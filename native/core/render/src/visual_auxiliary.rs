//! Cosmetic sprite data follows the original atlas, silhouette and painter order.
use crate::{
    Draw, Rect,
    sprites::{ARTWORK_PADDING, ARTWORK_SLOT, Artwork, Sprite, Sprites},
};
use std::collections::{HashMap, HashSet};

/// One worker's immutable mask sources and incrementally populated atlas.
/// New sprite slots do not repaint masks that have already been prepared.
#[derive(Default)]
pub struct AtlasCache {
    edge: i32,
    slots: HashSet<u64>,
    pixels: Vec<u8>,
}

impl AtlasCache {
    pub fn update(&mut self, edge: i32, slots: &HashMap<u64, Rect>, sprites: &Sprites, artwork: &HashMap<u64, Sprite>) -> &[u8] {
        if edge != self.edge {
            let mut pixels = vec![0; edge as usize * edge as usize * 4];
            let width = self.edge.min(edge) as usize * 4;
            for row in 0..self.edge.min(edge) as usize {
                pixels[row * edge as usize * 4..row * edge as usize * 4 + width]
                    .copy_from_slice(&self.pixels[row * self.edge as usize * 4..row * self.edge as usize * 4 + width]);
            }
            self.pixels = pixels;
            self.edge = edge;
        }
        for (&key, rect) in slots {
            if self.slots.insert(key) {
                paint_slot(&mut self.pixels, edge, key, rect, sprites, artwork);
            }
        }
        &self.pixels
    }
}

fn sample(key: u64, sprite: &Sprite, artwork: &HashMap<u64, Sprite>, x: i32, y: i32) -> [u8; 4] {
    let base = if key & (1 << 32) != 0 { (key >> 16) & 0xffff } else { key };
    let Some(mask) = artwork.get(&(base & !1)) else {
        return [0; 4];
    };
    if mask.w != sprite.w || mask.h != sprite.h {
        return [0; 4];
    }
    let sx = if base & 1 != 0 { mask.w - 1 - x } else { x };
    let at = ((y * mask.w + sx) * 4) as usize;
    let alpha = sprite.la[((y * sprite.w + x) * 2 + 1) as usize];
    let mut out: [u8; 4] = mask.rgba[at..at + 4].try_into().unwrap();
    out[3] = ((u16::from(out[3]) * u16::from(alpha)) / 255) as u8;
    out
}

// HD art keeps the original logical width and bottom edge. Repeat the mask
// per animation frame, using exactly the padding layout of Atlas::artwork_slot.
fn artwork_sample(key: u64, source: &Artwork, sprite: &Sprite, masks: &HashMap<u64, Sprite>, x: i32, y: i32) -> [u8; 4] {
    let frames = i32::from(source.frames.max(1));
    let frame_height = source.image.h / frames;
    let stride = if frames > 1 {
        frame_height + ARTWORK_PADDING * 2
    } else {
        frame_height
    };
    let row = if frames > 1 {
        (y % stride - ARTWORK_PADDING).clamp(0, frame_height - 1)
    } else {
        y
    };
    let frame = y / stride;
    let alpha = source.image.rgba[(((frame * frame_height + row) * source.image.w + x) * 4 + 3) as usize];
    // Authored master masks share the artwork's texel grid. A tagged entry
    // cannot be confused with the logical mask used by CPU and water paths.
    // Atlas UVs mirror art and auxiliary channels together at draw time.
    if let Some(mask) = masks.get(&((key & !1) | ARTWORK_SLOT)) {
        if mask.w != source.image.w || (mask.h != frame_height && mask.h != source.image.h) {
            return [0; 4];
        }
        let mask_row = if mask.h == frame_height { row } else { frame * frame_height + row };
        let at = ((mask_row * mask.w + x) * 4) as usize;
        let mut color: [u8; 4] = mask.rgba[at..at + 4].try_into().unwrap();
        color[3] = ((u16::from(color[3]) * u16::from(alpha)) / 255) as u8;
        return color;
    }
    let sx = x * sprite.w / source.image.w;
    let sy = row * source.height / frame_height - (source.height - sprite.h);
    if sy < 0 || sy >= sprite.h {
        return [0; 4];
    }
    let mut color = sample(key, sprite, masks, sx, sy);
    color[3] = ((u16::from(color[3]) * u16::from(alpha)) / 255) as u8;
    color
}

