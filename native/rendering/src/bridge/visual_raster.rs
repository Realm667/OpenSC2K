//! Bulk presentation-only light raster operations. No city or simulation state.
use godot::{
    classes::{Image, image::Format},
    prelude::*,
};

#[derive(GodotClass)]
#[class(base=Object, no_init)]
pub struct NativeVisualRaster {}

fn float_at(data: &[u8], offset: usize) -> f32 {
    f32::from_le_bytes(data[offset..offset + 4].try_into().expect("float image pixel"))
}

fn image(size: Vector2i, format: Format, data: &[u8]) -> Option<Gd<Image>> {
    Image::create_from_data(size.x, size.y, false, format, &PackedByteArray::from(data))
}

fn encode_patch(output: &mut [u8], size: Vector2i, source: &Gd<Image>, destination: Vector2i, world_origin: Vector2) {
    let source_size = source.get_size();
    let overlap = Rect2i::new(destination, source_size)
        .intersect(Rect2i::new(Vector2i::ZERO, size))
        .unwrap_or_default();
    let input = source.get_data();
    let input = input.as_slice();
    for y in overlap.position.y..overlap.end().y {
        for x in overlap.position.x..overlap.end().x {
            let at = (((y - destination.y) * source_size.x + x - destination.x) * 16) as usize;
            if float_at(input, at + 12) <= 0.0 {
                continue;
            }
            let local = Vector2::new(float_at(input, at), float_at(input, at + 4)) - world_origin + Vector2::new(4.0, 4.0);
            let u = (local.x * 512.0).round().clamp(0.0, 4095.0) as u32;
            let v = (local.y * 512.0).round().clamp(0.0, 4095.0) as u32;
            let out = ((y * size.x + x) * 4) as usize;
            output[out..out + 4].copy_from_slice(&[(u >> 4) as u8, (((u & 15) << 4) | (v >> 8)) as u8, (v & 255) as u8, 255]);
        }
    }
}

