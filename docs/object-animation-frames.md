# Numbered object animation frames

Use a numbered base filename for a master sprite. The loader discovers consecutive
files once when the pack loads. No frame list or duration list is needed.

```json
{
  "id": 1200,
  "png": "masters/1200.png",
  "logical_size": [40, 64],
  "artwork_rgba": "animation/objects/1200/TILE_1200_001.png"
}
```

Place `TILE_1200_002.png`, `TILE_1200_003.png`, and so on beside that base image.
The prefix is arbitrary; the final `_001.png` suffix starts discovery. A record
without `artwork_rgba` can instead use a numbered indexed `png` base. The indexed
master remains necessary for the renderer's logical geometry and semantic pixels.

- Without `_002.png`, the sprite is static: no animation strip is allocated.
- Every source frame lasts **125 ms (8 fps)**. Playback is 1, 2, 3, ... then 1.
  Two frames last 250 ms per loop; four last 500 ms. More frames lengthen the loop.
- Discovery stops at the first missing number. Files beyond a gap are ignored.
  Removing frame 2 therefore disables animation, even if frame 3 is still present.
- Up to 32 source frames are accepted, subject to the existing image-height and
  memory limits below. Existing RS detail animations use four source frames.
- All frames share dimensions, canvas anchor and resolution. Numbering does not
  introduce individual scaling or position overrides.
- A plain `lightmap` stays fixed. For animated emission, point `lightmap` at an
  indexed base such as `LIGHT_1200_001.png` and add consecutive matching masks.
  If mask 2 exists, every artwork phase must have a mask and there must be no
  extra consecutive mask. Invalid mask sequences reject the pack before activation.
  Art and emission share the same clock and frame index.
- An explicit `animation` field takes precedence for older packs. Original SC2K
  palette cycling remains unchanged. RS's 30 detail sequences use numbering;
  the 51 existing indexed sequences already use the same 125 ms frame interval.
- Detection finishes before pre-cache progress counting. Rendering does not scan
  files, decode images or upload textures on each frame. Reload the pack to pick
  up changed files.

# Explicit animation lists (compatibility)

A `master_sprites` record can provide one to 32 RGBA source frames. The files
use the same canvas, declared master resolution (2x for RS), registration and placement as its base art.
This is pack-local: original indexed SC2K graphics keep their palette cycling.
Existing indexed frame lists (including eight-frame traffic) are unchanged.

```json
"animation": {
  "format": "rgba",
  "frames": ["animation/object/0.png", "animation/object/1.png", "animation/object/2.png", "animation/object/3.png"],
  "lightmaps": ["animation/object/light-0.png", "animation/object/light-1.png", "animation/object/light-2.png", "animation/object/light-3.png"],
  "fps": 8,
  "durations_ms": [125, 250, 125, 250],
  "playback": "loop"
}
```

- Frame zero must exactly match the rendered base artwork (`artwork_rgba` when
  present, otherwise the indexed master rendered with its palette). Hidden RGB
  values under fully transparent pixels are ignored; alpha must match.
- `fps` is 8 by default, or 5. Each duration must be a positive integer multiple
  of its tick (125 ms at 8 fps, 200 ms at 5 fps). Omitted durations mean one tick.
- `playback` is `loop` by default. `ping_pong` plays 0,1,2,3,2,1, without repeating
  endpoints. Holds apply on both visits. One source frame is a stationary loop.
- Optional `lightmaps` has one file per source frame. A base `lightmap` is required
  and its pixels must match lightmap zero. Without this list the base mask stays
  constant. With no base mask, the animation is non-emissive. Masks must stay
  inside their corresponding frame's visible alpha, including when held.
- All files must be readable PNGs with exactly the base dimensions. RGBA frames
  need no indexed palette. Paths follow the existing safe pack-relative rules.
- The loader expands holds and ping-pong into a strip once. Maximum 32 internal
  frames, padded strip height 8192 pixels, existing decoded/atlas memory limits.
  An invalid list rejects the pack before activation. Large sprites may require
  shorter holds to fit. No image decoding or texture upload happens each tick.
- Playback uses the existing presentation clock, including pause behavior.
  Brightmaps sample the same strip frame. Water/wave shaders remain separate.

For modding, keep static buildings unchanged between frames and move only the
intended detail. Render motion in the object's isometric plane. A fast helicopter
rotor needs a blurred sweep; a wind turbine needs distinguishable blade phases.
Lightmap brightness can change with blinking artwork, but should not illuminate
walls or ground. All frames inherit the same pack-specific placement correction.

The private comparison gallery provides play/pause, individual-frame selection,
and a synchronized lightmap view. It does not change the pack or animation timing.
