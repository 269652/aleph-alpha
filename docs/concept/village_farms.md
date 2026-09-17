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
- `field_cells(origin, building_id)` → the ground a farmhouse may work:
  out to the **sides and downwards**, never north, offered nearest-first
  out to `FIELD_REACH_TILES`. Asked for directly — *"the farmhouses should
  be placed adjacent to the main street and the fields be placed sideways
  and downwards of it"*. A village house fronts the street with its door
  south, so the ground north of a farmhouse is the next row of buildings,
  not somewhere to sow. More cells are offered than any farmhouse works;
  the caller filters them for water, paving and what is already built on
  and takes the first `MAX_WORKED_CELLS`, which is what makes it the
  biggest field that actually fits rather than whichever cells came up.
- `owner_of(cell, farmhouse_origins, building_id)` → the origin of the
  farmhouse that claims `cell`, or `null`. A cell is claimed by the
  farmhouse whose footprint it is adjacent to; where two claim it, the one
  whose footprint is **nearer** (Chebyshev distance to the rectangle) wins,
  and an exact tie goes to the lower `(y, x)` origin. Total and
  deterministic: asked twice, it answers the same, and no cell ever has two
  owners.
- `next_action(states)` → which owned cell to work next: **harvest** a
  ready plot, else **water** a growing one past its margin, else **plant**
  a bare or withered one, else **tend the thirstiest** growing bed. The
  last two are not decoration — see "What a field costs to keep" below.
  The rule lives here so both the placeable Farm's worker and the village's
  own villager read one priority instead of two copies.

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

### What a field costs to keep

A day is `ChunkEcologyCatchup.SECONDS_PER_DAY` = 3600 s in four
`NpcSchedule.TIME_BLOCKS`, so a work block is ~900 s, against a `FarmPlot`
cycle of 20–60 s whose wither grace is half its growth time. A field is
therefore not a thing you sow and come back to; it is a circuit, and the
circuit has to out-run the grace.

Two rules make that work, both found by measuring a real work block rather
than by reading the code:

- **A visit waters the beds around it.** You water a *bed*, and the water
  runs to the beds beside it; one trip with a can or along a furrow wets
  the ground around where you stand. `TEND_REACH_TILES` is one tile.
- **A farmer in their own field never stands still.** With nothing ripe,
  nothing dying and nothing bare, they tend the thirstiest bed. And
  watering comes *before* planting: a bed already sown is work already
  done, so saving it beats breaking new ground.

Without those two, a three-tile field over one work block ran **108
replants, 72 waterings and zero harvests** — every bed died on the vine
because the farmer planted instead of watering, and idled between
thresholds. With them, measured wheat per work block:

| field | wheat | | field | wheat |
|------:|------:|-|------:|------:|
| 3 | 170 | | 8 | 215 |
| 4 | 208 | | 10 | 215 |
| 6 | 225 | | 14 | 215 |

A ten-tile field — the size asked for — produces about **eight times the
ambient drip it replaces**. The yield also **saturates around six to
eight**: past that the farmer cannot walk further in the time the crop
gives them, so the extra tiles are ground they never reach. `MAX_WORKED_CELLS`
is the limit that was asked for; the saturation is why a village grows its
output by raising a second farmhouse rather than a bigger field.

Crops still wither overnight, when nobody is watering at all, and the
farmer re-tills in the morning. Against 50–66 harvests in a working day
that is a rounding error, and a field tended by day and fallow at dawn is
what a field looks like.

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

- ✅ **`VillageFarm`, the pure rule set.** `field_cells` derives the ring
  from `BuildingCatalog`'s own footprint (5×4 minus the 3×2 the farmhouse
  stands on = 14 tiles); `owner_of` is total and deterministic (nearest
  footprint centre, ties by lower `(y, x)`), so no tile ever answers to two
  farmhouses and nothing is persisted; `crop_for` gives the farmer wheat and
  the herbalist herbs; `action_for`/`next_action` carry the harvest > plant >
  water priority, which `FarmerMarker` now delegates to instead of keeping
  its own copy. `test_village_farm.gd` 29/29.
