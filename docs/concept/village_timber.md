# Village Timber — the sawmill, and the villager whose trade it is

Reported in play: *"The sawmill also never produces any beams and doesn't
even have a dedicated worker"*, then: *"implement the sawmill properly"*.

## What this is not

Not a new production model. `SagewerkProduction` already turns a log
stockpile into beams and planks over time, with both costs and both shaping
times measured against real joinery (hewing a round log square wastes
sapwood and is slow; riving boards off it is cheap and fast) and pinned by
tests rather than eyeballed. That module is the sawmill's own behaviour and
is reused whole.

Not a new worker loop either. `LumberjackBehavior` is already the phase
machine for exactly this job — SEEKING → APPROACHING → FELLING → CARRYING →
DEPOSIT — and `ChoppableTree.take_damage` is already how a tree comes down,
"the same mechanic with a different caller" that the tile-scale Lumberjack
uses.

## The gap, stated precisely

Both of those serve the **placeable tile** `sagewerk`, which the player
builds and which spawns its own narrow `LumberjackMarker`.

The village's whole-building **`sawmill`** has none of it.
`VillageRenderer.INDUSTRY_BUILDING_ID` is placed at founding and referenced
by the growth-site search, and **nowhere else**. Nothing works it, nothing
produces at it, nothing is stored in it.

And there is a reason no villager works it: **no villager has that trade.**
`NpcIdentity.OCCUPATIONS` is farmer, blacksmith, merchant, guard, fisher,
herbalist, hunter, nurse. A village raises a sawmill at its own timber and
then has nobody whose job is timber.

## Design pillars

1. **A trade, not a machine.** The sawmill produces because a *person* works
   it, the same way the farmhouse produces because a farmer walks out to a
   field. A building that converts stock on a timer with nobody in it is the
   thing this project keeps replacing.
2. **Reuse the tile-scale pieces whole.** `SagewerkProduction` for the
   conversion, `LumberjackBehavior` for the phases, `ChoppableTree` for the
   felling. A second timber model would drift from the first.
3. **Real trees, felled for real.** A villager's axe is the same axe: the
   log exists because a tree came down, not because a number went up. The
   same "work against the real world" rule
   [npc.md](npc.md) already holds the hunter and the farmer to.
4. **The sawmill holds what it makes**, and the village gets it when someone
   carries it in — the chain [building_storage.md](building_storage.md)
   already establishes for the farmhouse.

## Real-world grounding

A village sawmill sits where the timber is, and a sawyer's day is two jobs,
not one: get logs to the mill, and work the mill. The felling happens out in
the wood, the shaping happens at the building, and the beams stack up at the
mill until they are wanted. Squaring a beam is slow, skilled work that wastes
material; sawing boards is quick and wastes little — which is why a beam
costs three logs and a plank one.

## Mechanism

### The trade

`lumberjack` joins `NpcIdentity.OCCUPATIONS`. This is a real change to every
village's roster — the occupation of each villager is drawn from that list by
seed, so adding to it re-rolls who is who everywhere. That is the honest cost
of a village having a timber trade at all, and it is stated rather than
hidden.

### `VillageSawmill` — the pure rule set

The sibling of `VillageFarm`, and deliberately the same shape: which building
is the sawmill, which occupation works it, how far a lumberjack ranges for
timber, and what wants doing next.

- `next_action(log_stock)` → `"fell"` when the mill wants logs, `"shape"`
  when it has enough to square a beam. Grounded on
  `SagewerkProduction.LOG_COST_PER_BEAM`, never a second number.
- A lumberjack ranges for trees within a real radius of the mill, so a
  village fells its own wood rather than stripping the map.

### The villager's work

`NpcMarker._step_timber(delta, is_working)` — the third sibling of
`_step_hunt` and `_step_farm`, built on the same four seams (find → position
→ reach → act) and returning a walk target or null exactly as they do, so it
plugs into the same override chain with the same "real work outranks a need"
ordering.

- **Fell:** walk to the nearest standing tree in range and bring it down with
  the same `ChoppableTree.take_damage` loop the player's own axe uses. The
  log goes into the sawmill's stock.
