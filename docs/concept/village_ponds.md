# Village ponds

*Asked for directly: "The Fisher should build a similar 3x2 enclosure but
filled with water and a pond with river water physics and fish swimming in
it which reproduce".*

A fisher who lives in a village should not have to be born beside a river.
The farmer's answer to "where do you work" is a fenced 3×2 bed outside their
own door ([village_farms.md](village_farms.md)); this is the same answer for
the fisher, dug rather than sown.

## Design pillars

- **The same shape as a field, because it is the same idea.** A 3×2 or 2×3
  rectangle to the sides and downwards of the house, nearest first, with a
  fence frame round it. Everything about siting, fencing and reloading is
  `VillageFarm`'s, reused rather than restated — a pond that sited itself by
  its own rule would drift away from the field it is modelled on.
- **A pond is real water, not a picture of water.** It is the SAME water
  every other system already understands: creatures refuse it, the surface
  paints it, its flow moves what floats in it. The alternative — a decorative
  pond with special cases in every consumer — is how a world stops being one
  world.
- **Fish live there, and go on living there.** A pond stocked once and
  fished flat is a bucket. A pond whose fish breed toward what the water can
  feed is a fishery.

## Real-world grounding

A village fishpond is not an ornament: carp ponds are the standard medieval
answer to "fish on a Friday, nowhere near the sea", dug beside a settlement
and stocked deliberately. They are small — a few tens of metres — fed by a
diverted channel rather than still, and their stock is managed: netted down
in autumn, left to breed back. Three tiles by two, moving water, a
population with a ceiling, is a fair miniature of that.

## Mechanism

### The pond is a field of water

`VillagePond.pond_rect` is `VillageFarm.field_rect` with the fisher's own
building, and its frame is `VillageFarm.fence_cells`/`fence_facing`
unchanged. Identical geometry, identical rails, identical gate rule.

### Built water

A pond cell is an ordinary chunk modification, `pond_water`, exactly like a
rail — which is what makes it survive a reload with nothing else stored. Two
world queries widen to include it and everything else follows for free:

- `is_water_at_global` — so creatures refuse to walk in
  (`CreatureMarker`), the water surface paints it, and anything that asks
  "is this water" gets the right answer.
- `is_river_at_global` — so it carries the river **flow** the ask names:
  the flow overlay draws on it and `FishMarker` reads a current there.

It is `OVERLAY_ONLY_TILE_IDS`-adjacent in spirit but not in fact: unlike a
rail it *replaces* the ground, because that is the point.

### Fish that reproduce

A pond holds its own small population, grown on the world's own ecology tick
toward a carrying capacity derived from the water it has. Stocking is not
spontaneous: a pond starts empty and the fisher stocks it, which is what a
village actually does.

## Status

- ✅ **`VillagePond.pond_rect` and its frame.** Delegated to
  `VillageFarm.field_rect`/`fence_cells` rather than restated, and the tests
  pin the sameness as hard as the pond: a pond that sited or fenced itself by
  its own rule would drift away from the field it is modelled on.
- ✅ **`pond_water` as built water.** `is_water_at_global` and
  `is_river_at_global` both answer for it, so creatures refuse it, the
  surface paints it and its flow moves what floats in it, with no case of its
  own anywhere else. `is_buildable_ground_at` refuses it too — the fisher's
  own water is not somewhere to put a house. Filling one in gives the dry
  ground back.
- ✅ **A fisher's house digs one.** Sited against the house that carries the
  `fisher` occupation, since a fisher lives in an ordinary house and there is
  no separate building to hang it on. Fenced on the field's own rule, through
  the field's own skips.

  Idempotence needed its own answer, and a reload proved it: "a pond cell is
  occupied, so no pond fits there again" is not enough, because another
  rectangle in the same reach still fits and the fisher got a second pond on
  every chunk load. `_has_pond_already` asks whether the house has water at
  all.
- ✅ **Fish that live there and breed.** A pond holds its own stock, keyed
  by the ANCHOR cell of that body of water (its top-left, found by flooding
  it) — one pond is one stock however many cells it has, rather than six
  buckets. `VillagePond.carrying_capacity`/`step` are the world's OWN
  `AquaticPopulationModel`, not a second curve: a pond is a small body of
  water, and fish in it breed for the same reasons and at the same rate as
  fish anywhere else. `EarthChunkManager.step_ponds` runs it on the world's
  ecology tick, wired into `_step_ecology_batch` and pinned there by a
  source-contract test — a step nothing calls breeds nothing, which is a bug
  this repo has already shipped once with wild crops.

  **Stocking is a real act.** Growth is logistic, so nothing grows from
  nothing: water nobody stocked stays empty however long it ticks. The
  village stocks the pond as it digs it, and stocking an already-stocked
  pond changes nothing — a fisher stocks a pond, they do not keep stocking
  it.
