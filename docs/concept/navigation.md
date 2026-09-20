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

- **Villagers walked through houses.** Fixed by `NpcBuildingGate` (see
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

`NpcBuildingGate` stays underneath as the last line of defence. A route
can go stale — a house can be raised across it mid-walk — and the gate
is what guarantees that even a stale route never puts a villager inside
a wall.

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

- ⬜ Everything below is the spec; see the Status list at the bottom of
  this file as slices land.

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
