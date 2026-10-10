# Multiplayer

Experimental LAN/direct-IP multiplayer supports simultaneous **Koop**,
**Competitive Shared** and **Competitive Region**, up to eight players on the
engine-supported SC2X map sizes. Large snapshots use checked, bounded chunks;
the largest maps still require suitable host memory and processing capacity.
All participants need the same network build.

## Start and continue

Open Multiplayer from the main menu. Choose Host or Join, a name and a preset or
custom color. The host chooses the mode and may set an optional password. Guests
enter the host's address and port (default 20000), then choose a new city seat or
request an existing one. The server supplies the mode; selected colors are retained.
For two local installations use separate profiles and 127.0.0.1.

New games open a pre-game lobby. Simulation and construction remain stopped until
at least two players have joined, all connected players confirm Ready, and the host
chooses Start game. Player changes invalidate readiness. Pending joins prevent start.
All participants start at Turtle speed. Existing in-progress saves resume paused;
saves created before the first start return to the lobby without stale confirmations.

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
drag a rectangle and confirm the quote. New games default to $5 per tile, adjustable
by the host before the lobby opens. At the shared start the host assigns equal dry-land
grants in separated geographical sectors, favouring compact and level areas. Grants
contain up to 1,024 tiles (limited by sector size and the least suitable chosen sector),
without reducing city funds. Further expansion uses city funds. Existing saves retain
their original purchase rules; late-founded cities receive the existing land allowance. The land tool excludes water by default; Include water
explicitly includes it in the selection and quote.
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

Competitive Region gives each seat a complete separate map and municipal simulation.
Multiplayer > Neighbouring cities lets everyone visit any city. Only the owner can
build or administer it. Visitors may send their own available emergency services
during a disaster; ownership colors and the distinct neighbour alarm remain active.
Cities continue under their normal simulation rules, including budget decisions.

Competitive games default to Endless. The host may instead set a population target
or net wealth target (city funds minus bank debt, player-loan principal and unpaid interest). A compact top-right
panel shows the own city's progress and the leading player(s); click it for the
scoreboard. New scored matches require undeveloped starting terrain. New matches require staying at or above the target for 300 game days
(one full engine calendar year). Dropping below resets the timer; the HUD shows days
held. Cities founded after the start are permanently unranked and grey in statistics;
a player taking over a founder city inherits its eligibility. Holding the target for
the full year pauses the game, shows winner fireworks and results,
and allows leaving or host-authorized continuation without scoring. Goals, results
and the unscored continuation state are stored in the normal city save.

Reconnect credentials belong to people; city seats persist separately. Connection
loss reserves the seat and pauses the game. Deliberate departure leaves it unoccupied.
Replacement requires host approval. City, land, treasury and debt remain; personal
statistics are archived, previous credentials revoked and old land proposals withdrawn.
A holder of the complete save may host it; automatic live host migration is not provided.

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

## Land market and multiplayer interface

The dedicated Buy land toolbar button sits immediately before Signs. It selects
rectangles without activating Residential. Selecting foreign land sends a priced
purchase request after confirmation; the owner must explicitly approve it.
Land offers & requests lists open offers, incoming/outgoing requests and the last
128 completed/withdrawn/declined entries. Show on map highlights the exact tiles
for 12 seconds. Preview never buys. Sellers can withdraw offers, requesters can
withdraw requests, and owners can decline requests. All decisions are serialized
by the host and revalidate balances and ownership before transferring anything.
Overlapping offers expire after ownership changes.

Ownership is drawn as an exterior ground outline, with foreground sprite alpha
and painter depth masking it. Remote map cursors use sub-tile positions and
frame-independent interpolation; large jumps snap and stale cursors disappear.

Scoreboard provides compact sortable Overview, Finances, Land ownership, Zoning,
Construction and Emergency services tables without horizontal scrolling. Koop city
totals are separate from personal contributions.
Year-to-date balance is the recorded budget balance, excluding construction and
land transactions. Land purchase/sale totals are persisted from the introduction
of tracking; older unknown totals remain unavailable.

Chat is docked at the lower left of the map, beside the toolbar, with an inline
reply field. Typing does not trigger game shortcuts. New incoming messages and
actual player joins/leaves have distinct quiet cues respecting local sound/volume.
Chat replay and duplicate events are silent. Status text distinguishes voluntary
leave from connection loss. New interface text ships in English and German via
the feature-local PO catalog and the integrated AppLocalization locale.

multiplayer_polish_test covers ownership consent, failed/raced transactions,
withdrawal, saved counters, exterior boundaries, interpolation, localization,
stable table sorting and real TCP chat/status events.

## Player loans, history and rematches

Budget > Player loans lets either party propose a principal, fixed annual rate
(0–25%) and term (1–50 game years). The proposer confirms on sending and the other
party accepts the displayed immutable terms. Only acceptance transfers funds;
insufficient lender funds reject the transaction. Interest is transferred annually
(rounded up to whole currency units); principal is due at maturity. Payments never
create an overdraft. Unpaid sums remain visible debt and are settled as funds become
available; there is no compound interest or hidden post-maturity penalty. Accepted
contracts remain with city seats on departure or takeover; unaccepted proposals are
withdrawn on takeover. These transfers are shown in this Budget tab, separately from
the original bank-bond reports.

Scoreboard > History compares monthly population, treasury, debt, land, developed
land and budget balance with shared axes, player colours and exact-value tooltips.
The latest 600 months are retained in the normal save. No values are invented for
months before recording began. Switching statistics pages needs no horizontal scroll.

After a result, the host may propose a rematch. The original terrain and difficulty
are reused, city progress and loan contracts reset, and everybody must confirm Ready
again. Starting sectors are stored per city seat across rounds and saves. A seat never
receives a previously used sector; when the finite set of 16 sectors is exhausted (or
there are no suitable unused positions), the request is rejected and new terrain is
required. Region cities show their assigned region number and change their initial
camera/start position. Absent players keep their saved city-seat identities.

## Synchronization performance

Reliable ordered deltas transfer only changed top-level fields and changed pages of
the encoded city/ownership arrays. Full snapshots establish join/recovery baselines;
a baseline mismatch requests recovery instead of applying uncertain changes. Large
messages are streamed in bounded chunks; cursor and environment updates replace older
unsent updates. Confirmed build commands publish immediately. Pending selections are
marked locally until the host responds, without changing local money or simulation.

Shared composes its common tile planes once per revision, and Region encodes each
viewed city once per revision. Two recent views are cached for delta reuse, subject to
a 64 MiB multi-view cache budget. Every Region city still simulates by its ordinary
rules; only the viewed city is rendered. The loopback load test measures 2/4/8 peers
with increasing zoned areas, transfer bytes, command convergence, simulation work and
combined process memory. It does not establish real Internet latency or GPU FPS.
