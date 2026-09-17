# Village Farms: a farmhouse, its own field, and the villager who works it

A village's **farmer** grows real wheat and its **herbalist** grows real
herbs, on real tiles that belong to a real **farmhouse** building. Every
crop tile adjacent to a farmhouse is tied to *that* farmhouse, so a village
that raises two farmhouses gets two fields with two separate workers —
Anno's rule, where a field is worked by the farm it lies beside.

Reported in play:

> The village needs a farmer which grows wheat like in Anno... every tile of
> wheat planted adjacent to a farm house may be tied to a farm house (so you
> can build multiple farms) ... similar to a farmer the herbalist should
> build a farm house and plant herbs ... the farm houses are separate
> buildings and the farmer / herbalist goes to work regularly...

## What this is not

It is **not** [npc_farm_production.md](npc_farm_production.md) a second
time. That doc gives the PLAYER a placeable `"farm"` tile with a dedicated
`FarmerMarker` structure-worker tending three plots at fixed offsets — a
narrow-purpose walker with no schedule, no hunger, no wallet. This doc is
about the VILLAGE's own occupation villagers: full `NpcMarker`s with daily
schedules and a real economy, who until now had nothing to farm at all
(`NpcProduction.PRODUCER_ITEM_BY_OCCUPATION` gave the `farmer` occupation a
`"fruit"` drip off ambient vegetation density, and gave the `herbalist`
nothing).

Both keep existing. They share the substrate — `FarmPlot`,
`FarmPlotMarker`, `FarmerBehavior` — and nothing else.

## Design pillars

1. **One growth model, not a third one.** A village field tile is a
   `FarmPlotMarker` holding a `FarmPlot`, the same deterministic
   plant/water/harvest lifecycle the player's own hand-tilled plot and the
   placeable Farm already use, reached through
   `EarthChunkManager.till_and_plant_farm_plot_at_global`/
   `water_farm_plot_at_global`/`harvest_farm_plot_at_global`. No second
   growth formula to keep in sync.
2. **The field belongs to the farmhouse, and the rule is geometry, not a
   record.** A tile's owner is derived from where it lies, every time it is
   asked — the same "nothing persisted, re-derive it" property the village
   plaza already has ([building.md](building.md)). Two farmhouses in one
   village each own their own ground and no tile is ever worked twice,
   because the rule is a total function: nearest farmhouse wins, ties broken
   deterministically.
3. **Work against the real world, not against a number.** The same rule
   [npc.md](npc.md) applies to the hunter and the fisher: while a villager
   has real field work in reach, the regional production drip is off and
   their income comes from what they actually harvested. A farmer with no
   farmhouse falls back to the drip exactly as before.
4. **The villager goes to work, and goes home.** The field is worked during
   the villager's own `work` schedule block and not otherwise. Crops
   planted in the evening are not tended overnight and wither; the farmer
   re-tills and re-plants them in the morning. This is a real consequence of
   an honest schedule, stated rather than engineered around — see "What
   withers, and why that is fine" below.
5. **Tuned values are tested functions or test-pinned constants**, per
   CLAUDE.md. Field capacity in particular is *measured* — one villager can
   keep only so many plots watered on a walking circuit — not asserted in a
   comment.

## Real-world grounding

- **A farmstead's home field.** The ground immediately around a farmhouse
  is the ground its household works: close enough to walk out to between
  other chores, fenced in by the yard rather than by distance. A field two
  villages away belongs to nobody. Adjacency *is* the historical ownership
  rule for an infield, which is why it is the rule here.
- **Two farmsteads, two infields.** Where two farmsteads stand near each
  other, the ground between them is split — each works what lies closer to
  its own yard. That is the tie-break rule below, not an invented one.
- **Wheat is a grain, herbs are a crop you cut.** Wheat already exists in
  this codebase as a real material with real art
  ([long_grass.md](long_grass.md)'s wheat atlas family). `herb` is new here,
  and it closes a gap another doc already named:
  `CookingRecipeBook`'s `fish_herb` → *Herbed Fish* recipe has always been
  unreachable because `ItemCatalog` had no `herb` item to cook with
  (`occupation_production.gd` says so in as many words). An herbalist who
  grows herbs is where herbs come from.
- **Why the herbalist gets the same building.** A herb garden and a wheat
  field are the same arrangement — a dwelling with worked ground around it.
  Giving the herbalist a second building id would be two mechanisms where
  the world only has one.

## Mechanism

### `VillageFarm` — the pure rule set

A new pure module (`src/gameplay/village_farm.gd`), the same
decides-the-rules / owns-the-effect split `HuntableQuarry` already draws
against `NpcMarker`:

- `FARM_BUILDING_ID := "farmhouse"` — pinned to
  `BuildingCatalog.PRODUCTION_BUILDING_IDS`, not spelled twice.
- `CROP_BY_OCCUPATION := {"farmer": "wheat", "herbalist": "herb"}` — the
  same table shape `NpcMarker.QUARRY_KIND_BY_OCCUPATION` already uses for
  hunter/fisher. An occupation absent from it has no field, which is the
  honest answer for every other villager.
- `field_cells(origin, building_id)` → the ring of tiles directly adjacent
  to the building's own footprint, in a deterministic order. For the 3×2
  farmhouse that is the 5×4 rectangle around it minus the 6 cells the
  building stands on: **14 tiles**, computed from the catalog footprint
  rather than written down.
- `owner_of(cell, farmhouse_origins, building_id)` → the origin of the
  farmhouse that claims `cell`, or `null`. A cell is claimed by the
  farmhouse whose footprint it is adjacent to; where two claim it, the one
  whose footprint is **nearer** (Chebyshev distance to the rectangle) wins,
  and an exact tie goes to the lower `(y, x)` origin. Total and
  deterministic: asked twice, it answers the same, and no cell ever has two
  owners.
- `next_action(states)` → which owned cell to work next and what to do
  there: **harvest** a ready plot, else **plant** an empty or withered one,
  else **water** a growing one that has used up
  `WATER_BEFORE_WITHER_FRACTION` of its real wither grace. This is exactly
  the priority `FarmerMarker._next_action_plot_index` already runs; it moves
  here so both the placeable Farm's worker and the village's own villager
  read one rule instead of two copies.

### The farmhouse

`BuildingCatalog`'s existing `farmhouse` (3×2, `farmstead` interior, already
on the growth ladder and already carrying real art). The village raises
**one per farming villager** — a farmer and a herbalist in the same village
get one each, which is what "so you can build multiple farms" asks for.