- **Shape:** at the mill, with enough logs in it, work `SagewerkProduction`
  forward and put the beam into the sawmill's own stock.

### The beams reach the village

The sawmill's stock is carried to the village the same way the farmhouse's
is, through the same haul.

### Somebody in the village has the trade

Reported in play with the mill's own panel in shot: *"The sawmill also
doesn't produce beams or plangs or logs"*.

The first cause was Mechanism 7's (the sawyer carried the shelf off at the
end of every work block). The second is the one this file was written for in
the first place — *"the sawmill never produces any beams and doesn't even
have a dedicated worker"* — and it came back, quietly, when `carter` joined
`NpcIdentity.OCCUPATIONS`: a trade is rolled by index, so a tenth occupation
re-rolls every villager, and the conscription that guarantees a carter takes
one villager off the end of the roster who may well have been the only
sawyer.

Measured (`tools/probe_trades_after_conscription.gd`, the 75 real grassland
villages in rows 0–5): **14 of them, 18.7%, had nobody whose trade is
timber** — and a mill with nobody to work it produces exactly nothing,
whatever else is fixed.

So a village staffs a sawyer the same way it staffs its food producers and
its carter: if the founding roster rolled none, one villager who is not
already feeding the village is conscripted into the trade. Scoped to the
FOUNDING roster on both halves — who is looked for and who is taken — so
growth never hands the axe to a newcomer and gives the old sawyer their
rolled trade back.

**A sawyer in a village with no timber is not wasted.** They keep the
regional drip every villager without a worksite already lives on, exactly as
a farmer with no farmhouse does. That is the same honest fallback this file's
own Mechanism already relies on: *"A village with no timber in reach raised
no mill, and its sawyer honestly has no sawmill work"*.

## Status

Written before implementation, per CLAUDE.md. Corrected as each slice lands.

- ✅ **`lumberjack` is a real village trade**, and the sawmill is a real
  place on the village map so their schedule resolves to the mill rather than
  to a decorative workspot. Adding to `OCCUPATIONS` re-rolled every village's
  roster, exactly as the spec warned — three tests that had silently depended
  on seed 1's old trade were pinned to a trade of their own rather than
  papered over.
- ✅ **`VillageSawmill`**, the pure rule set. `LOGS_PER_BEAM` is
  `SagewerkProduction`'s own measured cost re-exported, pinned to it by test.
  `TIMBER_REACH_TILES` is grounded on `VillageLayout.INDUSTRY_FOREST_REACH_
  TILES` — a mill sited beside timber must be able to reach that timber —
  with room to work outward as the near trees come down. Short of a beam's
  worth the answer is still `FELL`: a sawyer waiting at the mill for logs
  nobody is fetching is a mill that stops the moment it runs down.
  `test_village_sawmill.gd` 9/9.
- ✅ **`NpcMarker._step_timber`** — the third sibling of `_step_hunt` and
  `_step_farm`, on `LumberjackBehavior`'s own phase machine, felling real
  trees with the same `ChoppableTree.take_damage` loop the player's axe uses.
  Logs go into the mill; at the mill, with enough of them, a beam is squared
  over `SagewerkProduction`'s own shaping time and the logs really leave the
  stock. Timber out of the mill's range is left standing.
  `test_npc_marker_timber.gd` 15/15.
- ✅ **The renderer tells a lumberjack which sawmill is theirs**, and nobody
  else. `test_village_renderer.gd` 94/94.
- ✅ **Beams reach the village stock**, through the same store-then-haul the
  farmhouse runs and paid once on arrival. Beams only: the logs a mill holds
  are its own raw material, and carrying those off would carry away the thing
  the sawmill exists to work.

## Interaction with other docs

- [timber_construction.md](timber_construction.md) — the tile-scale
  Sägewerk, `SagewerkProduction`, `LumberjackBehavior`, and the hewing/riving
  grounding every number here comes from.
- [village_farms.md](village_farms.md) — the farmhouse this is modelled on,
  beat for beat.
- [building_storage.md](building_storage.md) — the store-then-haul chain the
  beams travel.
- [npc.md](npc.md) — "Work against the real world, not against a number".
- [production_chains.md](production_chains.md) — where beams and planks go
  once the village has them.
