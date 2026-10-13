# Package library

Settings → Data lists the available sources independently for graphics, sound,
music, original data, HD sprites, brightmaps, cities and mods. Rescan packages
refreshes the lists without changing the active sources. External file/folder
selection remains available. Missing saved paths stay visible with an explanation.
Invalid manifests and missing referenced files are reported in the menu tooltip;
the category loader checks full content before activating it. Failed activation
keeps the previous source.

In portable installations these folders are below `data/` beside the executable:

| Folder | Contents of each package subfolder |
| --- | --- |
| `graphic` | Graphics `pack.json` and its image files |
| `sounds` | Sound `pack.json` and WAV files |
| `music` | Music `pack.json` and its audio files; ordinary MP3 folders remain available in the Music Box |
| `data` | Original-data `pack.json` and required extracted resources |
| `hd` | HD sprite `pack.json` and images |
| `brightmaps` | `catalog.json` with compatible masks in `brightmaps/<group>/` |
| `cities` | Collections of city files, selected as the initial Open City location |
| `mods` | Existing `info.json` mod packages or folders containing them |
| `pack/sc2000` | Versioned original imports with graphics/sound/music/data subfolders |

The built-in sources are installed into `graphic/reticulating-splines`,
`sounds/reticulating-splines` and `music/reticulating-splines`. Brightmaps shipped
inside the application remain the automatic default. `godot_wry` is internal
and is never scanned or presented. Symbolic links are not followed during discovery.
Selecting a mod source uses the existing mod loader and dependency checks; it
does not change mod code or simulation rules. The automatic source loads the
existing collection. City selection never opens, saves or rewrites a city by itself.

Old `packs/` layouts and explicit external paths remain supported. Existing
automatic defaults in `packs/<kind>` take precedence over the bundled default.
No source or preference is deleted or silently moved. Installation must copy
bundled packages into the new layout and verify them before changing launchers.
Existing selections may continue to point to their legacy folders.

## Original import

A new exported installation asks once whether to import SimCity 2000 data.
Existing preferences or original imports identify an existing installation and
do not trigger the first-start question. The same question is available later
through Import Original Assets in Settings → Data.

- **No:** leave sources unchanged; a new installation uses its RS defaults.
- **Yes:** import only. The new packages appear in Data, without activation.
- **Yes, and activate:** import and activate each successfully imported category.

Both choices use the existing category importer. It extracts the supported
graphics/audio and runtime resources, text/newspaper data, city/scenario and
SCURK content; it does not copy an original installation or retain executables.
Imports use new, staged version folders under `pack/sc2000`, preserving previous
imports and allowing partial successes without losing active selections.

## Windows identity

The Windows x86_64 export is `ReticulatingSplines.exe`, with
`ReticulatingSplines.pck` and the existing native DLLs alongside it. Windows ARM64
uses `ReticulatingSplines-arm64.exe`. Both use the RS multi-resolution icon.
The Godot project name stays unchanged so existing user profiles are retained.
This local remaster identity does not change upstream licensing or attribution.
