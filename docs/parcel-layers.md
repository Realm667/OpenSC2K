# Pack-owned parcel layers

Master sprite records may opt into a software parcel with `parcel`:

```json
{"id": 1143, "parcel": {"border": "077300ff", "surface": "asphalt_curb"}}
```

`border` is eight hexadecimal RGBA digits; transparent alpha means no contour.
`surface` is `none`, `asphalt`, `asphalt_curb`, `dirt`, `dirty_asphalt`, `tiles`,
or `parking`. Missing metadata creates no layer. RS lists individual original
reference classifications in `graphics/parcel-review.json`, including exceptions.
SC2K imports have no opt-in and already contain their original outlines.

The loader validates the metadata for building masters 1112–1255 and derives
all three views. Archive replacement clears the previous pack's metadata.
The native renderer caches one texture per footprint, color and material during
configuration. Each applicable building adds one batched quad after its terrain
and before its artwork. No per-building node or per-frame texture generation is
needed. Coverage stays within the exact 2:1 parcel, at the existing terrain
baseline; object scale, image padding and mirroring cannot move the parcel.
The high-resolution texture has four texels per original large-view pixel in
all views. Ground has no emissive mask, building reflection or figure silhouette.
Underground and data views do not request parcel layers.

Artwork and lightmap transforms remain documented in master-sprite-registration.md.
The RS pack uses only colored contours in this layer. Its textured asphalt,
paving and soil were baked into the PNG artwork in review 85; `surface` is
`none`. The optional surface support remains available to other packs.
The private comparison gallery shows the fixed contour below editable artwork,
including its baked ground.