Siting reuses the village's own street-frontage rule
(`VillageLayout.next_street_plot`), with one added condition: a farmhouse
is only raised where its field ring has real room, so a farmhouse never
stands with nowhere to farm. Placed with the same self-healing
`_place_*_if_missing` shape the sawmill and the city hall already use, so an
older village gains its farmhouses on its next visit rather than only at
founding.

### The villager's work

`NpcMarker` gains `_step_farm(delta, is_working)`, a sibling of the existing
`_step_hunt` and built on the same four seams (find → position → reach →
act) and the same `FarmerBehavior` phase machine the placeable Farm's worker
uses:

- While the schedule says `work` and this villager's occupation is in
  `CROP_BY_OCCUPATION`, find their own farmhouse (the nearest
  `farmhouse` in their own settlement chunk that no other farming villager
  has already claimed) and ask `VillageFarm.next_action` over the field it
  owns.
- Walk to that cell — `_step_farm` returns it as the movement target, the
  same way a real quarry overrides the hunter's decorative workspot.
- On arrival, a real `WORK_SECONDS` dwell, then the actual
  till-and-plant / water / harvest call against the world.
- A harvest credits the village market through
  `NpcEconomy.record_real_catch`, the same paid, undepleted path a real deer
  or fish already takes.

With no farmhouse (an unloaded chunk, a village too small to have raised
one), `_step_farm` returns null and the villager keeps the schedule and the
regional drip they always had.

### What withers, and why that is fine

A day is `ChunkEcologyCatchup.SECONDS_PER_DAY` = 3600 real seconds, split
into four `NpcSchedule.TIME_BLOCKS`, so a work block is ~900 s. A
`FarmPlot`'s whole cycle is 20–60 s and its wither grace is half its growth
time (10–30 s). Two consequences, both real:

- **During a work block a field cycles many times.** 900 s of tending against
  a 20–60 s crop is 15–45 harvests' worth of opportunity, not one.
- **Overnight, everything growing withers.** Nobody is watering it. The
  farmer re-tills and re-plants in the morning. Against 15–45 cycles a day,
  losing the last one is a rounding error, and a field that looks tended by
  day and fallow at dawn is what a field looks like.

Field capacity follows from the same arithmetic and is **measured, not
capped by hand**: a full circuit of N plots costs about
N × (`FarmerBehavior.WORK_SECONDS` + walk), against a 10–30 s grace, so one
villager sustains only a handful. A second farmhouse — a second worker — is
how a village grows its output. That is the Anno shape the report asks for,
and it is why ownership has to be per-farmhouse rather than per-village.

### Persistence

Nothing new is stored. The farmhouse is an ordinary persisted building; the
field is re-derived from its origin every time; the plots live in
`EarthChunkManager._farm_plots` exactly as a player's own do, with the same
already-accepted "plot state does not survive a chunk unload" gap
[npc_farm_production.md](npc_farm_production.md) records for the placeable
Farm. A reloaded village re-derives the same field and starts tilling it
again.

## Interaction with other docs

- **[npc_farm_production.md](npc_farm_production.md)** — the placeable
  Farm's structure-worker. Shares `FarmPlot`/`FarmPlotMarker`/
  `FarmerBehavior` and now the `next_action` priority rule; nothing else.
- **[npc.md](npc.md)** — "Work against the real world, not against a
  number". The farmer and herbalist join the hunter and fisher on that
  rule; the `"fruit"` drip stays as the no-farmhouse fallback.
- **[farming.md](farming.md)** — the player's own hand-tilled loop, the
  substrate this reuses unchanged.
- **[milling_and_baking.md](milling_and_baking.md)** — village wheat is the
  same `wheat` item the Mill already consumes, so a village farm feeds a
  chain that already exists.
- **[cooking.md](cooking.md)** — `herb` becoming a real item makes
  `CookingRecipeBook`'s `fish_herb` → *Herbed Fish* reachable for the first
  time.
- **[village_growth.md](village_growth.md)** — the farmhouse is already on
  the growth ladder; this gives it a worker and a purpose.

## Status

⬜ Everything below is the plan; this section is rewritten to ✅/🚧 against
what actually lands, per CLAUDE.md.

- ⬜ `VillageFarm` pure module: field ring from the catalog footprint,
  per-farmhouse ownership with a deterministic tie-break, crop by
  occupation, the shared `next_action` priority.
- ⬜ A real `herb` item, and herb crop art.
- ⬜ One farmhouse per farming villager, sited where its field fits, raised
  by the same self-healing path as the sawmill.
- ⬜ `NpcMarker._step_farm`: the villager walks out to their own field
  during their work block and really tills, waters and harvests it.
- ⬜ A harvest credits the village market, and the regional drip is off
  while real field work is in reach.
- ⬜ A measured yield-per-work-block figure, pinned by a test rather than
  claimed here.
