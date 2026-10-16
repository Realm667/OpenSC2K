Reticulating Splines Remaster — Style A (2x)

Development source pack, 14 October 2026. 499 city masters; all smaller city
views derive from the 2x masters. Original import sets remain separate.

Latest review: 228 city masters and two UI sheets corrected from the city review.
Roads, railways, crossings, grades, ramps, bridges and tunnels share wider
cross sections. Matching traffic masks, 400 traffic frames and 400 light frames
follow the same paths. Beige soil/coasts/zoning and subdued blue pipes retain
seasonal and water-flow behavior. Ground enhancements reuse the corrected masters.
Rubble projection and exact park/rubble offsets are pack-local; aircraft, train,
superhero, rotor motion, explosion edges and city-growth artwork were revised.
Previous building corrections and Nature pastel A parcel contours remain.

Asphalt, pavement, parking and dirt are now textured and baked into the building
PNGs, with material grain, joints, curb bevels and contact shadows. The RS pack
requests no software ground fills. 127 colored parcel contours remain software
layers, using the approved Nature pastel palette (variant A, 13 color families);
17 exceptions including #1227 retain no contour. SC2K uses its existing
integrated contours. Artwork and matching lightmaps remain strictly pack-local.
Unrequested base grass stays transparent for seasonal terrain.

Private editable sources, exact ImageGen prompts and current verification:
D:/OpenSC2K/Codex/standalone-data-pack/corrections/2026-10-14-city-review/CURRENT.txt
Previous accepted reviews: corrections/2026-10-14-review86/CURRENT.txt and
corrections/2026-10-14-nature-pastel/CURRENT.txt.
Receipts: graphics/city-review.json, graphics/placement-review.json,
graphics/parcel-review.json.
Selected raster hashes: provenance.json and graphics/SHA256SUMS.json.
Private comparison galleries cover buildings, other city tiles, UI and all
manifest-referenced Visual Enhancements resources. Original pixels stay private.

The personal Runtime is installed only by REL under the workspace rules.
Existing project notices and graphics/LICENSE-STATUS.txt continue to apply.

TrueColor migration (15 October 2026): the visible PNG sources are RGB/RGBA,
including all 528 vehicle/person color variants. The previous palette-consolidation
receipt remains historical; literal colors now reside in the variant PNGs.
432 vehicle lightmap references still share 49 PNGs. Existing GPU batching and
light/environment effects remain unchanged. RS uses the same built-in Visual
Enhancement clouds as SC2K.

All 122 animations use source frames at 125 ms per frame: the existing 81
sequences plus 40 water/coast/pipe sequences converted from cyclic colors, plus the
fullbright power-warning blink formerly driven by a palette shader.
The pack disables palette cycling; original SC2000 imports remain indexed and
keep their cycles. A 16x16 compatibility lookup and optional semantic masks
preserve logical road/water/editor addresses without limiting visible colors.
Source colors, alpha, canvas dimensions, anchors and existing lightmaps are
preserved. See docs/media-pack-format.md and graphics/truecolor-review.json.

2026-10-15: 34 additional four-frame object animations with synchronized masks.
All 144 buildings now use the centered-footprint-v1 master canvas convention;
accepted sizes and positions are baked into pixels, with no individual overrides.
Use the matching game build with master_canvas support. Modding documentation:
../../docs/master-canvas-layout.md; per-building sizes and guides: templates/.

2x and building colors, 16 October 2026:
All 4199 visible artwork/mask PNGs reduced from approved RS 4x sources. The
16x16 compatibility lookup is unchanged. Material-color ramps retain the pixel
style without dithering. All logical sizes, anchors and 122 frame sequences
(125 ms each frame) are unchanged. Lightmaps and semantic masks are aligned.
Residential buildings use olive/cyan/vanilla accents; commercial buildings cool
white/gray/anthracite; industry oxide/rust/sand. City Hall, Hospital, Police
Station, Museum and Llama Dome use white finishes; Prison has dark facades.
Police Station is #1210; #1202 is oil power and was not whitened.
Current receipt: graphics/resolution-color-review.json (or this folder).
Historical migration receipts retain their original dated source dimensions.