- ✅ **`herb` is a real item.** Driven by a failing test that every crop a
  village grows must be something the world can hold. It also closes a gap
  another file named outright: `CookingRecipeBook`'s `fish_herb` → *Herbed
  Fish* has always asked for an ingredient `ItemCatalog` did not have.
- ✅ **One farmhouse per farming villager**, sited on street frontage with
  real room for a field. `VillageLayout.next_street_plot` gained an optional
  `accepts_origin` predicate for exactly that. Placed *over* the paving
  (`place_building_over_roads`), like the city hall — a frontage plot's own
  doorstep is already a road cell by then, and an ordinary `place_building`
  refuses that. Idempotent, so a reload raises no second set and an older
  village gains its farmhouses on the next visit.
- ✅ **`NpcMarker._step_farm`.** The villager walks out to their own field
  during their work block and really tills, waters and harvests it through
  the same `FarmPlot` lifecycle a player's own plot uses. Each farming
  villager is handed the cells their own farmhouse owns, paired in roster
  order against farmhouses in `(y, x)` order so the same villager gets the
  same field on every reload. `test_npc_marker_farming.gd` 14/14.
- ✅ **A harvest is real village stock and real pay.**
  `NpcEconomy.record_real_harvest` credits the crop actually grown at the
  same rate a gathered unit earns. `record_real_catch` could not do this
  job: it credits whatever the occupation *drips* ("fruit" for a farmer,
  not the wheat in the field), and the herbalist is in no producer table at
  all. The regional drip is off for the whole work block while a villager
  has a field, exactly as a real hunt switches it off.
- ✅ **A ten-tile field, sideways and downwards, that really produces.**
  Asked for directly: *"The space the farmhouse utilizes should be
  maximized and capped to 10 tiles ... each farmhouse needs to be connected
  by a street ... the fields be placed sideways and downwards of it"*.
  `MAX_WORKED_CELLS` is 10, the field is a directed region rather than a
  ring, and a farmhouse takes street frontage when there is any and the
  outskirts with a paved spur when there is not — so every farmhouse is
  connected to a street either way.

  Getting a field that size to yield anything took two real fixes, both
  found by measuring a work block rather than by reading the code: watering
  now comes before planting (a bed already sown is work already done), and
  a farmer with nothing urgent tends the thirstiest bed instead of standing
  still. Without them a three-tile field ran 108 replants, 72 waterings and
  ZERO harvests. With them, 10 tiles yields ~215 wheat per work block,
  about eight times the drip it replaces — and the yield saturates around
  six to eight tiles, which is why a second farmhouse, not a bigger field,
  is how a village grows its output. Full table in "What a field costs to
  keep" above.

Honest gaps, each real:

- 🚧 **A herb plot renders as bare tilled soil.** `IllustratedCropSprite`
  has entries for carrot and potato, and `FarmPlotMarker` has a dedicated
  wheat path; an unregistered crop's `leaf_texture` returns null, so herbs
  grow invisibly. Exactly the gap
  [npc_farm_production.md](npc_farm_production.md) recorded for wheat before
  [long_grass.md](long_grass.md)'s wheat atlas closed it — an asset
  question, not a logic one. `herb` has no inventory art either and falls
  back to the procedural item sprite.
- 🚧 **Ten of a farmhouse's fourteen ring tiles lie fallow.** That is the
  measured capacity above, not an oversight, but it does mean a farmhouse
  visibly works only part of its own yard. A second worker per farmhouse
  would be the honest way to use the rest, and nothing models one.
- 🚧 **Plot state does not survive a chunk unload**, the same already-
  accepted gap the placeable Farm carries: a revisited village re-tills its
  field from scratch. A closed-form catch-up (the shape
  `chunk_ecology_catchup.gd` uses) is the real fix and is not attempted
  here.
- ⬜ **Nothing yet notices a village that wants a second farmhouse.** The
  village raises one per farming villager and stops. Growing the chain on
  demand is `SettlementBuildDecision`'s to answer, and it reports *missing*
  producers rather than insufficient throughput — the same open question
  [npc_farm_production.md](npc_farm_production.md) already records.
