# Navigation: how anything alive gets from here to there

Not to be confused with [wayfinding.md](wayfinding.md), which is about
*player instruments* — a compass, a map, a spyglass — that tell **you**
where things are. This doc is about how the **simulation's own agents**
move: villagers walking to work, creatures crossing a meadow, and what
either of them does when something solid is in the way.

## Design pillars

**1. Ask before stepping, never discover afterwards.** This is
[npc.md](npc.md)'s and `CreatureMovementGate`'s shared existing rule and
it stays the foundation. Everything that reacts *after* a blocked move
has already happened reads as erratic — the creature gate exists because
a creature wedged between a player and a tree re-picked a direction every
single frame.

**2. A wanderer and a traveller need different machinery.** This is the
central decision of this doc, and it is why there is not one navigation
system here but two:

| | what it is doing | what it needs |
|---|---|---|
| **creature** | wandering, grazing, fleeing — no destination it must reach | **reactive avoidance**: keep walking, just not into things |
| **villager** | a real schedule with a real place to be | **a route**: get to the doorstep even if a barn is in the way |

Giving a wandering deer a path to a place it does not care about would be
both wasted work and wrong — a deer that A\*s around a house is not
behaving like a deer. Giving a villager only reactive avoidance is what
produced the known failure below.

**3. Nothing is solid because of physics.** A building's `StaticBody2D`
stops the *player* because the player is a real physics body. Every other
mover in this game — `NpcMarker`, `CreatureMarker` — is a `Sprite2D` or
`Node2D` assigning `position` directly, so physics is invisible to them
by construction. Solidity, for them, is a **query**, and the whole of
this doc is about making that query cheap, exact and shared.

**4. Never trap anything.** Every rule here has an escape. An agent that
ends up inside something solid — a house raised over it, an older save —
may always move, in any direction. Imprisoning an agent permanently is a
worse bug than the one any of these mechanisms exists to fix.

## What was broken, and what this fixes

Reported live, in order: *"NPCs walk straight through houses, ignoring
the hitbox"*, then *"fix creatures walking through houses too also add
proper wayfinding / routing"*.