pub fn atlas(edge: i32, slots: &HashMap<u64, Rect>, sprites: &Sprites, artwork: &HashMap<u64, Sprite>) -> Vec<u8> {
    let mut out = vec![0; edge as usize * edge as usize * 4];
    for (&key, rect) in slots {
        paint_slot(&mut out, edge, key, rect, sprites, artwork);
    }
    out
}

fn paint_slot(out: &mut [u8], edge: i32, key: u64, rect: &Rect, sprites: &Sprites, artwork: &HashMap<u64, Sprite>) {
    let original_key = key & !ARTWORK_SLOT;
    let Some(sprite) = sprites.images.get(&original_key) else {
        return;
    };
    let hd = if key & ARTWORK_SLOT != 0 {
        sprites.artwork.get(&original_key)
    } else {
        None
    };
    for y in 0..rect.h {
        for x in 0..rect.w {
            let color = match hd {
                Some(source) => artwork_sample(original_key, source, sprite, artwork, x, y),
                None => sample(key, sprite, artwork, x, y),
            };
            let at = (((rect.y + y) * edge + rect.x + x) * 4) as usize;
            out[at..at + 4].copy_from_slice(&color);
        }
    }
}

pub fn raster(bounds: Rect, draws: &[Draw], sprites: &HashMap<u64, Sprite>, artwork: &HashMap<u64, Sprite>, emission: bool) -> Vec<u8> {
    let mut out = vec![0; bounds.w as usize * bounds.h as usize * 4];
    for draw in draws {
        if draw.shadow {
            continue;
        }
        let Some(sprite) = sprites.get(&draw.image) else {
            continue;
        };
        let clipped = draw.rect.clip(bounds);
        for y in clipped.y..clipped.y + clipped.h {
            for x in clipped.x..clipped.x + clipped.w {
                let sx = x - draw.rect.x;
                let sy = y - draw.rect.y;
                if sprite.la[((sy * sprite.w + sx) * 2 + 1) as usize] == 0 {
                    continue;
                }
                let at = (((y - bounds.y) * bounds.w + x - bounds.x) * 4) as usize;
                // An opaque non-emissive foreground pixel clears lights behind it.
                let color = if emission && draw.emission_disabled {
                    [0; 4]
                } else {
                    sample(draw.image, sprite, artwork, sx, sy)
                };
                out[at..at + 4].copy_from_slice(&color);
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn incremental_atlas_matches_full_after_additions_and_growth() {
        let red = sprite(vec![255, 0, 0, 255], &[255]);
        let blue = sprite(vec![0, 0, 255, 255], &[255]);
        let sprites = Sprites::new(HashMap::from([(2, red.clone()), (4, blue.clone())]), [0; 4]);
        let masks = HashMap::from([(2, red), (4, blue)]);
        let mut slots = HashMap::from([(2, Rect::new(1, 1, 1, 1))]);
        let mut cache = AtlasCache::default();
        assert_eq!(cache.update(8, &slots, &sprites, &masks), atlas(8, &slots, &sprites, &masks));
        slots.insert(4, Rect::new(9, 2, 1, 1));
        assert_eq!(cache.update(16, &slots, &sprites, &masks), atlas(16, &slots, &sprites, &masks));
        assert_eq!(cache.update(16, &slots, &sprites, &masks), atlas(16, &slots, &sprites, &masks));
    }
    fn sprite(rgba: Vec<u8>, alpha: &[u8]) -> Sprite {
        Sprite {
            w: alpha.len() as i32,
            h: 1,
            rgba,
            la: alpha.iter().flat_map(|a| [0, *a]).collect(),
        }
    }

    #[test]
    fn authored_master_masks_keep_subpixel_detail_and_distinct_animation_frames() {
        use crate::sprites::Atlas;
        let mut sprites = Sprites::new(HashMap::from([(2, sprite(vec![0; 8], &[255, 255]))]), [0; 4]);
        let source = Sprite {
            w: 8,
            h: 8,
            rgba: vec![255; 8 * 8 * 4],
            la: Vec::new(),
        };
        sprites.artwork.insert(
            2,
            Artwork {
                image: source,
                height: 1,
                frames: 2,
                fps: 8,
            },
        );
        let mut mask = Sprite {
            w: 8,
            h: 8,
            rgba: vec![0; 8 * 8 * 4],
            la: Vec::new(),
        };
        let red = [231, 143, 61, 191];
        let blue = [92, 144, 210, 255];
        mask.rgba[(2 * 8 + 1) * 4..(2 * 8 + 2) * 4].copy_from_slice(&red);
        mask.rgba[(6 * 8 + 6) * 4..(6 * 8 + 7) * 4].copy_from_slice(&blue);
        let masks = HashMap::from([(2 | ARTWORK_SLOT, mask)]);
        let mut packed = Atlas::new(32);
        let slot = packed.artwork_slot(2, &sprites.artwork[&2]).unwrap();
        let rgba = atlas(packed.edge, &packed.slots, &sprites, &masks);
        let pixel = |x: i32, y: i32| -> &[u8] {
            let at = (((slot.y + y) * packed.edge + slot.x + x) * 4) as usize;
            &rgba[at..at + 4]
        };
        assert_eq!(pixel(1, 4), red, "one master texel survives inside a four-texel logical pixel");
        assert_eq!(pixel(0, 4), [0; 4], "light must not spread to its neighbor");
        assert_eq!(pixel(6, 12), blue, "the second frame has independent lighting");
        assert_eq!(pixel(1, 12), [0; 4], "the first frame is not repeated over the second");
        assert_eq!(
            sample(2, &sprites.images[&2], &masks, 0, 0),
            [0; 4],
            "HD entries cannot enter the logical path"
        );
    }

    #[test]
    fn master_masks_repeat_static_frames_clip_alpha_and_reject_wrong_dimensions() {
        let original = sprite(vec![0; 4], &[255]);
        let mut source = Artwork {
            image: Sprite {
                w: 4,
                h: 8,
                rgba: vec![255; 4 * 8 * 4],
                la: Vec::new(),
            },
            height: 1,
            frames: 2,
            fps: 8,
        };
        let mask = Sprite {
            w: 4,
            h: 4,
            rgba: vec![255; 4 * 4 * 4],
            la: Vec::new(),
        };
        let masks = HashMap::from([(2 | ARTWORK_SLOT, mask)]);
        source.image.rgba[3] = 0;
        assert_eq!(artwork_sample(2, &source, &original, &masks, 0, 0)[3], 0);
        assert_eq!(artwork_sample(2, &source, &original, &masks, 0, 8), [255; 4]);
        assert_eq!(artwork_sample(2, &source, &original, &masks, 1, 7), [255; 4]);
        let wrong = HashMap::from([(
            2 | ARTWORK_SLOT,
            Sprite {
                w: 4,
                h: 3,
                rgba: vec![255; 48],
                la: Vec::new(),
            },
        )]);
        assert_eq!(artwork_sample(2, &source, &original, &wrong, 0, 8), [0; 4]);
        // A still source uses the same physical sampling without frame padding.
        source.frames = 1;
        source.image.h = 4;
        source.image.rgba.truncate(64);
        assert_eq!(artwork_sample(2, &source, &original, &masks, 3, 3), [255; 4]);
    }
    #[test]
    fn colors_gradients_flips_and_traffic_keep_the_original_silhouette() {
        let artwork = HashMap::from([(2, sprite(vec![255, 0, 0, 64, 0, 128, 255, 192], &[255, 255]))]);
        let original = sprite(vec![0; 8], &[255, 255]);
        assert_eq!(sample(2, &original, &artwork, 0, 0), [255, 0, 0, 64]);
        assert_eq!(sample(3, &original, &artwork, 0, 0), [0, 128, 255, 192]);
        let traffic = sprite(vec![0; 8], &[0, 255]);
        assert_eq!(sample((1 << 32) | (2 << 16), &traffic, &artwork, 0, 0)[3], 0);
        assert_eq!(sample((1 << 32) | (2 << 16), &traffic, &artwork, 1, 0), [0, 128, 255, 192]);
    }
    #[test]
    fn foreground_clears_hidden_emission_and_transparency_keeps_it() {
        let sprites = HashMap::from([(2, sprite(vec![0; 8], &[255, 255])), (4, sprite(vec![0; 8], &[255, 0]))]);
        let artwork = HashMap::from([(2, sprite(vec![255; 8], &[255, 255]))]);
        let bounds = Rect::new(0, 0, 2, 1);
        let draws = [Draw::new(2, bounds), Draw::new(4, bounds)];
        assert_eq!(
            raster(bounds, &draws, &sprites, &artwork, true),
            vec![0, 0, 0, 0, 255, 255, 255, 255]
        );
        let slots = HashMap::from([(2, bounds)]);
        assert_eq!(atlas(2, &slots, &Sprites::new(sprites, [0; 4]), &artwork)[..8], [255; 8]);
    }

    #[test]
    fn unpowered_foreground_blocks_lights_but_keeps_seasons() {
        let sprites = HashMap::from([(2, sprite(vec![0; 8], &[255, 255]))]);
        let masks = HashMap::from([(2, sprite(vec![255; 8], &[255, 255]))]);
        let bounds = Rect::new(0, 0, 2, 1);
        let mut front = Draw::new(2, Rect::new(0, 0, 1, 1));
        front.emission_disabled = true;
        let draws = [Draw::new(2, bounds), front];
        assert_eq!(raster(bounds, &draws, &sprites, &masks, true), [vec![0; 4], vec![255; 4]].concat());
        assert_eq!(raster(bounds, &draws, &sprites, &masks, false), vec![255; 8]);
    }

    #[test]
    fn hd_masks_follow_density_bottom_alignment_and_padded_animation_frames() {
        use crate::sprites::Atlas;
        let mut sprites = Sprites::new(HashMap::from([(2, sprite(vec![0; 8], &[255, 255]))]), [0; 4]);
        let masks = HashMap::from([(2, sprite(vec![255, 0, 0, 255, 0, 255, 0, 128], &[255, 255]))]);
        let mut image = Sprite {
            w: 4,
            h: 8,
            rgba: vec![255; 4 * 8 * 4],
            la: vec![255; 4 * 8 * 2],
        };
        // A transparent HD pixel must not emit; another animation frame stays lit.
        image.rgba[(2 * 4 * 4) + 3] = 0;
        sprites.artwork.insert(
            2,
            Artwork {
                image,
                height: 2,
                frames: 2,
                fps: 8,
            },
        );
        let mut packed = Atlas::new(32);
        let slot = packed.artwork_slot(2, &sprites.artwork[&2]).unwrap();
        let rgba = atlas(packed.edge, &packed.slots, &sprites, &masks);
        let pixel = |x: i32, y: i32| -> &[u8] {
            let at = (((slot.y + y) * packed.edge + slot.x + x) * 4) as usize;
            &rgba[at..at + 4]
        };
        assert_eq!(
            pixel(0, 2),
            [0; 4],
            "taller art must not shift the bottom-aligned original mask upwards"
        );
        assert_eq!(pixel(0, 4)[3], 0, "transparent HD pixels clear emission");
        assert_eq!(pixel(1, 4), [255, 0, 0, 255]);
        assert_eq!(pixel(3, 4), [0, 255, 0, 128]);
        assert_eq!(pixel(0, 12), [255, 0, 0, 255], "each padded frame receives its own mask");
        assert_eq!(pixel(0, 15), pixel(0, 13), "bottom padding repeats the final frame row");
    }
}
