# Multiplayer Koop

The multiplayer branch adds an experimental, playable real-time cooperative city to the Visual Enhancements package. Up to eight participants share one city, treasury, budget and simulation. Competitive Shared and Competitive Region are planned extensions and are not implemented in this version.

## Start a session

1. Install the same multiplayer build and import the required game assets on each computer.
2. Open **Multiplayer** from the main menu. Enter a player name, TCP port and session code.
3. The host selects **Koop hosten**. This creates an empty 128 by 128 city. To use generated terrain or an existing city, open that city first and select the option to host a copy. The city must be SC2X, no larger than 128 tiles per side, with no unresolved simulation decision.
4. Other players enter the host's LAN address, the same port and code, then select **Beitreten / Wiederverbinden**. Port 20000 is the default. For two instances on one computer, use separate data profiles and address `127.0.0.1`.
5. The host chooses a running speed. Each participant can request a pause or a speed; the slowest request applies. The city tools work simultaneously, without turns.

The top menu's **Multiplayer** button opens shared administration, save and leave actions. Budget, ordinance and bond actions use this panel. Load current budget values before editing; another participant's intervening policy change rejects an obsolete proposal. An exclamation mark indicates a simulation decision. The annual budget must be confirmed there; military decisions and other blocking notices have explicit confirmation actions.

Direct IP uses the same TCP connection as LAN. The host must be reachable on the selected port. Automatic LAN discovery, NAT traversal, encryption and automatic host migration are not provided. Use the prototype with trusted participants on a private network; a session code is admission control, not encrypted transport.

## Conflicts and recovery

Only the host runs the authoritative simulation. Even the host's visible city is a separate display copy. Clients send tool intentions; the host calculates costs and executes the existing tools on a candidate city. It rejects stale selected tiles and stale tiles anywhere in the resulting structural change, including indirect terrain effects and complete building footprints. Independent changes from the same observed revision remain valid. Shared funds are checked against the latest accepted city.

Bridge, connection, tunnel and stadium choices are returned to the requesting player. The host rechecks the command after the choice. Confirmed construction prices are limits, so a more expensive result cannot be accepted silently. A rejected candidate does not alter the authoritative city's payloads or random generators.

Undo is available only for the same participant's immediately preceding edit, while no other edit or simulation step has intervened. This version rejects expired Undo requests instead of reversing later work.

A lost participant causes a shared pause. The host can release that pause explicitly. Disconnected clients display their last snapshot and cannot edit. Reconnecting with the same local profile retains the participant identity and command sequence, preventing an already handled request from being charged twice. After leaving a session, the local singleplayer city is restored.

## Save a session

The host saves a versioned `.sc2mp` file using the path in the Multiplayer panel. The default is `multiplayer/session.sc2mp` within that installation's data folder. A previous save is retained as `.bak`. Saving includes the SC2X city, random generators and phase checkpoint, participant identities, command sequences and session identity. Resolve pending simulation decisions before saving. Imported cities are copied and their source files are not overwritten.

Use **Gespeicherte Sitzung hosten** to resume. A restored session starts paused; choose a session code and share it with the participants. The local client identity is in `multiplayer-client.cfg`. Keep each participant's profile separate, including when testing two instances on one computer. Do not publish session files or client profiles: they contain reconnect identities.

## Prototype boundaries

- One cooperative city, at most 128 by 128 tiles. No separate municipal economies, ownership or regional trade yet.
- Camera movement and zoom are independent. Rotation is disabled because the current engine rotates city data; independent rotated views need a separate coordinate mapping.
- Manual disaster triggers, facility query actions and the industry tax detail window are not available in Koop. Ordinary simulation disasters remain active according to the hosted city's rules. Read-only city queries and data views remain available.
- The custom budget panel supports the existing residential, commercial and industrial tax percentages, service funding, Auto-Budget, ordinances and bonds. It does not yet reproduce the full singleplayer budget reporting interface.
- Confirmed commands publish immediately; periodic simulation snapshots follow at four per second. TCP uses no-delay mode. The host simulates continuously. Bandwidth and rendering performance need testing on real LAN hardware and developed cities before raising the map or participant limits.
- The host controls the shared weather progression. Weather transitions, precipitation, cloud types and atlas transitions, low mist, flashes and thunder events are sent separately at up to 20 updates per second, including the current state for late joiners. Host pause freezes precipitation and storm audio on guests. Dry storms use wind without rain. Guests can still disable effects or mute audio locally. Cosmetic weather starts afresh when a saved session is hosted again; the simulation weather remains in the saved city. All participants in the integrated 0.3.0 runtime must use network build `opensc2k-coop-4`; the integrated 0.3.0 runtime records native dispatch positions in session saves. Sessions without that position record are rejected rather than restoring incomplete deployment state. The previous dedicated Multiplayer runtime remains available for its older saves.

## Architecture and tests

`CoopWorld` owns the city, simulation and command validation. `CoopSession` owns TCP admission, participant identities, sequencing, speed requests and session files. `CityTcpChannel` uses bounded, length-prefixed UTF-8 JSON with partial nonblocking reads and writes. Incoming commands have frame and rate limits; a slow peer cannot accumulate unbounded snapshots. `ApplicationMultiplayer` connects existing menus and tools to the session and maintains the display copy.

`coop_multiplayer_test` covers simultaneous independent edits, stale demolition, Undo ownership, invalid coordinates, shared funds, stale budgets, simulation advancement, TCP synchronization, duplicate requests, reconnect and session persistence. `coop_ui_test` covers main-menu entry, host activation, ordinary map tools, a remote edit, shared budget, save and return to singleplayer. Run these with the project validator; run the full release suite before distributing a build. Loopback checks do not establish reachability or performance between separate computers.

## Subsequent modes

Competitive Region requires separate authoritative city contexts on a shared calendar, with all participants able to inspect every other city through a read-only live view. Contracts must commit deliveries and payments together.

Competitive Shared requires ownership and municipality-aware simulation on one physical map. Separate bank balances alone are insufficient: taxes, demand, upkeep, public services and network supply need municipal attribution. Neutral land may be purchased anywhere, including disconnected parcels; another player's land requires an explicit sale offer. Full maps leave voluntary trade, rebuilding and densification.

The historical design references are [SimCity 2000 Network Edition's online help](https://nightfirepc.com/maps/sc2knefiles/2KNET/DOCS/basics.htm), its [server and client model](https://nightfirepc.com/maps/sc2knefiles/2KNET/DOCS/servclin.htm), and [SimCity 2013's regional and spectator features](https://eaassets-a.akamaihd.net/eahelp/manuals/simcity-manuals_PC.pdf). These inform the future modes; they do not imply that this prototype implements their municipal economy or regional trading systems.
