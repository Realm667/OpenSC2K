OpenSC2K Remaster - Style A (4x)

Local graphics delivery, 13 October2026

Select the graphics folder as a custom graphics pack in a compatible OpenSC2K
build, or point OPENSC2K_GRAPHICS_PACK to this graphics folder. The complete
pack does not require original graphics. The existing optional original import
is preserved. Do not copy this pack over a personal installation manually.

499 city masters and112 UI masters cover666 required resource keys.
206 city lightmaps;293 intentionally unlit masters;408 image frames and408
matching light frames;48 road masks.1442 Visual artwork records cover432
vehicle views,96 pedestrian states,896 woodland variants,13 ground masks
and5 cloud atlases.3444 PNG files; aliases share files. Small/medium zoom
views derive from the4x large master in memory. No extra building sides.

Compatibility: the feature/standalone-data-pack loader supports this manifest.
The complete Visual/Remaster consumer combination was tested in an isolated
build against integration base2373d7610010b52b8f59383979551669088973f0.
Its reviewed42-file consumer patch is retained at
D:/OpenSC2K/Codex/standalone-data-pack/validation/visual-artwork/complete-consumer-handoff.patch
The responsible central integration workflow must apply/review that binding
before a shared Runtime update. This delivery does not install or publish it.

Validation:281 upstream release cases pass across the recorded full selection
and strict continuations after Windows helper corrections. All29 renderer
cases pass. Actual replacement art was separately checked without originals:
full loader and mask audit, city day/night/power, networks/bridges/grades,
moving sprites, UI/newspaper/SCURK, nature, clouds and City Life.
Final report and exact evidence hashes:
D:/OpenSC2K/Codex/standalone-data-pack/production/reports/final-acceptance.json

Measured catalogue:1600x1000, RTX4080, paused,120 VSync frames: median16.669ms,
p95 16.864ms; peak working set3.24GiB, peak private4.33GiB; texture monitor
1.13GiB. Preparation52.596s. These include debug preparation/capture and do
not predict all city sizes or compare equivalent original and Remaster builds.
Existing CPU/reflection geometry retains its logical-resolution contract.

Sources and tools: editable ImageGen sources, prompts, emission regions and
deterministic export/projection tools remain in
D:/OpenSC2K/Codex/standalone-data-pack/production
provenance.json records hashes. graphics/SHA256SUMS.json identifies delivery.
AI assistance: OpenAI ImageGen and Codex. Original artwork was used locally
for technical reference and visual inspiration; no original pixel files or
rejected mesh experiments are included.

License: newly generated artwork has no selected distribution license yet.
See graphics/LICENSE-STATUS.txt. Existing project notices remain applicable
to their existing code and resources; no broader grant is inferred.

Deutsch
Vollstaendiges4x-Grafikpaket im freigegebenen Stil A, mit passenden Lichtmasken.
Grafikordner in einem kompatiblen Build als eigenes Paket auswaehlen.
Alle666 Pflichtschluessel sind abgedeckt; keine Originalgrafiken erforderlich.
Die Kombination mit Visual Enhancements ist isoliert geprueft. Die gemeinsame
Runtime wird ausschliesslich ueber die verantwortliche Zentrale aktualisiert.
Quellen, Generatoren und genaue Pruefnachweise liegen im genannten Themenordner.
Vor einer Veroeffentlichung ist noch die Lizenz fuer die neuen Bilder festzulegen.