- **Villagers walked through houses.** Fixed by the villager wall slide (see
  [npc.md](npc.md)'s "Walls are solid to a villager too") — but only with
  axis sliding, which gets an agent *along* a wall and not *around* it.
  A villager whose doorstep sat behind its own house pressed into the
  wall forever. That is the gap this doc's routing layer closes.
- **Creatures walked through houses**, for a different reason:
  `EarthChunkManager.solid_obstacles_near` — the only thing
  `CreatureMovementGate` ever sees — walks `_loaded_trees` and
  `_loaded_stones` and has no building term at all.

## Mechanism

### Creatures: buildings become a blocker the existing gate understands

`CreatureMovementGate.clear_direction` already searches outward through
twelve turn offsets for a heading that clears, preferring the smallest
turn and the creature's current facing. It needed no new search — only
a new *kind* of obstacle.

Buildings are supplied as an optional **tile predicate** rather than as
circles in the existing `blockers` array, and that choice is deliberate.
A building is a rectangle of whole tiles; approximating one as circles
means either inscribed circles (which leave real diamond-shaped gaps at
every four-tile corner that a step can land in) or circumscribed ones
(which block beyond the wall). More importantly it is **O(footprint
tiles) per candidate direction** — a village with eight houses in range
would add ~70 blockers, checked against twelve candidate headings, per
creature, per tick. This codebase has already been bitten once by exactly
that shape of cost ("since the last change the game is laggy", which is
why `solid_obstacles_near` exists at all). A tile predicate is O(1) per
candidate and exact.

The gate's own "don't make it worse" rule extends to it unchanged: a
creature already standing in a building may always step, so nothing is
ever pinned inside a wall.

### Villagers: a real route, computed once per destination

`TileRouter` is an ordinary **A\*** over the tile grid, and it is
deliberately ordinary — the interesting decisions here are all about
what it is allowed to cost, not about the search:

- **Eight-connected, octile heuristic.** Agents move diagonally, so a
  four-connected path would be visibly wrong (a staircase where a
  straight diagonal exists).
- **No corner cutting.** A diagonal step between two blocked orthogonal
  neighbours is refused, or villagers would slip through the exact corner
  gap where two buildings touch.
- **A hard node budget, not a distance limit.** The world is
  chunk-streamed and effectively infinite; an unbounded A\* toward an
  unreachable goal would walk the whole loaded region. The budget caps
  the worst case directly, and exhausting it returns *no route* rather
  than a bad one.
- **A blocked goal returns no route**, rather than a nearest-reachable
  guess. A villager's real destination is its doorstep, which is never
  inside a footprint (`BuildingCatalog.doorstep_of` puts it one row
  south), so a blocked goal means something genuinely unexpected and
  guessing would hide it.

Routing runs **when the destination tile changes**, not per frame, and
the result is followed waypoint by waypoint. That is what makes a real
search affordable: a villager walking to the well pays for one A\* and
then walks it.

`NpcMarker._slid_along_walls` stays underneath as the last line of defence. A route
can go stale — a house can be raised across it mid-walk — and the gate
is what guarantees that even a stale route never puts a villager inside
a wall.

### Terrain and water are not the same kind of obstacle

Wiring these in is one decision, not two, and getting it wrong in the
obvious way would have removed working behaviour:

- **Slope is absolute.** `TerrainPassability.is_passable` already owns the
  threshold; too steep is simply not ground an agent can be on.
- **Water is costly, not blocked.** A creature must stand *on* a water
  tile to drink from it, and creatures, villagers and the player all
  already have swim animations and a `WaterMovementModel`. Blocking water
  would not have been a safety measure, it would have deleted all of that.

So water enters through **cost**, which means routes are priced in
**travel time rather than distance** — and the prices are derived, not
invented. If swimming is `BASE_SWIM_SPEED` (0.6) of walking pace, a water
tile takes 1/0.6 as long to cross, and that is exactly what the router is
told. Slope reads the same way through
`TerrainPassability.speed_multiplier`. A villager therefore walks round a
river when there is a dry crossing and wades when going round would cost
more, which is what a person does and what no amount of blocking could
express.

Cost scales are clamped to at least 1.0. The octile heuristic assumes open
ground is the cheapest there is, so a tile cheaper than open ground would
make the heuristic overestimate and quietly return non-optimal routes —
wrong rather than merely odd.

## Real-world grounding, such as it is

Little here is a physical claim, and this doc will not dress up a
pathfinder as one. The one honest observation it does encode is the
pillar above: **a grazing animal and a commuting person genuinely do
navigate differently.** A deer crossing a meadow is not solving a route;
it is moving and reacting. A person walking to work is executing a plan
and will walk right around a building to do it. Modelling both with one
mechanism would make one of them wrong, and the split here is that
observation, not an optimisation.

## Status

- ✅ **Creatures see buildings.** `CreatureMovementGate.clear_direction`
  takes an optional tile predicate and `tile_size`; the twelve-turn search
  it already did needed no change, only a new kind of obstacle. 17 tests,
  including a sweep from every tile ringing a house in all eight
  directions. The condition *guarding* the gate mattered as much: both
  call sites took a fast path skipping it entirely when no tree or stone
  was near, so a creature in open ground beside a house walked straight
  through however well the gate understood buildings.
- ✅ **`AgentPassability`** holds the predicate once for all three movers
  (`NpcMarker`, `CreatureMarker`, `BondedCompanionMarker`), built once per
  mover in `setup()` rather than per frame. `BondedCompanionMarker` had
  been discarding its `tile_size` parameter entirely; it is kept now.
- ✅ **`TileRouter`** — 8-connected A\* with an octile heuristic, no corner
  cutting, a hard node budget, and integer costs (scaled by 100) so that
  two genuinely equal paths compare equal and the result is deterministic.
  13 tests.
- ✅ **Villagers route.** `NpcMarker._steer_toward` aims at the next
  waypoint of a real route, recomputed only when the destination *tile*
  changes and no more often than `ROUTE_RECOMPUTE_SECONDS` — so a villager
  walking to a fixed doorstep pays for exactly one search. Pinned by the
  test that actually mattered: not "never inside a house", which sliding
  already passed, but **arrives at a doorstep with a house squarely in the
  way**, which sliding failed at 89px out.
- ✅ **The slide stays underneath the router.** A route can go stale — a
  house raised across it mid-walk — and `_slid_along_walls` is what
  guarantees a stale route still never ends inside a wall.
- ⬜ **Creatures still do not route**, by design (see the open question
  below). A creature blocked by a long wall turns along it and wanders
  off, which is what a wandering animal should do, but a predator
  committed to a hunt inherits the same limitation.
- ✅ **Terrain and water are wired into both paths**, via
  `AgentPassability` — one module answering two separate questions
  (blocked: buildings and cliffs; costly: water). Villagers refuse cliffs
  and prefer dry crossings; creatures and companions refuse cliffs through
  the same predicate.
- ✅ **Creatures now TURN at a cliff rather than stopping at one.** An
  earlier draft of this list claimed terrain was in neither path; that was
  wrong for creatures, which already had `_terrain_blocks_movement` —
  but it ran *after* the heading was chosen, so the only thing a creature
  could do about a cliff was stand still. Folding slope into the gate's own
  per-candidate predicate means the existing twelve-turn search now finds
  a way along the contour instead. The cost stays one predicate call on
  the common path, because the gate returns on its first clear candidate.
- ⬜ **Water costs nothing to a creature.** Only villagers route, and only
  a router can price a tile — a wandering animal has no route to weigh, so
  it wades whatever it walks into. Correct for a deer at a stream; less so
  for one that ought to prefer the bank.
- ⬜ **Trees and stones are not in the villager's predicate.** Creatures
  avoid them through `solid_obstacles_near`; villagers only avoid
  buildings.
- ⬜ **No cross-chunk routing.** A destination in an unloaded chunk cannot
  be routed to. Villagers never have one; carters eventually might.

### Reconciled with a parallel implementation (2026-09-20)

Two sessions fixed "agents walk through walls" independently, and this doc
now describes the merged result rather than what either wrote alone.
`claude/brave-euler-bcoea4` landed first, and **its wall gate is the one
that survived**, for a reason worth keeping written down: it asks
`piece_blocks_movement_at_global` — the same question the wall's own
collision body is spawned from — so what stops a player, what stops a
villager and what a route plans around can never disagree. It also knows a
DOOR and a FLOOR are walkable pieces, where the footprint question this
doc originally specified reported the whole building solid and would have
meant no villager could ever plan a way indoors. It handles farm rails too.

**That preference was half right, and the other half was a bug**
(2026-09-20). Reported after every marker already had this gate: *"NPCs
still walk through houses and ignore the hitbox"*. A village house is a
whole-building **entity**, not a grid of pieces (see
`docs/concept/building.md`, "Buildings are entities; interiors are
scenes"), and `BuildingCatalog.occupies` is explicit that the two kinds are
different things — "a legacy BuildingPiece or a single-tile placeable is
its own thing and answers false here". So the piece question answers
`false` on every cell of a cottage, while the player is stopped by a
`StaticBody2D` over its whole footprint: the player and the markers were
being stopped by two different kinds of building.

`AgentPassability` had made the preference structural — an `elif`, so a
world that knew pieces never asked about buildings at all.

**Both questions, asked once.** `AgentPassability.structure_blocks(world,
tile)` is now the single answer the router, `WalkGate`,
`NpcMarker._blocked_step` and `CreatureMarker._building_blocks_arrival` all
read, so six gates cannot answer it six ways. What protects a walkable door
is not the preference but the **disjointness**: a `BuildingPiece` answers
`false` to `has_building_at_global`, measured on real stamped pieces
(`test_marker_gates_block_buildings.gd`), so both questions can be asked
and a door stays a door. And a whole building's footprint being solid in
full costs nothing, because its interior is a separate scene entered from
the **doorstep**, which `BuildingCatalog.doorstep_of` puts "just south of
the door, outside the footprint".

What survived from this side is what the other did not have: the **router**
(`TileRouter`), **`AgentPassability`**, and terrain/water. Two modules
written here (`NpcBuildingGate`, `BuildingWalls`) were deleted as
superseded rather than kept beside their better equivalents.

One real regression came out of that deletion and is worth recording,
because a test caught it and reasoning did not: the surviving slide knew
walls and rails but **not slope**, so removing the deleted gate removed
the only thing enforcing terrain on the actual step. A villager whose goal
sat behind a cliff found no route, fell back to walking straight at it,
and climbed it. Slope now lives in the slide — the one place every step
passes through — rather than in a second gate beside it.

## Open questions

- **Should creatures ever route?** A predator committed to a hunt has a
  real destination, which is the one creature case that looks like a
  villager's. Left reactive for now, deliberately.
- **Where does terrain passability belong?** `TerrainPassability` already
  answers slope, and water already blocks ground cover. Neither is wired
  into either navigation path yet, so agents still walk up cliffs and
  across rivers.
- **Cross-chunk routing.** The node budget bounds a search, but a
  destination in a chunk that is not loaded cannot be routed to at all.
  Villagers never have one today; carters and traders eventually might.
- **Do routes need to be shared?** Many villagers walking the same street
  each solve the same A\*. A cached per-settlement route graph would be
  the natural answer if it ever measures as a cost.
