# Quality of life

The interface uses shared dialog margins, control spacing, headings and keyboard
focus styles in both themes. Utility windows follow theme changes immediately.

## Pick an existing tool

Click an existing building or network with the middle mouse button to select
its building tool. Developed residential, commercial and industrial buildings
select their zone and density. Underground view picks pipes or subway tools.
Unavailable inventions and rewards remain unavailable. A middle-button drag
still pans the map. The action can be rebound in Settings → Controls.

## Window positions

In-game windows remember their positions and resizable dimensions locally.
Positions outside the current screen are brought back into view. Opening a new
city does not reopen a budget decision or other modal prompt.

## Music box

Windows → Music box distinguishes **SC2000 original music**, **Reticulating
Splines**, other selected replacement packs, and personal music folders. Original music
requires a loaded imported SC2000 data pack and available imported music files.
The sibling music pack from that import remains selectable when a replacement
pack is selected for automatic music. Installed `packs/standalone-audio/music`
and the selected music pack are also checked. Missing sources are not offered.
Manual choices use the exact source file and the selected SoundFont; they never
fall through to another pack with the same numeric slot.
Choose a source or personal folder on the left, then double-click a title on the
right. The current song has a play marker; tooltips show its source and file path.
The optional Queue tab retains the existing ordered queue. Tracks advances within
the selected collection; Queue advances within that queue. Previous, Play / Pause and
Next also work through the configured media keys while the music box is active.
Automatic music returns to the original game selection. Closing the window keeps
the current playback. Disabling Music in Options stops custom playback.

Music changes fade briefly. The music-box volume controls the audible output
without changing the original controller's music activity or simulation timing.
The effects slider changes the existing effects preference. Only imported original music
uses the soundtrack titles from *SIM-MELODY from SIM CITY2000*, matched to
Windows MIDI resource IDs (10000–10018), independently of installed file names.
These proper names remain unchanged across interface languages. Replacement and
personal MP3s use the ID3 song title, falling back to their filename. The shipped
legacy "Standalone Music" pack is labeled Reticulating Splines; replacement files
are never assigned SC2000 soundtrack titles. Source labels also appear during
automatic playback, whose selection and timing remain unchanged. The [title-to-MIDI reference](https://w.atwiki.jp/gamemusicbest100/pages/2869.html)
lists both the game cue names and the soundtrack titles used here. In particular,
10016 is “The Construction: HAPPYLAND”; the album order differs from MIDI order.

Window layouts and music preferences live beside the local settings file in
`.layouts.cfg` and `.music-box.cfg` files. They are not stored in cities. Playlists
and favorites persist; legacy named lists and workspace sections are retained
as inactive data, with no load/save UI; custom playback does not start automatically at launch.
Music and effects have separate volume sliders. Progress and elapsed/total time
are shown for decoded recordings. MIDI playback has no recorded duration and
shows a dash instead of a fabricated time. The progress bar does not seek.

The bounded read-only metadata reader supports ID3v1 and ID3v2.2/2.3/2.4 title
frames, including Latin-1, UTF-8 and UTF-16. It reads at most 1 MiB of tag data and
keeps up to 512 title characters. Unsupported, empty or corrupt tags fall back
to the filename. Song identity remains the source/path, even for duplicate titles.
References: [ID3v2.3](https://id3.org/id3v2.3.0) and
[ID3v2.4 structure](https://id3.org/id3v2.4.0-structure).

### Add your own MP3 music

1. Open **Windows → Music box → Open music folder**. This creates and opens the
   `music` folder in the game's user data directory. In a portable installation
   it is `data/music` beside the executable.
2. Create your own subfolders, for example `music/Evening`, and put MP3 files
   inside them. Nested folders and MP3 files directly in `music` also work.
3. Select **Rescan**, or reopen the music box. Choose a folder on the left,
   then double-click a track to play it.

Each real subfolder appears as a collection, including empty folders. The root
music folder appears when it contains MP3s directly. In the Tracks tab,
playback continues through the visible collection. Original and personal tracks
can share the current queue. ID3 titles or fallback filenames are displayed;
files are read in place and are never copied, renamed or modified.

Personal tracks use paths relative to `music` so playlists survive moving the
whole user data directory. Renaming a song or folder requires adding it to the
playlist again. Removed files remain in saved playlists and are skipped by Next
and automatic progression. An unreadable MP3 returns playback to automatic game
music with a notice. Folder links are not followed. No pack manifest, original
resource number, restart or external audio converter is required for MP3s.

New interface strings are in the central language catalogs and `messages.pot`.
Language availability follows the application's registered language set. No
original game assets are included in this feature.
