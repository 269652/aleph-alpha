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
  ground back. And **nothing grows in it** (2026-09-20): a pond blocks the
  ground cover like any other built thing, through the one predicate they
  all share — see "Grass in the water" below.
- ✅ **A hut on the bank** (2026-09-20). `fisher_hut`, a real catalog
  building with the farmhouse's own footprint, price and storage, raised on
  the bank of the pond it belongs to by the pond pass itself rather than by
  the growth ladder. Its art is borrowed from the farmhouse through a
  declared `draws_as` until its own sheet is drawn. Full account below, in
  "Water you can see, and a hut over it".

  **And the pond is dug where the hut can stand** (2026-09-20). Siting the
  water without asking whether its own works could stand beside it left one
  real village in three with a pond and no hut at all. The dig asks now,
  and falls back to digging anyway when no bank in reach can take one —
  see "A pond is dug where its hut can stand" below.

  ⚠️ **Two villages in three still have no hut**, and it is measured
  rather than suspected: their fisher's plot genuinely has no room for a
  3x2 works, and the obvious next fix (the frame going round the hut)
  opens zero sites in either. Same section, "What it does not fix".
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

  **And the stock is kept** (2026-09-20), in `POND_FISH_DIR`, because a
  fisher stocking a pond once is only a fishery if the fish are still
  there tomorrow. Full account below, in "A pond keeps its fish".
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


## Water you can see, and a hut over it (2026-09-20)

Reported live with a screenshot, which is the thing the line directly above
says had not been taken: *"The built pond renders as earth instead of water
and it's missing a fisher hut (use farmhouse sprite until illustration
exists)"* — a fenced brown rectangle with the pond's own fish swimming on
it. Two separate faults behind the first half, and both were only ever
visible in a picture.

### It was not painted at all on the visit that dug it

The surface is painted once per chunk load (`_paint_river_flow_overlay`),
and the village that digs the pond runs LATER in that same load
(`spawn_village`) — so the pass had already been and gone, and
`build_at_global` never repainted it. A pond dug on the visit that founded
its village therefore had no water surface until the chunk was next
reloaded, which is every new village a player walks into. What was left on
screen is the bare `pond_water` modification, and the painter has no tile
of its own for it: it falls through `atlas_coords_for_modification`'s
fail-safe to flat earth.

Digging or filling a pond now repaints the surface over that cell **and the
four round it** — a pond's own cross-section is read off its neighbours, so
a cell that was rim water becomes open water the moment the cell beside it
is dug. Five cells, not the whole chunk: the surface pass probes hydrology
per cell and a pond is dug one cell at a time.

### And once painted, it was a puddle

Measured on the first real render: **10.4%** of the pond's own area read as
water. The waterline is the contour where the across field crosses 1, and
that field is reconstructed by INTERPOLATING between cell centres — so
where the water's edge lands is half decided by the DRY cells round it, and
those carried whatever the nearest river had left there, tens of tiles'
worth. The contour crossed 1 a few pixels out from each pond cell's own
centre, and a 3×2 pond read as a small oval in a brown rectangle.

`VillagePond.WATER_ACROSS` and `BANK_ACROSS` are one decision rather than
two: 0 in the water and 2 on the ring one tile out puts the contour exactly
halfway between them, which is the water cell's own edge — the edge of the
hole. `waterline_offset_tiles` states that and a test pins it at half a
tile, so a change to either number that moved the waterline off the pond's
edge fails there rather than on screen. The bank never overrides a real
river's own field, only a value further out than it (a cell between a pond
and a river belongs to whichever water is nearer). Re-rendered on the same
pond: **89.8%**.

### The hut on the bank

A farmer's beds have a farmhouse standing over them; a fisher's water had
nothing at all, which is the half of "the same shape as a field" that was
never built. `fisher_hut` is a real catalog building now — the farmhouse's
own 3×2 footprint, price and storage, since it is the same works beside the
same size of worked ground.

It is sited on the BANK rather than on street frontage
(`VillagePond.hut_origin`): the hut belongs to the water, the water is
already dug and fenced by the time the hut goes up, so there is one obvious
right place for it and no search of the chunk to do. The nearest free site
within `HUT_BANK_REACH_TILES` of the water wins, walked in a fixed order so
the same pond puts the hut in the same place on every reload. Two tiles,
not one: the water is fenced on its own ring, so a hut demanding to touch
it could only ever stand on the rails. Idempotence is asked of the GROUND —
a hut already standing on this pond's bank is this pond's hut — which is
what stops a village growing a second one every time it is walked past.

