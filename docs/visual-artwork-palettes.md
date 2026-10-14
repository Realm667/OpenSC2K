# Visual artwork palettes

A `visual_artwork` record can optionally include `palette_swap`, an array of
1–256 colors written as eight hexadecimal RGBA digits (for example `66818dff`).
Its `png` then contains numeric indices, not visible colors: every source pixel
must be opaque with equal red, green and blue channels, and its red value is the
zero-based palette index. Grayscale PNGs are supported. Alpha comes exclusively
from the selected palette entry, so antialiased edges and transparent pixels can
be reproduced exactly. Logical dimensions and the 4x master scale are unchanged.

```json
{
  "key": "person/0/0/0",
  "png": "visual/palettes/person-0-0.png",
  "logical_size": [3, 6],
  "master_scale": 4,
  "palette_swap": ["00000000", "66818dff"]
}
```

Records may share an index image with different palettes. The loader decodes
each PNG once, caches identical image/palette combinations, and expands variants
once at pack load. These RGBA images enter the existing city-life GPU atlas;
there is no recoloring or extra material per figure per frame. Lightmaps and
season masks remain ordinary images and can independently share file paths.
Invalid palettes, indices, sizes or memory budgets reject the whole artwork set.
Records without `palette_swap` keep their existing RGBA behavior. Caches belong
to the loaded artwork instance and do not survive switching to another pack.

The RS conversion preserves all 432 vehicle and 96 pedestrian variants exactly,
including body shapes, skin tones, transparency and 432 emission masks. It uses
85 index PNGs and 49 unique lightmap PNGs instead of 960 separate files. File
counts and source PNG decoding decrease; final GPU atlas dimensions are unchanged.
This is not a claim of higher frame rate or reduced atlas memory.

RS omits `cloud/*` overrides deliberately. `CityVisualClouds.artwork_atlas`
therefore uses the same built-in Visual Enhancement atlases as SC2K, with the
existing weather, movement and cloud-shadow behavior. No original game files
are copied into the RS pack.
