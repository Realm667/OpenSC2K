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

Windows → Music box uses the selected music pack, recordings and SoundFont.
Double-click a track to play it. Add tracks to an ordered playlist, mark favorites,
and filter the library. Previous, Play / Pause and
Next also work through the configured media keys while the music box is active.
Automatic music returns to the original game selection. Closing the window keeps
the current playback. Disabling Music in Options stops custom playback.

Music changes fade briefly. The music-box volume controls the audible output
without changing the original controller's music activity or simulation timing.
The effects slider changes the existing effects preference. The 19 original music
slots use the soundtrack titles from *SIM-MELODY from SIM CITY2000*, matched to
Windows MIDI resource IDs (10000–10018), independently of installed file names.
The same titles appear in the library, favorites, playlists and current-track
display, and remain unchanged across interface languages. Personal MP3s retain
their file names. The [title-to-MIDI reference](https://w.atwiki.jp/gamemusicbest100/pages/2869.html)
lists both the game cue names and the soundtrack titles used here. In particular,
10016 is “The Construction: HAPPYLAND”; the album order differs from MIDI order.

Window layouts and music preferences live beside the local settings file in
`.layouts.cfg` and `.music-box.cfg` files. They are not stored in cities. Playlists
and favorites persist; custom playback does not start automatically at launch.

### Add your own MP3 music

1. Open **Windows → Music box → Open music folder**. This creates and opens the
   `music` folder in the game's user data directory. In a portable installation
   it is `data/music` beside the executable.
2. Create your own subfolders, for example `music/Evening`, and put MP3 files
   inside them. Nested folders and MP3 files directly in `music` also work.
3. Select **Rescan**, or reopen the music box. Choose **My music** or a folder
   from the collection selector, then double-click a track to play it.

Each folder containing MP3s appears as a collection. With an empty playlist,
playback continues through the visible collection. Original and personal tracks
can share favorites and the current queue. File names are displayed as track names;
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