#[godot_api]
impl NativeVisualRaster {
    /// Rasterize one already-projected road plane, preserving RGBAF world coordinates.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn road_patch(
        bounds: Rect2i,
        inverse: Transform2D,
        scale: i64,
        tile: Vector2,
        start: Vector2,
        along: Vector2,
        side: Vector2,
        diagonal: bool,
    ) -> Option<Gd<Image>> {
        if bounds.size.x <= 0 || bounds.size.y <= 0 || scale <= 0 {
            return None;
        }
        let mut pixels = vec![0_u8; (bounds.size.x as usize) * (bounds.size.y as usize) * 16];
        for y in 0..bounds.size.y {
            for x in 0..bounds.size.x {
                let point = Vector2::new((bounds.position.x + x) as f32 + 0.5, (bounds.position.y + y) as f32 + 0.5) / scale as f32;
                let uv = inverse * point;
                let local = start + along * uv.x + side * (uv.y - 0.5);
                let covered = (0.0..=1.0).contains(&uv.y)
                    && if diagonal {
                        local.x.abs() <= 0.5 && local.y.abs() <= 0.5
                    } else {
                        (0.0..=1.0).contains(&uv.x)
                    };
                if !covered {
                    continue;
                }
                let world = tile + local;
                let offset = ((y * bounds.size.x + x) * 16) as usize;
                for (channel, value) in [world.x, world.y, 0.0, 1.0].into_iter().enumerate() {
                    pixels[offset + channel * 4..offset + channel * 4 + 4].copy_from_slice(&value.to_le_bytes());
                }
            }
        }
        image(bounds.size, Format::RGBAF, &pixels)
    }

    /// Encode a clipped world-coordinate road into the compact HD receiver.
    #[func]
    fn encode_receiver(mut target: Gd<Image>, source: Gd<Image>, destination: Vector2i, world_origin: Vector2) {
        if target.get_format() != Format::RGBA8 || source.get_format() != Format::RGBAF {
            return;
        }
        let size = target.get_size();
        let mut output = target.get_data().to_vec();
        encode_patch(&mut output, size, &source, destination, world_origin);
        target.set_data(size.x, size.y, false, Format::RGBA8, &PackedByteArray::from(output.as_slice()));
    }

    /// Compose all road patches into one buffer, avoiding a receiver copy per patch.
    #[func]
    fn headlight_receiver(size: Vector2i, origin: Vector2i, patches: VarArray, world_origin: Vector2) -> Option<Gd<Image>> {
        if size.x <= 0 || size.y <= 0 {
            return None;
        }
        let mut pixels = vec![0_u8; size.x as usize * size.y as usize * 4];
        for value in patches.iter_shared() {
            let patch = value.try_to::<VarDictionary>().ok()?;
            let source: Gd<Image> = patch.get("image")?.try_to().ok()?;
            let position: Vector2i = patch.get("origin")?.try_to().ok()?;
            if source.get_format() != Format::RGBAF {
                return None;
            }
            encode_patch(&mut pixels, size, &source, position - origin, world_origin);
        }
        image(size, Format::RGBA8, &pixels)
    }

    /// Coverage requires one channel, not four color channels per mask texel.
    #[func]
    fn alpha_mask(source: Gd<Image>) -> Option<Gd<Image>> {
        if source.get_format() != Format::RGBA8 {
            return None;
        }
        let data = source.get_data();
        let coverage: Vec<u8> = data.as_slice().chunks_exact(4).map(|pixel| pixel[3]).collect();
        image(source.get_size(), Format::R8, &coverage)
    }

    /// Assemble small instance streams in bulk; images and masks remain shared.
    #[func]
    fn figure_buffers(
        entries: VarArray,
        rectangles: VarDictionary,
        mask_origins: PackedVector2Array,
        layers: PackedInt32Array,
        origin: Vector2i,
        scale: i64,
        group_size: i64,
    ) -> Array<PackedFloat32Array> {
        let mut result = Array::new();
        if scale <= 0 || group_size <= 0 || mask_origins.len() != entries.len() || layers.len() != entries.len() {
            return result;
        }
        let group_size = group_size as usize;
        let mut transforms = vec![0.0_f32; group_size * 8];
        let mut parameters = vec![0.0_f32; group_size * 12];
        for (index, value) in entries.iter_shared().enumerate() {
            let entry = value.to::<VarDictionary>();
            let sprite = entry.get("sprite").unwrap().to::<Gd<Image>>();
            let rect = rectangles.get(sprite.instance_id().to_i64()).unwrap().to::<Rect2i>();
            let mut figure = entry.get("figure").unwrap().to::<Gd<RefCounted>>();
            let position = figure.get("position").to::<Vector2>();
            let previous = if figure.get("has_previous_position").to::<bool>() {
                figure.get("previous_position").to::<Vector2>()
            } else {
                position
            };
            let mut visual = entry.get("origin").unwrap().to::<Vector2i>().to_vector2();
            // Movement precision is independent of the selected artwork resolution.
            visual += position - position.round();
            let destination = visual - origin.to_vector2();
            let slot = index % group_size;
            let at = slot * 8;
            transforms[at] = (i64::from(rect.size.x) / scale) as f32;
            transforms[at + 3] = destination.x;
            transforms[at + 5] = (i64::from(rect.size.y) / scale) as f32;
            transforms[at + 7] = destination.y;
            let at = slot * 4;
            parameters[at..at + 4].copy_from_slice(&[
                rect.position.x as f32,
                rect.position.y as f32,
                rect.size.x as f32,
                rect.size.y as f32,
            ]);
            let at = group_size * 4 + at;
            parameters[at..at + 4].copy_from_slice(&[visual.x, visual.y, previous.x - position.x, previous.y - position.y]);
            let at = group_size * 8 + slot * 4;
            let mask = mask_origins[index];
            parameters[at..at + 4].copy_from_slice(&[
                mask.x,
                mask.y,
                layers[index] as f32,
                entry.get("opacity").unwrap().to::<f64>() as f32,
            ]);
            figure.set("previous_position", &position.to_variant());
            figure.set("has_previous_position", &true.to_variant());
            if slot + 1 == group_size || index + 1 == entries.len() {
                result.push(&PackedFloat32Array::from(transforms.as_slice()));
                result.push(&PackedFloat32Array::from(parameters.as_slice()));
                transforms.fill(0.0);
                parameters.fill(0.0);
            }
        }
        result
    }

    /// Shade an approach once. First patch owns overlapping road pixels.
    #[func]
    fn night_receiver(size: Vector2i, origin: Vector2i, patches: VarArray, lights: VarArray) -> Option<Gd<Image>> {
        if size.x <= 0 || size.y <= 0 {
            return None;
        }
        let mut pixels = vec![0_u8; (size.x as usize) * (size.y as usize) * 4];
        let lamps: Vec<(Vector2, Color, f64, f64)> = lights
            .iter_shared()
            .filter_map(|value| {
                let light = value.try_to::<VarDictionary>().ok()?;
                Some((
                    light.get("position")?.try_to().ok()?,
                    light.get("color")?.try_to().ok()?,
                    light.get("radius")?.try_to().ok()?,
                    light.get("intensity")?.try_to().ok()?,
                ))
            })
            .collect();
        for value in patches.iter_shared() {
            let patch = value.try_to::<VarDictionary>().ok()?;
            let source: Gd<Image> = patch.get("image")?.try_to().ok()?;
            let position: Vector2i = patch.get("origin")?.try_to().ok()?;
            if source.get_format() != Format::RGBAF {
                return None;
            }
            let source_size = source.get_size();
            let data = source.get_data();
            let data = data.as_slice();
            let placement = position - origin;
            let overlap = Rect2i::new(placement, source_size)
                .intersect(Rect2i::new(Vector2i::ZERO, size))
                .unwrap_or_default();
            for y in overlap.position.y..overlap.end().y {
                for x in overlap.position.x..overlap.end().x {
                    let out = ((y * size.x + x) * 4) as usize;
                    let at = (((y - placement.y) * source_size.x + x - placement.x) * 16) as usize;
                    if pixels[out + 3] != 0 || float_at(data, at + 12) <= 0.0 {
                        continue;
                    }
                    let world = Vector2::new(float_at(data, at), float_at(data, at + 4));
                    let mut color = Color::from_rgba(0.0, 0.0, 0.0, 1.0);
                    for &(position, tint, radius, intensity) in &lamps {
                        let distance = f64::from(world.distance_to(position));
                        let falloff = (1.0 - distance / radius).max(0.0).powf(1.6);
                        color += tint * falloff as f32 * intensity as f32;
                    }
                    for (channel, value) in [color.r, color.g, color.b].into_iter().enumerate() {
                        pixels[out + channel] = (value * 255.0).clamp(0.0, 255.0) as u8;
                    }
                    pixels[out + 3] = 255;
                }
            }
        }
        image(size, Format::RGBA8, &pixels)
    }
}
