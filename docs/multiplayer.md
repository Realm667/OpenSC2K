# Multiplayer

Experimental LAN/direct-IP multiplayer supports simultaneous **Koop** and
**Competetive Shared**, up to eight players on SC2X maps up to 128 × 128.
**Competetive Region** is displayed as unavailable and remains a subsequent release.
All participants need the same network build.

## Start and continue

Open Multiplayer from the main menu. Choose a name, color and mode. The host may
set an optional password. Guests enter the host's address and port (default 20000).
For two local installations use separate profiles and 127.0.0.1. Duplicate colors
receive an alternative; names remain visible too.

**Neue Stadt** opens the regular terrain preview and complete city setup.
**Gespeicherte Stadt** opens a city file. **Kopie erstellen** keeps the original
and asks for a new save destination; otherwise continue the selected save.
Legacy SC2 cities are converted to SC2X. Old .sc2mp sessions can still be imported.

Use normal File > Save / Save As. Only the host saves. Session identities,
municipalities, ownership, statistics and simulation checkpoints travel inside
SC2X automatically; no separate session path is needed. The previous save is
retained as .bak. Resolve pending simulation decisions before saving. Keep client
profiles and saves private: they contain reconnect identities.

The Multiplayer menu between Newspaper and Help contains Scoreboard, Chat,
connection recovery, leaving and Shared land transactions. Budgets, ordinances,
industry taxes, bonds and speed use regular controls. Chat and camera movement do
not pause the host. Everyone can request a pause; the slowest explicit speed
request applies. New guests no longer cap speed at Turtle. A disconnect pauses
the world until the host releases it. Reconnection preserves identity and sequence.

## Koop

All players administer one city, treasury and budget concurrently. The host checks
costs and the full affected area, including indirect terrain edits and building
footprints. Stale conflicts are rejected without payment. Existing limited Undo
only applies to your immediately preceding edit before another change or tick.
Everyone can dispatch shared emergency services. Colored marker outlines identify
the last dispatcher without creating exclusive ownership.

## Competetive Shared

Each participant has a separate municipal simulation and account on the shared
visible terrain. Budgets, taxes, loans, population and services are independent.
Imported development belongs to the host. Guests receive fresh accounts using the
session difficulty. Undeveloped land is neutral. Use Multiplayer > Land kaufen,
drag a rectangle and confirm the quote. The initial price is $10 per tile.
Disconnected parcels are allowed. Buildings and indirect terrain changes must
stay on your land. Colored boundaries identify ownership.

Owners may offer rectangles at explicit prices. Buyers accept through Landangebote.
The host transfers payment, ownership, zones and complete buildings together;
partial-building sales are rejected. Loans stay with the seller. Active emergency
or moving objects must leave a transferred parcel first, and transfers wait while
either city handles a disaster. Raced or expired purchases charge nothing.

Each city uses its own infrastructure; adjacent foreign networks do not provide
free services. Intermunicipal supply contracts and cross-border environmental
propagation are not implemented in this first Shared version. City rotation and
Shared Undo remain unavailable.

Players may assist an active disaster with their own available fire, police or
military units without entering disaster mode themselves. A distinct two-tone
alarm and bottom-toolbar location identify the affected player. Markers retain
dispatcher colors and show names on hover. Recall includes your foreign deployments.

## Presentation and communication

Remote cursors use map coordinates with names and colors. Scoreboard shows
construction counts/spending, common city totals in Koop, and individual municipal
totals in Shared. The session chat has colored names, literal text and unread counts.

The host controls day/night, seasons, weather and clouds. Guests receive the phase
and settings on joining; corresponding environmental controls are locked. Local
audio levels remain available. Visual effects restart when hosting a saved city;
simulation weather is saved.

Confirmed edits publish immediately. Simulation snapshots run at four updates per
second, atmosphere up to twenty and cursors up to ten. TCP uses no-delay and bounded
queues. Only the host simulates; clients send intentions, never city files or
balances. Discovery, NAT traversal, encryption and host migration are not provided.

## Validation

coop_multiplayer_test, multiplayer_next_test and coop_ui_test cover concurrent
edits, conflicts/costs, budgets, city setup controls, saves, reconnect, separate
Shared accounts, land transactions, disaster aid, chat, colors, presence and
atmosphere. Run the release suite plus GPU/two-process checks before distribution.
Loopback tests do not establish reachability/performance on physical LAN computers.