**And it is an overlay, like every other building.** A hut missing from
`TerrainRenderer.BUILDING_OVERLAY_TILE_IDS` paints the same flat brown
square under itself that list exists to prevent -- found on the merge by
`test_a_whole_building_is_an_overlay_and_paints_no_ground_of_its_own`
rather than by inspection, which is exactly what that test is for.

**The art is borrowed, and says so.** The catalog entry names
`draws_as: "farmhouse"`, and a borrowed sheet is the LAST link of the
building's own chain (`BuildingCatalog.finished_sheet_chain`): the day
`fisher_hut.png` lands it wins with no code change, and removing the one
line is pure tidying. Pinned by
`test_a_borrowed_sheet_never_hides_the_buildings_own`.

**It borrows the yard as well** -- asked for directly the moment the hut
was up beside its pond: *"the fisher hut should get a yard too"*. A
farmhouse stands in one of nine drawn yards (`background_sheet_for`, "A
building's own yard, drawn behind it" in [building.md](building.md)), and
an earlier version of this paragraph argued the hut should not, on the
grounds that a fisher's hut stands on a bank rather than in a farmyard.
That was the wrong call and is recorded as one: a farmhouse in a finished
yard beside a hut on bare plot reads as one building done and the other
forgotten. What `draws_as` borrows is the whole picture -- the house AND
the ground it stands in -- and the hut's OWN seed still picks which of the
nine, so the hut by the pond and the farmhouse up the street are different
pictures.

## Nothing grows in it, and it keeps its fish (2026-09-20)

Reported live with the water in shot: *"Now there's a pond, but grass
grows in it and no fish are in it"*. Two independent faults, neither
visible from anything this doc's status list claimed.

### Grass in the water

`TallGrass` seeds off the chunk's BIOME array, and a pond is deliberately
NOT a biome (see "Built water" above) — so a pond dug out of grassland
still reads as grassland to every ground-cover sim, and the grass already
standing there simply stayed standing. This world has answered that exact
report once before, for rivers: *"grass grows in rivers"*, answered by
`TallGrass._is_river_at`, because a river does not change the biome array
either.

A river is GENERATED, so its answer belongs in the sim. A pond is BUILT,
so its answer is the seam every other built thing already uses:
`EarthChunkManager._is_built_surface`, the one predicate
`build_at_global`, `destroy_at_global` and `_built_local_cells` share for
ground cover. A pond now clears the cover as it is dug and keeps it out
afterwards — grass, flowers, scrub and lichen alike — and filling the
hole in gives the ground back, exactly as pulling out a fence rail does.

Worth stating because a half-fix would have looked like a whole one: the
chunk-load path ALREADY kept grass out, through `_ground_cover_blockers`,
which reads `is_water_at_global` and so has always seen a pond. What it
did not cover is the visit that DIGS one — the sim is built when the
chunk loads and the village digs later in that same load — nor
`TallGrass.plant`, which checks the biome and the block set but not the
water. Both go through `block_cells` now.

**Reeds are a separate question, left open on purpose.** A real fishpond
has vegetation in it, and this world already has a sim for that
(`AquaticVegetation`, which seeds on water as an INCLUSION filter rather
than an exclusion). A dug pond is not in the mask it reads, so a pond
grows nothing at all today. That reads as clean water rather than as
wrong water, and *land* grass standing in a pond was the report.

### A pond keeps its fish

Measured before anything was changed, on two real streamed villages
(`tools/probe_pond_and_farmhouse.gd`): both held a dug, fenced pond, and
both reported a stock of **0.00** with nothing swimming in it.

The water survives because it is a persisted chunk modification, and the
fence survives because it is a persisted chunk modification. The FISH were
an in-memory dictionary keyed by chunk, and the village pass that stocks a
pond only ever runs on the visit that DIGS one —
`_dig_fisher_ponds_if_missing` returns early on a pond that is already
there, which is correct ("a fisher stocks a pond, they do not keep
stocking it"). So a pond was a fishery on the one visit that founded it
and a hole for the rest of the game. Even within a session it came back
wrong: `_free_pond_fish_markers` empties the water on unload and nothing
re-synced it on load, so a stock that did survive in memory had nothing
swimming in it.

`POND_FISH_DIR` persists the stock per chunk, keyed by the pond's own
anchor — saved on unload beside the region's aggregate, merged back on
load with the in-session record winning, which is the same precedence the
region's own fish population already uses. The stock is saved in its OWN
block rather than with the region's, because that block is skipped for a
chunk with no water in it at all, and a landlocked chunk is exactly where
a village digs a pond.

**Persistence, not re-stocking on reload**, and the difference is the
whole point: a pond the village has fished out must stay fished out until
it breeds back, and a reload that quietly refilled it would make the stock
decorative.
`test_a_pond_fished_out_is_still_fished_out_after_a_reload` pins it.

## A pond is dug where its hut can stand (2026-09-20)

Reported live, standing at the water: *"no Fisher Hut is near"*. Measured
on three real streamed villages (`tools/probe_village_geometry.gd`) before
anything was changed: one of them had a pond with **no hut anywhere**, and
not by a near miss. All **51** candidate origins within
`HUT_BANK_REACH_TILES` of that water were refused — 19 by the village
street, 21 by neighbouring houses, 5 by the pond's own fence rail and 6 by
the water itself.

The pond had been dug into the two-row strip between the street and the
next house row, which is exactly wide enough for the water and nothing
else. Two passes that never spoke: the dig took the best rectangle in
reach, and the hut was sited afterwards on whatever bank that left.

### The dig asks first

`VillageFarm.field_rect` gains the caller's-own-condition argument
`VillageLayout.street_plot` has had all along, and for the reason that one
already states: *a farmhouse needs room for its field, and a farmhouse
with nowhere to farm is a farmhouse that should not have been raised.* A
refused rectangle simply keeps the search going, so the fisher gets the
next-best water that does work.

And when no bank in reach can take a hut, a second, unconditional search
digs the pond anyway. **A pond with no hut beats no pond at all**: the
fisher works the water, not the building.

### Asked of the ground as it WILL BE

`hut_origin` is asked at PLACEMENT time, by which point the rails are real
ground and the caller's own `is_free` refuses them. The dig asks the same
question BEFORE either the water or its frame exists, so
`hut_origin_after_fencing` adds the rails by hand — without that, the dig
would happily choose a site whose only bank is the fence it is about to
build. A test pins exactly that case: ground whose only clear band in
reach is the pond's own southern rail line takes a hut under the
placement-time question and none under the dig-time one.

### And a step to its door

Every other building a village places has its doorstep paved as part of
siting the plot, because every other building is sited ON frontage. A hut
belongs to the water instead, so nothing laid its front step and it stood
with its door opening onto bare ground.

That invariant has been false since the hut landed and was hidden by
luck: the fixture village's hut happened to fall with its doorstep on one
of the pond's own rails, so
`test_every_placed_building_faces_south_onto_a_real_road_cell` passed for
the whole lot anyway. Moving the pond by one rectangle broke it, which is that
test doing exactly its job. The step is laid AFTER `place_building`, never
before — `place_building` refuses a plot whose doorstep is already
non-empty, so paving first would refuse the hut over its own future front
step, the same ordering trap the houses' own pass records.

### What it does not fix, and why the obvious next fix is not it

A controlled A/B on a wiped world — the same three villages founded from
nothing, before and after — says the dig-time question is a **no-op in
the two villages that were missing a hut**. Their ponds do not move,
because no other rectangle in reach passes either, so the fallback runs
and the water lands in the same strip. Both of those fishers live at the
far west end of the street, and the street grid boxes them in: one street
row above, the next below, leaving a two-row strip that the water exactly
fills. A 3x2 works plus its doorstep needs three rows.

The obvious next move is to raise the hut BEFORE the frame, so the fence
goes round it the way it already goes round a farmhouse standing in its
field's ring — which would also retire `HUT_BANK_REACH_TILES`' own
stated reason for being 2 rather than 1. **Measured, it is not the fix.**
Walking the same candidate grid again with the pond's own rails, and only
the rails, treated as clear ground opens **7** sites in the village that
already has a hut and **0** in each of the two that do not. The frame is
not what is in the way; the street grid and the neighbours are.

(The first count said 5 and 2, which looked like enough. It was read off
a first-reason tally, and a site whose FIRST refusal is a rail can still
be blocked by a street on another of its cells — an upper bound wearing
an answer's clothes. Recorded because the reorder was about to be written
on it.)

What remains is a design question rather than a defect, and it is the
borrowing itself: a fisher's hut takes the farmhouse's 3x2 footprint
because it is DRAWN as one, and a real fisher's shack is not a farmhouse.

### Honest gaps

- **The catch still goes to the fisher's cottage**, not to the hut. The hut
  holds `storage` like any works, but `stock_building_cell` is still the
  building that carries the `fisher` occupation, and nothing routes a catch
  into the hut yet. It is a building standing over the water, not yet a
  fish store.
- **A hut looks exactly like a farmhouse**, because it is drawn as one. A
  village with both shows two identical buildings until the real sheet
  lands — which is what "use farmhouse sprite until illustration exists"
  asks for, stated here so nobody reads it as a bug.
- **The pond's bed is the flat earth tile** under the water surface, which
  is what shows past the waterline at the pond's own edge. That reads as a
  muddy bank and is left deliberately; it is also the fallback a scene with
  no flow overlay registered would show, where a pond is still a brown
  rectangle.
