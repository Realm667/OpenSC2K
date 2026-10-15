# Editable object animation frames

A `master_sprites` record can provide one to four RGBA source frames. The files
use the same canvas, 4x resolution, registration and placement as its base art.
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
