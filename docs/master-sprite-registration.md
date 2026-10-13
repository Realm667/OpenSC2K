# Master sprite canvas registration

Graphics packs with `master_sprites` use indexed PNGs at four pixels per logical
pixel. The loader derives all three views from these masters. Changes to the
art and emission mask belong to that graphics pack; sprite IDs alone never
select global size or position overrides.

A building master (ID 1112 through 1255) can retain its original parcel when
its image needs a larger transparent canvas:

```json
{
  "id": 1112,
  "png": "masters/1112.png",
  "logical_size": [40, 24],
  "visual_registration": [32, 4, 4],
  "lightmap": "lightmaps/1112.png"
}
```

`visual_registration` is `[footprint_width, left_padding, bottom_padding]`
in large-view logical pixels. Values are nonnegative multiples of four; the
footprint width is a positive multiple of 32. The footprint and left padding
must fit the canvas, whose width must also be a multiple of four. Bottom
padding must be less than its height. Values must not exceed 1024.

The painter subtracts left padding from its original X position and adds
bottom padding to the bottom-aligned canvas baseline. Horizontal flips use
the opposite margin. Extra height above the baseline needs no separate value.
Ground parcels and water reflection contacts keep their original geometry.
Conservative region bounds include the extra bottom margin. These values are
held by the loaded archive and are cleared when a different archive replaces
the sprite, including SCURK replacements. They never enter city documents.

Optional `artwork_rgba` names a full-color PNG with exactly the same dimensions
as the indexed master. It preserves partial transparency such as glass. The
indexed image still supplies picking and mask geometry. This option cannot be
combined with an animation record. Paths use the pack's existing validated
relative-path reader and images count toward its decoded-memory budget.

Art, indexed silhouette, and lightmap must share the same transformation and
canvas. Scale and translation can be baked into these pack-owned files; the
runtime does not need a global correction table. Missing registration retains
the existing bottom-aligned behavior.

The RS review gallery also reads `review_reference_size` and `review_padding`
to keep its original reference grid fixed. These are review metadata, not
runtime placement instructions. `placement-review.json` records the source
hashes, user transforms, and applied notes so they are not applied twice.