- ✅ **Fish you can SEE in it.** Real `FishMarker`s stand on the pond's own
  water, one per whole fish and at most one per tile — six tiles is a pond,
  not a shoal. Kept in step with the stock on every stocking, breeding tick
  and catch, and freed with the chunk. Deliberately NOT in `_loaded_fish`:
  that list is respawned wholesale whenever a chunk's aggregate fish
  population is reconciled, which would wipe a pond's own fish every time the
  region's did anything.
- ✅ **The fisher works it.** `_step_pond` is the fisher's own work tick, the
  same shape and the same override `_step_farm` has: on the clock they stand
  over their water and cast, off it the cast is dropped and what their house
  holds goes to the village. A cast costs `FarmerBehavior.WORK_SECONDS` —
  what a piece of field work already costs, so fishing and farming are one
  effort rather than two tunings to keep in step.

  The catch walks the chain [village_farms.md](village_farms.md) already
  describes, through the same functions: `_store_harvest` into the fisher's
  own house, `haul_stock_to_village` at the end of the block. The field that
  holds it is `stock_building_cell` now, renamed from `farmhouse_cell` —
  it is a farmer's farmhouse and a fisher's cottage, and a field called
  farmhouse_cell holding a cottage would be a lie in the one place a reader
  goes to check where a catch went.

  A pond fished below one whole fish gives nothing until it breeds back, and
  a fisher with no pond keeps the open water their quarry model already gives
  them.


## A pond that is actually a pond (2026-09-19)

Reported in one go, and all three parts were true: *"there's no real pond
with river / lake water physics... also it's randomly placed somewhere not
adjacent to the fishers house or across the street.. it's a procedural
entity layn over and not properly dug / built pond"*.

**It was not water you could get into.** A pond has answered
`is_water_at_global` since the feature landed -- which is why nothing is
ever built or grown on one -- but it carried no DEPTH, and the player's
water state is the maximum of ocean, river and lake depth. A pond is none
of those three, so a fisher's pond was water a player walked over on dry
feet. `VillagePond.DEPTH_METERS` (1.8) is the fourth source now, asked
alongside the others. A flat depth, not a solved one: a dug pond is a hole
somebody dug to a depth they chose. The figure is the standard temperate
one for a pond that can overwinter fish -- which is what a fisher digs one
FOR -- and it is pinned against `WaterMovementModel.WADE_DEPTH_METERS`
rather than as a bare number, because what matters in play is that it
reads as water to swim in rather than a puddle to walk through.

**It was across the street.** Measured at the first grassland village with
a fisher: 3.0 tiles from the house with a whole street row between them.
A pond is sited by `VillageFarm.field_rect`, and that search refuses ground
NORTH of the building -- true for a farmhouse, where north is the next row
of buildings, and exactly wrong for a fisher, whose house fronts the
street to the south so that every scrap of their own ground is behind
them. All 32 free cells on that fisher's own side were north of the house,
so a search that could only look south had nowhere to go but over the
road. `field_rect`/`field_cells` gained an opt-in `behind` that only the
pond passes, plus a guard that no street row may lie between the house and
any cell of the water. Deliberately NOT "adjacent": ground out the back is
a fine place for a pond, and demanding adjacency would leave most villages
with none at all.

Two things that shook out of opening the ground behind a house, each
caught by an existing test rather than by inspection: a pond could swallow
the village well and another villager's beds (the dig now takes the same
`reserved` set the farm pass does, plus the beds it just laid -- a bed is
not a tile modification, only its rails are, so `is_occupied` cannot see
one); and `_has_pond_already`/`_pond_water_near` still looked SOUTH, so a
reload could not find the pond it had already dug and dug another every
load -- precisely what `_has_pond_already`'s own doc comment warns about.

**It was laid over, not dug.** The blue was the flat `pond_water`
modification tile and nothing else. Every other kind of water rides one
overlay (hydrology.md's "ONE WATER SURFACE"), which is what gives it a
waterline, an ink edge, a shore feather and ripples --  and
`_paint_river_flow_overlay` works that out from the GENERATOR, the one
thing that cannot know about a modification. A pond fell through to
"nothing is water here" and had its overlay cell erased outright (measured:
source id -1 on a freshly dug pond). It is answered before the probe now,
as still water with zero current. Its cross-section is read off its own
shape rather than solved -- it has no channel and no spill to contour from
-- so a cell with dry ground orthogonally beside it reads near the
waterline and a cell surrounded by its own water reads as open water. On a
3x2 pond every cell is a rim cell, which is correct: a pond that small IS
all shore.

**Not verified in a live session.** Every number above is headless
measurement; the screenshots have not been re-taken.
