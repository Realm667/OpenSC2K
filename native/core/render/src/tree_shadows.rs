//! Cached canopy projections onto the actual terrain triangles, before trees
//! and buildings. Shared by indexed and full-color region rendering.
use crate::{Builder, Draw, Rect, region::Region};

pub const TAG: u8 = 56;
const MASKS: [u8; 15] = [0, 9, 3, 6, 12, 11, 7, 14, 13, 1, 2, 4, 8, 15, 0];
const ROOTS: [[i32; 2]; 7] = [[16, 25], [8, 24], [24, 24], [16, 19], [9, 19], [23, 19], [16, 30]];
// Sun from upper left, consistent with the authored buildings. Horizontal
// displacement in tile units per altitude level; it does not change with zoom.
const LIGHT: [f32; 2] = [0.38, -0.12];
type Vertex = [f32; 4]; // screen x/y and projected canopy u/v

fn faces(mask: u8) -> [[usize; 3]; 2] {
    if [1, 4, 11, 14].contains(&mask) {
        [[0, 1, 3], [1, 2, 3]]
    } else {
        [[0, 1, 2], [0, 2, 3]]
    }
}

fn corners(x: i32, y: i32, altitude: f32, mask: u8) -> [[f32; 3]; 4] {
    let mut points = [
        [x as f32 - 0.5, y as f32 - 0.5, altitude],
        [x as f32 + 0.5, y as f32 - 0.5, altitude],
        [x as f32 + 0.5, y as f32 + 0.5, altitude],
        [x as f32 - 0.5, y as f32 + 0.5, altitude],
    ];
    for (i, point) in points.iter_mut().enumerate() {
        point[2] += f32::from((mask >> i) & 1);
    }
    points
}

#[cfg(test)]
fn ground_height(point: [f32; 2], x: i32, y: i32, altitude: f32, mask: u8) -> f32 {
    let p = corners(x, y, altitude, mask);
    for face in faces(mask) {
        let [a, b, c] = face.map(|i| p[i]);
        let u = [b[0] - a[0], b[1] - a[1]];
        let v = [c[0] - a[0], c[1] - a[1]];
        let q = [point[0] - a[0], point[1] - a[1]];
        let det = u[0] * v[1] - u[1] * v[0];
        let s = (q[0] * v[1] - q[1] * v[0]) / det;
        let t = (u[0] * q[1] - u[1] * q[0]) / det;
        if s >= -0.0001 && t >= -0.0001 && s + t <= 1.0001 {
            return a[2] + s * (b[2] - a[2]) + t * (c[2] - a[2]);
        }
    }
    altitude
}

fn clip(mut polygon: Vec<Vertex>, axis: usize, limit: f32, sign: f32) -> Vec<Vertex> {
    let input = std::mem::take(&mut polygon);
    let Some(&last) = input.last() else {
        return polygon;
    };
    let mut previous = last;
    for point in input {
        let a = (previous[axis] - limit) * sign;
        let b = (point[axis] - limit) * sign;
        if (a >= 0.0) != (b >= 0.0) {
            let t = a / (a - b);
            polygon.push(std::array::from_fn(|i| previous[i] + (point[i] - previous[i]) * t));
        }
        if b >= 0.0 {
            polygon.push(point);
        }
        previous = point;
    }
    polygon
}

fn canopy_uv(point: [f32; 3], crown: [f32; 3], radius: f32) -> [f32; 2] {
    [
        (point[0] - crown[0] - LIGHT[0] * (crown[2] - point[2])) / radius,
        (point[1] - crown[1] - LIGHT[1] * (crown[2] - point[2])) / radius,
    ]
}

