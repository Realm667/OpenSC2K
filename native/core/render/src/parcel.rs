//! Pack-local parcel decals, cached once and batched with ordinary city sprites.
use crate::sprites::{Artwork, Sprite, Sprites};

const FIRST: i32 = 2_000_000;

fn pixel(x: f64, y: f64, width: f64, border: [u8; 4], material: u8) -> [u8; 4] {
    let u = (x - width / 2.0) / width + y * 2.0 / width;
    let v = -(x - width / 2.0) / width + y * 2.0 / width;
    if !(0.0..=1.0).contains(&u) || !(0.0..=1.0).contains(&v) {
        return [0; 4];
    }
    let edge = u.min(v).min(1.0 - u).min(1.0 - v) * width / 2.0;
    if edge < 0.65 && border[3] != 0 {
        return border;
    }
    let mut rgb = match material {
        0 => return [0; 4],
        3 => [103, 85, 59],
        4 => [77, 76, 66],
        5 => [153, 151, 136],
        _ => [76, 85, 88],
    };
    let curb = matches!(material, 2 | 4 | 6) && edge < 1.65;
    if curb {
        rgb = [154, 154, 141];
    }
    let a = (u * width * 2.0).floor() as i32;
    let b = (v * width * 2.0).floor() as i32;
    // Stable world-plane grain; no simulation random state or frame updates.
    let noise = ((a * 17 + b * 31 + a * b * 7).rem_euclid(9) - 4) as i16;
    if material == 5 && (a.rem_euclid(16) == 0 || b.rem_euclid(16) == 0) {
        rgb = [126, 128, 119];
    }
    if material == 6 && !curb && ((u > 0.76 && u < 0.94 && b.rem_euclid(20) < 2) || (v > 0.76 && v < 0.94 && a.rem_euclid(20) < 2)) {
        rgb = [177, 174, 150];
    }
    if material == 3 && (a * 11 + b * 23).rem_euclid(113) < 3 {
        rgb = [131, 120, 97];
    }
    [
        ((rgb[0] as i16 + noise).clamp(0, 255)) as u8,
        ((rgb[1] as i16 + noise).clamp(0, 255)) as u8,
        ((rgb[2] as i16 + noise).clamp(0, 255)) as u8,
        255,
    ]
}

impl Sprites {
    pub fn add_parcel(&mut self, id: i32, border: [u8; 4], material: u8, divisor: i32) -> Result<(), String> {
        let source = id as u64 * 2;
        if !self.images.contains_key(&source) || material > 6 || ![1, 2, 4].contains(&divisor) {
            return Err("invalid parcel source".into());
        }
        let width = self.footprint_width(source);
        if width < 32 / divisor || width > 128 / divisor || width % (32 / divisor) != 0 {
            return Err("invalid parcel footprint".into());
        }
        let signature = (width, border, material);
        if let Some(&cached) = self.parcel_cache.get(&signature) {
            self.parcels.insert(source, cached);
            return Ok(());
        }
        let parcel_id = FIRST + self.parcel_cache.len() as i32;
        let height = width / 2 + 1;
        let density = 4 * divisor;
        let large_width = f64::from(width * divisor);
        let mut logical = Sprite {
            w: width,
            h: height,
            rgba: Vec::new(),
            la: Vec::new(),
        };
        for y in 0..height {
            for x in 0..width {
                let color = pixel(f64::from(x * divisor) + 0.5, f64::from(y * divisor), large_width, border, material);
                logical.rgba.extend(color);
                logical.la.extend([1, color[3]]);
            }
        }
        let mut art = Sprite {
            w: width * density,
            h: height * density,
            rgba: Vec::new(),
            la: Vec::new(),
        };
        for y in 0..art.h {
            for x in 0..art.w {
                let color = pixel(
                    (f64::from(x) + 0.5) / 4.0,
                    (f64::from(y) + 0.5) / 4.0,
                    large_width,
                    border,
                    material,
                );
                art.rgba.extend(color);
            }
        }
        let key = parcel_id as u64 * 2;
        if material == 0 {
            self.unshaded_parcels.insert(key);
        }
        self.images.insert(key, logical);
        self.artwork.insert(
            key,
            Artwork {
                image: art,
                height,
                frames: 1,
                fps: 0,
            },
        );
        self.parcels.insert(source, parcel_id);
        self.parcel_cache.insert(signature, parcel_id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn parcel_is_optional_shared_and_registered_to_ground_not_art_padding() {
        for divisor in [1, 2, 4] {
            let width = 64 / divisor;
            let sprite = Sprite {
                w: width + 8,
                h: 80,
                rgba: vec![],
                la: vec![],
            };
            let mut sprites = Sprites::new(HashMap::from([(2286, sprite.clone()), (2288, sprite)]), [0; 4]);
            assert!(sprites.parcels.is_empty());
            for id in [1143, 1144] {
                sprites.registration.insert(id * 2, [width, 4, 4]);
                sprites.add_parcel(id as i32, [0, 128, 0, 255], 2, divisor).unwrap();
            }
            assert_eq!(sprites.parcel_cache.len(), 1);
            assert_eq!(sprites.parcels[&2286], sprites.parcels[&2288]);
            let key = sprites.parcels[&2286] as u64 * 2;
            assert_eq!(sprites.images[&key].w, width);
            assert_eq!(sprites.artwork[&key].image.w, 256);
            assert_eq!(sprites.canvas_padding(key), (0, 0));
        }
    }

    #[test]
    fn parcel_has_transparent_exterior_and_no_invented_contour() {
        assert_eq!(pixel(0.0, 0.0, 64.0, [0, 128, 0, 255], 2), [0; 4]);
        assert_eq!(pixel(32.0, 32.0, 64.0, [0, 128, 0, 255], 0), [0, 128, 0, 255]);
        assert_eq!(pixel(32.0, 32.0, 64.0, [0; 4], 0), [0; 4]);
        for style in 1..=6 {
            assert_eq!(pixel(32.0, 16.0, 64.0, [0; 4], style)[3], 255);
        }
    }
}
