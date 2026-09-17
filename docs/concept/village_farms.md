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

### The fence around the beds

Asked for directly, with the field circled in a screenshot: *"the farmhouse
should build a fence around the bed so no animals enter"*.

A farm without a fence is a field that feeds deer. The village raises the
fence **with** the farmhouse, out of the same timber the farmhouse's own
cost already pays for — the identical argument
[npc_farm_production.md](npc_farm_production.md) already makes for the
placeable Farm's gate, whose recipe cost *is* "wood (6) for fence
rails/posts and plant_fibre (4) lashing them".

- **What is enclosed:** the beds the villager actually works — a **compact
  rectangle**, `FIELD_SHAPES` (3×2 or 2×3, whichever fits), not a scattered
  handful of whatever ground happened to be clear. Asked for directly, with
  the broken ring circled in a screenshot: *"The fence should enclose a 2x3
  or 3x2 area"*. A ragged bed set has a ragged ring, and a ragged ring is
  what reads as broken fencing.

  Six beds is also what the yield measurements already pointed at: six
  peaked at 225 wheat per work block and everything from eight to fourteen
  sat at 215 (see "What a field costs to keep"). The shape the report asks
  for and the shape the measurement asks for are the same shape.
- **Where the rails stand:** the rectangle's own **border** — every cell
  touching a bed, on the diagonal as well as the orthogonal so the corners
  close, that is not itself a bed, not the farmhouse's own footprint, not
  water, and not the village's paving. `VillageFarm.fence_cells` is that
  rule, pure and derived — like `field_rect` and `owner_of`, it stores
  nothing, so the same farmhouse fences the same ring on every reload.
- **The frame closes at the corners.** A border's four diagonal cells are
  **corner posts**, not lengths of rail: drawing a horizontal rail across a
  corner is exactly the "broken" look the report points at. The sheet has no
  corner cell of its own, so a corner is drawn with the post art the side
  columns use, which is what a real corner post is. A post knows *which
  side* it caps (`corner_west`/`corner_east`), because it has to stand on
  the same line as the wall below it — one left on its own tile centre would
  sit half a tile off the run it caps, which is a broken joint of its own.
- **The side walls sit on the frame's inner edge.** The two vertical walls
  are drawn on the edge of their own tile that faces the beds. This
  **reverses** an earlier pass, which pushed them half a tile the other way
  on the report *"the side walls of the fence should be moved outwards and
  corner pieces added so it doesn't look that broken"*; the later ask, with
  the west and south sides arrowed toward the beds, is *"move the fences to
  the inner edge of the enclosure and treat the rest of the tile as
  street"*. Everything but the sign survived that reversal: the two walls
  still move by the same distance in opposite directions, and a corner post
  still stands exactly where the wall it caps does. See "The rail stands on
  the inner edge" below, which is the general rule both are now cases of.
- **The gate** is where the ring meets the village's own paving. No rail is
  raised there: the farmer walks in over the street their farmhouse fronts,
  which is the whole reason a farmhouse takes frontage at all. A fence laid
  across the road would wall the village off from its own farm.
- **A street ROW is street, paved or not.** Neither beds nor rails ever land
  on one. The founding layout paves a further street only *between its own
  doorsteps*, so a street row has unpaved gaps in it — and measured on real
  villages, a village that treats those gaps as open ground plants crops and
  drops rails in the middle of its own road with paving either side. It also
  made the frames inconsistent: a field under a paved stretch correctly got
  no north wall, because the street is its boundary, while the field beside
  it got a rail. Derived from the skeleton (`street_y` plus
  `STREET_PITCH_TILES`), so it costs nothing and needs nothing stored.