pub fn append(builder: &Builder, out: &mut Region, draw: &Draw, bounds: Rect) {
    let city = &builder.city;
    if !builder.config.natural_forests
        || builder.config.underground
        || draw.moving
        || draw.depth < 0
        || !matches!(draw.sprite.rem_euclid(500), 256..=268)
        || draw.surface_grid == 0
    {
        return;
    }
    let y = (draw.depth % i64::from(city.edge)) as i32;
    let x = (draw.depth / i64::from(city.edge)) as i32 - y;
    if x < 0 || y < 0 || x >= city.edge || y >= city.edge {
        return;
    }
    let i = city.index(x, y);
    if city.wet(i) || !city.visible(i) {
        return;
    }
    let shape = city.surface(x, y) as usize;
    let Some(&mask) = MASKS.get(shape) else {
        return;
    };
    let c = builder.config;
    let points = corners(x, y, city.land(i) as f32, mask);
    for nx in (x - 1).max(0)..=(x + 1).min(city.edge - 1) {
        for ny in (y - 1).max(0)..=(y + 1).min(city.edge - 1) {
            let n = city.index(nx, ny);
            let density = i32::from(city.buildings[n]) - 5;
            if !(1..=7).contains(&density) || city.wet(n) || !city.visible(n) {
                continue;
            }
            let selected = builder.forest_sprite(nx, ny, c.base() + i32::from(city.buildings[n]));
            // Only the enhanced woodland uses this documented root layout.
            if selected < crate::nature::FIRST {
                continue;
            }
            let group = (selected - crate::nature::FIRST) / crate::nature::SPAN;
            let variant = group % 8;
            let neighbors = group / 8;
            let source_mask = MASKS.get(city.surface(nx, ny) as usize).copied().unwrap_or(0);
            for tree in 0..density {
                let seed = tree * 29 + variant * 47 + density * 13;
                let [mut rx, mut ry] = if density == 1 { [16, 27] } else { ROOTS[tree as usize] };
                rx += seed % 5 - 2;
                ry += (seed / 5) % 3 - 1;
                let side = if rx > 16 {
                    if ry < 25 { 0 } else { 1 }
                } else if ry < 25 {
                    3
                } else {
                    2
                };
                if density >= 4 && neighbors & (1 << side) != 0 {
                    rx += if rx > 16 { 1 } else { -1 };
                }
                let root = [
                    nx as f32 + (rx - 16) as f32 / 32.0 + (ry - 27) as f32 / 16.0,
                    ny as f32 - (rx - 16) as f32 / 32.0 + (ry - 27) as f32 / 16.0,
                ];
                let height = [18.0, 14.0, 14.0, 18.0, 14.0, 18.0][seed as usize % 6];
                let radius = [9.0, 8.0, 11.0, 10.0, 13.0, 10.0][seed as usize % 6] / 32.0;
                let crown = [
                    root[0],
                    root[1],
                    // Match the sprite baseline, including fully raised ground. Slopes
                    // affect the receiver, not the existing tree sprite baseline.
                    city.object(n) as f32 + f32::from(source_mask == 15) + height / 18.0,
                ];
                for face in faces(mask) {
                    let mut polygon: Vec<Vertex> = face
                        .iter()
                        .map(|&index| {
                            let p = points[index];
                            let uv = canopy_uv(p, crown, radius);
                            [
                                c.side() as f32 + (city.edge as f32 + p[0] - p[1] + 1.0) * c.hw() as f32,
                                c.top() as f32 + (p[0] + p[1] + 1.0) * c.hh() as f32 - p[2] * c.step() as f32,
                                uv[0],
                                uv[1],
                            ]
                        })
                        .collect();
                    // Back-facing steep terrain does not receive a visible shadow.
                    let [a, b, d] = [polygon[0], polygon[1], polygon[2]];
                    if (b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0]) <= 0.0001 {
                        continue;
                    }
                    for (axis, limit, sign) in [
                        (2, -1.0, 1.0),
                        (2, 1.0, -1.0),
                        (3, -1.0, 1.0),
                        (3, 1.0, -1.0),
                        (0, bounds.x as f32, 1.0),
                        (0, (bounds.x + bounds.w) as f32, -1.0),
                        (1, bounds.y as f32, 1.0),
                        (1, (bounds.y + bounds.h) as f32, -1.0),
                    ] {
                        polygon = clip(polygon, axis, limit, sign);
                    }
                    if polygon.len() < 3 {
                        continue;
                    }
                    let first = out.vertices.len() as i32;
                    for point in &polygon {
                        out.vertices.push([point[0] - bounds.x as f32, point[1] - bounds.y as f32]);
                        out.uvs.push([point[2], point[3]]);
                        out.colors.push([f32::from(TAG) / 255.0, 0.0, 0.0, 1.0]);
                    }
                    for at in 1..polygon.len() - 1 {
                        out.indices.extend([first, first + at as i32, first + at as i32 + 1]);
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ground_faces_keep_all_raised_corners_and_both_diagonals() {
        for mask in MASKS {
            for p in corners(4, 5, 3.0, mask) {
                assert!((ground_height([p[0], p[1]], 4, 5, 3.0, mask) - p[2]).abs() < 0.0001);
            }
        }
    }
    #[test]
    fn light_projection_changes_with_receiver_height() {
        let crown = [4.0, 5.0, 8.0];
        for height in [3.0, 3.5, 4.0, 7.0] {
            let receiver = [
                crown[0] + LIGHT[0] * (crown[2] - height),
                crown[1] + LIGHT[1] * (crown[2] - height),
                height,
            ];
            let uv = canopy_uv(receiver, crown, 0.3);
            assert!(uv[0].abs() < 0.00001 && uv[1].abs() < 0.00001);
        }
    }
    #[test]
    fn region_clipping_preserves_projected_uvs() {
        let p = vec![[0.0, 0.0, -1.0, -1.0], [10.0, 0.0, 1.0, -1.0], [10.0, 10.0, 1.0, 1.0]];
        for v in clip(p, 0, 5.0, 1.0) {
            assert!(v[0] >= 5.0);
            assert!((v[2] - (v[0] / 5.0 - 1.0)).abs() < 0.00001);
        }
    }
}
