# Quality of life

The interface uses shared dialog margins, control spacing, headings and keyboard
focus styles in both themes. Utility windows follow theme changes immediately.

## Pick an existing tool

Click an existing building or network with the middle mouse button to select
its building tool. Developed residential, commercial and industrial buildings
select their zone and density. Underground view picks pipes or subway tools.
Unavailable inventions and rewards remain unavailable. A middle-button drag
still pans the map. The action can be rebound in Settings → Controls.

## Window positions and workspaces

In-game windows remember their positions and resizable dimensions locally.
Positions outside the current screen are brought back into view. Opening a new
city does not reopen a budget decision or other modal prompt.

Windows → Workspaces saves three arrangements: Building, Finances and City
analysis. Arrange the report windows, select a slot and save it. Restoring a slot
opens its reports with fresh city data and restores their positions. Close a
blocking decision before restoring a workspace. Reset window positions centers
the open windows and clears their remembered positions.

Workspaces contain window arrangements. They do not rotate the city or change
vehicle visibility, which can affect the original simulation.

## Music box

Windows → Music box uses the selected music pack, recordings and SoundFont.
Double-click a track to play it. Add tracks to an ordered playlist, mark favorites,
filter the library, and save or load named playlists. Previous, Play / Pause and
Next also work through the configured media keys while the music box is active.
Automatic music returns to the original game selection. Closing the window keeps
the current playback. Disabling Music in Options stops custom playback.

Music changes fade briefly. The music-box volume controls the audible output
without changing the original controller's music activity or simulation timing.
The effects slider changes the existing effects preference. Track names come from
the installed files; numeric-only files use their track number.

Window layouts and music preferences live beside the local settings file in
`.layouts.cfg` and `.music-box.cfg` files. They are not stored in cities. Playlists
and favorites persist; custom playback does not start automatically at launch.

New interface strings are in the central language catalogs and `messages.pot`.
Language availability follows the application's registered language set. No
original game assets are included in this feature.