- **What it does:** a rail shuts one LINE, not one tile.
  `CreatureMarker` refuses the step that would carry an animal across the
  rails and slides along them rather than sticking against them — the
  obstacle its own `_advance` doc comment has always described ("blocked
  by an obstacle, once that lands") and nothing had yet supplied.
  Villagers and the player walk through freely; the fence is a stock
  fence, not a wall. See "The rail stands on the inner edge" below.
- **The rails are real tiles**, `farm_fence`, persisted as ordinary chunk
  modifications like every other placeable. They weather and break like
  anything else made of wood, because the sheet has the frames for it.

**Art contract.** `assets/sprites/buildings/fence.png`, 1536×1024, magenta
dividers with a printed label row across the top and a label gutter down
the left — the same grid the house lifecycle sheets use
(`VariantSheetGrid.art_bands`). Four orientation columns by three condition
rows, in the sheet's own printed order:

|            | North (Back) | South (Front) | East (Top View) | West (Top View) |
|-----------:|:------------:|:-------------:|:---------------:|:---------------:|
| Pristine (0) | 0,0 | 1,0 | 2,0 | 3,0 |
| Worn (1)     | 0,1 | 1,1 | 2,1 | 3,1 |
| Destroyed (2)| 0,2 | 1,2 | 2,2 | 3,2 |

A rail picks its column from which side of the enclosure it stands on, so a
run along the field's north edge is drawn back-on and a run down its east
edge is drawn as a post-and-rail seen from above.

### The rail stands on the inner edge

Asked for directly, with the west and south sides of a real ring arrowed in
a screenshot: *"move the fences to the inner edge of the enclosure and treat
the rest of the tile as street … the brown squares should still be street
when a fence is put"*.

A rail used to be a whole tile: ground no animal could stand on, painted as
a bare earth square over whatever was already there. That drew a dug brown
moat round every field with the rails floating in the middle of it. A rail
is a **line on one edge** instead — the edge facing the beds it encloses —
and the rest of its own tile is ordinary ground.

- **Which edge.** `VillageFarm.fence_inner_direction` is the inverse of what
  the facing names: a rail closing the field's *north* side stands north of
  the beds, so its rails lie on its own *south* edge. Pinned against
  `fence_facing` itself rather than written out a second time, so a rail can
  never be drawn on one edge and block another.
- **The ground is untouched.** A rail paints no tile of its own. It is in
  `TerrainRenderer.OVERLAY_ONLY_TILE_IDS`, so `paint()` leaves the cell
  showing the terrain it was raised on, and `_neighbor_biomes` lets a
  neighbouring earth cell blend toward it like the real ground it still is —
  without that second half a fenced ring cuts a hard dithered seam right
  round the field. Before this the four rail ids were simply unknown to
  `atlas_coords_for_modification` and fell through its plain-earth fallback,
  which is the whole story of the brown square.
- **Where the art stands.** `IllustratedStructureSprite.footprint_offset`
  puts a rail's own ground line on that edge, and what counts as its ground
  line depends on how the sheet draws the run: a broad-side run (the
  North/South columns) stands on its **posts**, so the bottom of its wood is
  its ground line; a top-view run (East/West) has no posts — the band of
  rail *is* the ground line — so its **centre line** lands on the edge
  instead. Measured off the art with `_art_rect`, not assumed from the cell:
  `fence.png` draws every run centred in its own cell with real margin all
  round, so bottom-anchoring alone leaves a rail's posts about a fifth of a
  tile short of the edge they belong on. A first pass assumed a *north* rail
  already stood on its own south edge and was wrong by exactly that margin.
  `Image.get_used_rect` cannot supply the measurement — a pixel part way
  between the sheet's magenta divider and its black background survives the
  chroma key at full alpha and makes the used rect the whole cell — so
  `_is_art_pixel` keys on that leftover being magenta-*cast* (blue at least
  as strong as green) where real wood and iron never are.
- **What an animal may do.** `VillageFarm.rails_block_step` replaces the old
  "is this tile fenced" question with "does this step cross the rails",
  asked of the PAIR of cells a step joins
  (`EarthChunkManager.fence_blocks_step_global`, and
  `CreatureMarker._fence_blocks_movement` asks it of the cell under the
  animal and the cell its look-ahead lands in). Stepping onto the ring,
  along it, or away from the beds is free; crossing the rails is shut from
  both sides, so an animal already in the crop cannot walk out either. A
  diagonal crosses both of its own edges and is blocked whenever either
  component would be, so nothing slips round a corner that no cardinal step
  can pass.
- **Except a corner post, which shuts only the diagonal.** A corner's beds
  are diagonal, so the diagonal is the only way through it into the crop;
  its cardinal neighbours are the two runs it caps, and stopping a step
  along a run would stop an animal walking the ring — the opposite of what
  was asked. Nothing is opened by the exception: every cardinal way in is
  still shut by the run's own rail. A first pass missed it and turned
  animals back at all four corners, which
  `test_the_ring_of_a_rectangular_field_is_walkable_all_the_way_round`
  caught.

The ring is therefore a real perimeter path — the ground it was raised on,
walkable, with rails along its inner edge — rather than a band of dug earth.
The placeable `wooden_fence` is deliberately NOT part of this: it is a prop
standing on its own tile like a campfire, and bare earth under a prop is
this codebase's existing convention
([npc_farm_production.md](npc_farm_production.md)).

**The corners are a second sheet, not a fifth column.** The ring closes on
the diagonal, so four cells of every ring have only a diagonal bed and no
side of the enclosure to name — `fence_facing` sends them to `north`/
`south` today, which lays a straight rail across the bend. The fix is
`assets/sprites/buildings/fence_corners.png`, the identical contract
(1536×1024, magenta rules, printed labels, `VariantSheetGrid.art_bands`)
with the four columns being the corner of the enclosure rather than its
side:

|            | NW | NE | SW | SE |
|-----------:|:--:|:--:|:--:|:--:|
| Pristine (0) | 0,0 | 1,0 | 2,0 | 3,0 |
| Worn (1)     | 0,1 | 1,1 | 2,1 | 3,1 |
| Destroyed (2)| 0,2 | 1,2 | 2,2 | 3,2 |

A corner cell is one shared post with two HALF runs leaving it, each drawn
as the straight column it must butt against (NW = a North back-on run
exiting right, plus a West top-view run exiting down) and each cut flush at
the cell edge so the rails line up with the neighbouring tile's. Separate
sheet rather than extra columns because the existing four columns are
`fence.png`'s own printed order, pinned by
`test_the_four_rails_are_four_different_pictures` — widening that sheet
would rewrite art already on disk. The generation prompt lives in
[../art/ai_sprite_prompts.md](../art/ai_sprite_prompts.md) §13.

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

- ✅ **Every farmhouse really joins the village's streets.** Reported in
  play with a screenshot of a farmhouse standing in open ground: *"There
  are still Farmhouses not connected by a street"*. Measured before
  anything was touched, and it was not an edge case — **half** of every
  growth plot the village offered fronted paving no street reached (80 of
  160, over 40 seeds × four village sizes). `next_street_plot` walks the
  *skeleton's* streets, every row the spine could ever open; what `layout`
  actually paves is narrower, because a further street is paved only once
  it really got a plot at founding.

  A plot now comes with the paving that joins it — a `road_spur` beside the
  doorstep, the same `{doorstep, road_spur}` shape `industry_plot` and
  `outskirt_plot` already hand back — and a plot nothing can reach is not
  offered at all. The tie-back is the one `layout` itself uses, so a village
  that grows looks like a village that was founded: an L down a lane column
  from the spine, then along the new street's row to the door.

  The first version of the tie-back broke **eight** of the growth ladder's
  own tests, and it took three separate corrections to get them all back --
  each one a different way of being too strict about where a road may run:

  - The lane's column is **searched**, nearest the door first. Fixing it at
    the spine's own start reads plausible and is wrong: `layout` lays its
    gate lane at the start of the run it actually paved, which on a village
    wedged against water is nowhere near where the skeleton drew the spine.
    Recovered two of the eight.
  - The tie-back may **cross** paving the village has already laid --
    another street's row, an earlier plot's doorstep, the square. Without
    that, every junction reads as blocked and no second building on a row
    can reach the first one's lane. This is what keeps every village that
    had frontage before still offering it (measured: 160 of 160).
  - The spur is tested against **water only**, never the caller's wider
    ground rule. The growth ladder builds against `is_buildable_ground_at`,
    which refuses the forest *biome* outright; testing the spur that way
    refused the tie-back on wooded ground. A spur is a road, and a village
    fells the trees it needs to lay one -- the same split `skeleton` already
    draws for the square. Recovered the remaining five.

  The over-time path is covered too: a rung raised by the growth ladder long
  after its plot was offered re-derives the same tie-back from the chunk's
  own seed (`VillageLayout.frontage_spur`), so nothing new is persisted.

- ✅ **A farmhouse fences the beds it works.** Asked for directly, with the
  field circled: *"the farmhouse should build a fence around the bed so no
  animals enter"*. `VillageFarm.fence_cells` is the ring, pure geometry with
  nothing persisted; the renderer raises real rails on every cell of it that
  can take one, leaving the village's own paving open as the gate. Laid only
  once every field is known — two farmsteads near each other share the
  ground between them, so one farm's fence line is the other farm's crop —
  and before any villager or prop is placed, since a prop is grounded
  against what is already built.

  The rails really stop animals: `CreatureMarker._fence_blocks_movement` is
  the same ask-before-you-step check `_terrain_blocks_movement` already is,
  on the one movement choke point every intent funnels through. Villagers
  and the player are untouched.

  Each rail carries its facing in its own tile id
  (`farm_fence_north`/`south`/`east`/`west`), because the tile id is the
  only thing stored about a rail and the sheet's four orientation columns
  have to still draw correctly on the next load.

- ✅ **A rail stands on its tile's inner edge, and the rest of that tile is
  ordinary ground.** Asked for directly, with the west and south sides of a
  real ring arrowed: *"move the fences to the inner edge of the enclosure
  and treat the rest of the tile as street … the brown squares should still
  be street when a fence is put"*. Three halves of one change, each driven
  red first: the rails paint no ground tile at all
  (`TerrainRenderer.OVERLAY_ONLY_TILE_IDS`, which also stops a neighbouring
  earth cell reading the ring as modified and dithering a seam round the
  field); the art moves onto the edge facing the beds
  (`IllustratedStructureSprite.footprint_offset`, derived from
  `VillageFarm.fence_inner_direction`, one branch per projection the sheet
  uses); and movement asks whether a STEP crosses the rails
  (`VillageFarm.rails_block_step` via
  `EarthChunkManager.fence_blocks_step_global`) instead of whether a tile
  carries one, so an animal may stand on the ring and walk along it and only
  the crop is shut. See "The rail stands on the inner edge" above.

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
- 🚧 **The gate is a real hole.** Where the fence ring meets the village's
  paving no rail is raised, because a fence laid across the road would wall
  the village off from its own farm — so an animal that wanders into the
  gate cell is inside the field. That is what a farm gate is, and closing it
  would need a gate mechanic (a rail an animal cannot pass and a person
  can), which nothing models. The field is bounded by the street on one side
  only, so the hole is a few tiles wide at most.
- 🚧 **Rails do not weather or break.** The sheet carries Worn and Destroyed
  rows and only the Pristine row is ever drawn. Nothing damages a fence, so
  nothing would ever read them yet.
- 🚧 **A rail closes exactly one of its own sides.** `fence_cells` closes
  the ring on the diagonal, but a rail's tile id carries one facing, so
  `fence_inner_direction` names one edge — where the old whole-tile rule
  simply made the cell solid and closed every side of it at once. On a
  **rectangular** field the four corner cells each touch exactly one bed,
  diagonally, and `fence_facing`'s vertical answer is always one of that
  diagonal's own two components, so the diagonal into the crop is still
  blocked; the cost is one step *along* the ring at each corner, so the
  perimeter path is walkable except at its four turns. On a **concave**
  outline (a notch or an L — `nearest_cells` returns whatever shape the
  ground allows) one rail cell can face beds on two different sides: it
  closes the first side `fence_facing` names and leaves the second open.
  The bend also still *draws* as a straight run, for the same reason.

  All of it is one missing thing: a rail id carrying a SET of closed edges
  (a corner, a T) with art to match. The contract for `fence_corners.png` is
  above and its prompt is written
  ([../art/ai_sprite_prompts.md](../art/ai_sprite_prompts.md) §13); no corner
  art exists on disk yet, so nothing is wired.
- ⬜ **Nothing yet notices a village that wants a second farmhouse.** The
  village raises one per farming villager and stops. Growing the chain on
  demand is `SettlementBuildDecision`'s to answer, and it reports *missing*
  producers rather than insufficient throughput — the same open question
  [npc_farm_production.md](npc_farm_production.md) already records.
