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

**One search, whoever asks** (2026-09-20). `VillageRenderer
.farm_plot_with_field` is the field-aware plot: the next free frontage
whose ground fits a field and, since the rule below, its fence
(`_field_fits_at`), and the outskirts (`VillageLayout.outskirt_plot`)
when the streets are full. The founding placement asks it for each
farmstead in turn, judged against the farmhouses already standing, and
the growth path (`EarthChunkManager._growth_site_for`) asks the same
function for a farmhouse the assembly votes itself — against the
landmarks and the ground a project is already rising on — so a farmhouse
raised through the village's own ledger is never one the founding rule
would have refused ([village_economy_balance.md](village_economy_balance.md)
mechanism 6).

**Two yards keep a line between them.** Two fields can share one line of
rails, and that line needs a cell to stand on: the search refuses a plot
whose footprint would touch a standing farmhouse's, side by side or at a
corner (`VillageFarm.yards_touch`), so one clear column or row always
lies between two yards. The street frontage lays farmhouses at that pitch
by itself; the outskirts search did not, and once the founding roster
raised five farmsteads it packed (6,24) and (9,24) together on the stub
villages, each field's inner rail line falling on the other's beds — 28
open sides across the villages sampled
(`test_every_farmstead_really_gets_its_enclosure`, and
`test_no_two_farmsteads_stand_yard_to_yard` pins the rule at the siting).

**One rule, two callers** (2026-09-19). "Has real room" and "here is your
field" were two separate copies of the same question — `_field_fits_at` at
siting, `_workable_field_of` at derivation — and they had drifted. The
derivation rejects a cell a **neighbouring farmhouse owns** (ownership is
geometric, so a farmhouse raised later can take ground from one raised
earlier) and a cell **reserved for a landmark** (the village well is not
somewhere to sow); siting checked neither. A farmhouse could therefore be
raised on ground that looked free and then be handed nothing at all — no
beds, and so no fence ring either. Reported live with the village in shot:
*"There's a farmhouse without bed enclosure"*.

Both now go through one `_may_sow(origin, origins, …)` predicate, with
`_reserving` wrapping the occupancy test the same way for both, so the two
cannot answer differently. A candidate origin is judged with **itself in the
running** against the farmhouses already standing, since a farmhouse owns
ground by being nearest to it. `test_siting_and_derivation_never_disagree_
about_an_origin` states the invariant directly rather than testing the two
copies separately.

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
- **A rail's wood sits INSIDE its own tile, flush against the edge facing
  the beds.** The one rule the whole frame follows, and the last of three
  reports to arrive at it: *"at the bottom it still overlaps half a tile"*.
  A south rail's posts standing on its own north edge reads correctly as a
  fence seen from the front, but the body then rises over the bottom row of
  beds and hides half a tile of crop — measured, 34px of a 64px tile. Flush
  from the inside puts the same fence half a tile nearer the viewer and
  covers nothing. `footprint_offset` applies it to every facing, and to both
  axes of a corner, so the frame touches the crop on every side without ever
  covering it.

- **Consecutive rails SHARE a post — they do not merely meet.** Reported
  with a finished enclosure in shot: *"the enclosures render unnecessary
  vertical rails"*.

  Every cell of `fence.png` is a whole panel: a post at **each** end with
  rails between (the sheet's four columns are North/South front views and
  East/West top views, all the same design). An earlier pass — *"also
  scale"* — made a rail's wood span exactly one tile so that consecutive
  rails MEET with no gap. That closed the gaps and left the real problem
  untouched: two whole panels meeting put **two posts** at every junction, a
  few pixels apart, which is what reads as a doubled or unnecessary rail.

  A run of six rails should show seven posts, not twelve. So a rail is
  scaled so the distance between **its own two post centres** is exactly one
  tile, rather than so its whole wood is. Its two posts then land precisely
  on its tile's two edges, the neighbour's near post lands on the same
  point, and the two draw over each other as one — the outer half of each
  end post overhanging into the next tile is the same post that tile draws
  for itself.

  The number is MEASURED from the art, never assumed: `_post_spacing_of`
  classifies each slice of the panel against the **rail** level (the median
  of the slices carrying any content) rather than against the peak, and
  requires a post band to be at least 2% of the run wide. Both guards are
  load-bearing — the trimmed cells carry stray edge slices, including one
  fully opaque column at the far end, that own the peak and otherwise
  swallow the whole run. Measured this way all four facings agree, at source
  resolution and at drawn resolution alike: the posts sit about 0.62–0.65 of
  the run apart, which at a 16px tile had them **12.5–13.0px apart inside a
  16px tile**.

  The consequence, stated plainly: the timber is drawn about a quarter
  thicker than before, because the scale is uniform on both axes (this
  project does not stretch art along one axis to fit). A fence that shares
  its posts is necessarily a little heavier than one that merely abuts.

- **A corner post has a ground POINT, not a ground line.** Reported with all
  three visible corners crossed out (*"the fences still aren't optimal"*).
  A corner knew only which side WALL it capped, so its art was placed as a
  whole tile of vertical rail with nothing saying where along that tile to
  stop — and the run it caps sits on that tile's own EDGE, so the frame
  overshot by a tile at every corner. `fence_facing` names both sides now
  (`corner_nw`/`ne`/`sw`/`se`), its inner direction is the diagonal, and
  `footprint_offset` centres the post on that corner of its own tile in both
  axes: half the post runs back along each run it caps and joins them, and
  nothing hangs past either. It also takes the side wall's own scale rather
  than being scaled by its own length — scaling a post as if it were a run
  is what made it a tile of rail in the first place.

  The two-id corners (`corner_west`/`corner_east`) stay recognised as
  `LEGACY_FENCE_TILE_IDS`: a rail is an ordinary chunk modification, so an
  id that stopped reading as a fence would lose its art *and* stop being
  overlay-only, painting a bare earth square on ground somebody has already
  walked past. Nothing raises one.

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
- **The gate** is where the ring meets the village's own PAVING, and only
  there. No rail is raised on a paved cell: the farmer walks in over the
  street their farmhouse fronts, which is the whole reason a farmhouse takes
  frontage at all. A fence laid across the road would wall the village off
  from its own farm.

  A rail may stand on an unpaved cell of a street ROW, though, unlike a bed.
  Reported with the bed circled, *"it's still not fully enclosing the bed"*:
  a field sits below the house it belongs to, so one whole side of its frame
  lands on the next street row, and holding rails to the beds' own street-row
  rule left that side open — measured on real villages, a three-wide `.....`
  gap with the frame closed on every other side. An unpaved gap is not a
  gate, and a rail along the edge of a road is a fence beside a road. Sowing
  in a street row stays forbidden, which is what that rule was really about:
  a crop in the roadway is not a crop.

  A *short* unpaved gap is not one of those cells at all any more: the
  village closes it as street before any rail is raised
  ([infrastructure.md](infrastructure.md), "A village closes the short holes
  in its own streets"), so the frame meets real paving there and takes it as
  a gate. That ordering is what stops the two rules colliding into a fence
  laid across a road.

- **A bed is cleared before it is sown, and so is its fence line.** Asked
  for directly: *"long grass should be cleared before planting"*, then
  *"the grass should be cleared on the fence tiles as well"* — a frame was
  being raised straight through standing long grass, so the fence line read
  as a row of posts lost in a meadow. A rail is one of
  `EarthChunkManager._is_built_surface`'s own cells now, alongside a
  building piece and a laid road, so raising one clears what stands there
  and pulling one out gives the ground back: a torn-out fence line is
  ordinary ground again, not a permanent scar. Tilling a bed blocks the
  chunk's ground cover on that cell — tall grass, flowers, desert scrub, tundra
  lichen — through the same seam a building's own floor already uses
  ([building.md](building.md)'s *"grass must be cut before and can't grow
  back inside a house"*), so a farmer no longer plants wheat into a standing
  meadow that then grows over it. The clearing happens only when the till
  really takes: a bed refused because a live crop is already on it was never
  worked, and must not scythe the ground anyway. Worked ground stays worked
  — nothing seeds, spreads or falls back into it — which is deliberate and
  is the same permanence a house floor has; a bed nobody ever returns to
  does not regrow its meadow.

- **A wheat bed shows no ground of its own at all.** Reported twice, about
  two different sprites. First `ProceduralSoilSprite`'s MOUND (*"what's the
  round procedural dark blob? Can you remove it and keep just the wheat"*);
  then, once a full tile of `soil.png` was put under every bed to stop wheat
  rising out of bare meadow, *"now there are brown blobs instead of the
  planted wheat ... remove the blobs"* — that sheet's cells carry a soft dark
  vignette, so a tile of it under a bed reads as a blob rather than as
  ground. Both are hidden for wheat and both kept for a root crop, whose
  root really is in that earth. This **reverses** the tilled-tile pass on
  the player's own later instruction, not as a correction of it.

- **(Superseded) A wheat bed shows no soil mound.** Reported with the beds circled:
  *"what's the round procedural dark blob? Can you remove it and keep just
  the wheat"*. `ProceduralSoilSprite`'s mound is a ROOT crop's own ground —
  the root grows inside it, and pulling one leaves the crater its DISTURBED
  state draws — but under a field of bending wheat it is just a dark circle,
  six of them in a 3×2 bed. `FarmPlotMarker` keys it on what the bed was
  SOWN with rather than on `plot.crop_id`, which harvesting clears: a bare
  mound appearing the moment the wheat comes off is the same blob back.
- **A bed stands on real tilled earth.** `assets/sprites/terrain/soil.png`
  is a 3x3 grid of nine hand-drawn tilled-soil tiles; `FarmPlotMarker` draws
  one of them, full-tile, under everything else it draws. This is what
  actually answers the mound complaint above. Removing the mound from a
  wheat bed left the bed standing on the meadow it was tilled out of — six
  rectangles of untouched grass with wheat coming out of them — because
  nothing ever drew the ground a bed is. The mound is unchanged and still
  belongs to root crops (see the bullet above); the soil under it is a
  separate layer and is always on.

  Which of the nine a bed gets is hashed from its own global tile, so
  neighbouring beds differ but a given bed is the same every time it is
  drawn, matching every other seeded art pick in this codebase.

  **This sheet's gutters are BLACK, not magenta**, unlike every other
  illustrated sheet here. That is not a detail: `IllustratedTerrainSprite`
  punches magenta to alpha before slicing, and `SpriteSheetSlicer.
  detect_frames` then finds cell dividers by their transparency. Fed a
  black-gutter sheet that pipeline finds no dividers at all and returns the
  whole 1254x1254 image as ONE frame — measured, not predicted.

  Rather than teach the chroma-key pass a second background colour, a sheet
  may now declare its `column_bands` outright, and soil does: both axes were
  measured from the file, so there is nothing left for content detection to
  find. That is the better fit regardless of the gutter colour, because a
  full-bleed GROUND tile is the one case where content detection is actively
  wrong — cropping to content and rescaling is precisely what must not
  happen to a tile that has to abut its neighbours. Sheets without
  `column_bands` are untouched and still find their columns by content.

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

### A fence with nothing left to enclose comes down

Reported live with the village in shot: *"There's a bed enclosure without a
Farmhouse"*, and again after the first sweep landed: *"there are still fenced
enclosures without a corresponding Farmhouse or Fisher"*.

A field is only ever fenced around a farmhouse that really stands. But the
rails are real persisted tiles, so a farmhouse that goes **afterwards** —
razed, or reclaimed for standing in water — leaves its whole frame behind for
ever.

**A rail survives only if it is on a real frame this visit**: some
farmhouse's own ring around its own beds, or some pond's own ring around its
own water. Not "near a building that survived".

The first pass used distance instead, on the worry that frame membership
would not be stable across visits — a farmhouse's field is re-derived every
time against what is standing, the last visit's rails included, so asking
"is this rail in today's frame" unstably would have each visit pull up the
previous one's fence.

It is stable, and that is measured rather than assumed: across four real
villages and the 113 rails between them, every rail a founding lays sits on
its own farmhouse's ring or its own pond's ring on the next visit too, and
not one of them needed the slack the distance rule was giving away
(`test_the_sweep_takes_no_rail_a_real_founding_laid`). What that slack *did*
keep standing is a frame left by a razed farmhouse that happened to lie near
a surviving one — which is exactly the second report.

A pond's ring is read off the water that is really there rather than off a
plan, so a pond that was only partly dug still keeps the frame around what it
got.

The sweep runs on every visit, not on the removal: idempotent, self-healing,
and able to clean up a save whose farmhouse went before it existed — the same
shape `_lay_plaza_if_missing` and `_place_industry_if_missing` already have.

### A farmstead clears its own ground

Reported in play with the enclosure in shot: *"the Farmhouse should clear
trees in its bed enclosure"*.

A fence around six beds with an oak standing in the middle of them is not a
field. Every other real placement in this game already fells what is in its
way — `place_building` and `build_at_global` both call
`_clear_vegetation_on_cells` on the cells they write, which is
[building.md](building.md)'s own *"the NPCs / Player must first fell all
trees to make space for the building"*. The beds were the one thing that
never did, because they are not written tiles: they are ground handed to a
farmer, who tills them one at a time and can only clear the ground COVER
(`till_and_plant_farm_plot_at_global` blocks grass and flowers, and has no
axe).

So the farmstead clears its beds the way it clears its footprint: at
founding, once, on the cells it has just claimed.

- **What is cleared:** exactly the cells the fence encloses — the field
  rectangle the villager really works. Not the fence ring (those are built
  tiles, and building one already clears its own cell), and not a margin
  beyond it: a village fells the timber it needs, not the wood it is
  standing near.
- **Trees, boulders and ore veins alike**, because that is what
  `_clear_vegetation_on_cells` means by vegetation and because a boulder in
  a bed is the same problem as an oak in one. The felled timber is not
  credited anywhere: a village clearing its own founding site is scene
  setting, not a harvest, exactly as it already is for a house's footprint.
- **Through one duck-typed hook**, `clear_vegetation_at_global(cells)`, the
  same fail-open shape every other world call the renderer makes already
  uses — a world that cannot answer simply has nothing to clear.
- **On every visit, not only the first.** The sweep is idempotent (a cleared
  cell has nothing left to clear), which is what lets it heal a village
  founded before this existed, the same self-healing shape
  `_clear_rails_with_nothing_to_enclose` and `_lay_plaza_if_missing`
  already have.

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

- **The worker may cross into their own beds.** Rails stop a villager the
  way they stop an animal (`NpcMarker._blocked_step`) — but a field's rails
  stand on its *inner* edge, so the one villager they shut out is the
  farmer whose beds they enclose. Reported live: *"The farmer doesn't farm
  anymore"*. Measured on a real village with
  `tools/probe_village_farming.gd`: of three villagers with a field, one
  worked 58 beds in ten minutes and the other two worked **none**, frozen
  in `APPROACHING` for 2650 of 2750 on-field ticks — the herbalist nine
  pixels from its own soil, refused the last step south into it.

  "The gate" above exists for exactly this, but *reaching* it needs
  pathfinding a `Sprite2D` walking one `move_toward` per frame does not
  have. The commit that gave rails their hitbox said so itself: *"boxed in
  on both, they stay put"*. So a villager may cross into a cell of their
  own `field_cells`, and nothing else moves — every other rail still stops
  them, **a neighbour's field included**, and no villager without a field
  is exempt from any rail. The farmer is who the enclosure is *for*; it is
  there to keep animals out, not the worker.

  Still open, and measured rather than assumed: a farmer whose own field
  lies beyond **another** farmstead's ring still cannot reach it. In the
  probe's village the third farmer stands west of its neighbour's fenced
  beds with its own field east of them, and walks into that ring's rail
  forever. Its own gate would serve if it went to its farmhouse frontage
  first; that is the routing this rule deliberately does not attempt.
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
- **And a run is scaled by its RUN.** Asked for in one word once the rails
  landed on their edges: *"also scale"*. Every whole building scales its
  cell WIDTH to the tile, which is the footprint anchor. A rail cannot: the
  sheet draws each run centred in its own cell with real margin at both
  ends, so a cell scaled by its width leaves that margin as a gap between
  one rail and the next — measured, 52 of 64 across for a broad-side run and
  39 of 64 down for a top-view one, which reads as a row of separate pieces
  rather than a fence line. `_footprint_scale` scales a rail so its own wood
  spans exactly one tile along the direction its run travels (east-west for
  a rail whose beds lie north or south, north-south for one whose beds lie
  east or west), so consecutive rails meet and the frame closes. Its band is
  then wider than the tile it stands on, which is why the footprint-width
  contract now speaks for whole buildings only, and why the placement
  carries where the band's left edge falls instead of assuming it away.
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

### Grown, stored, carried: where a harvest actually goes

Asked for directly: *"make sure wheat grows and is harvested which increases
farmhouse stock which gets transported to city stock"*. The middle of that
chain did not exist. A villager's harvest went straight into the village
market, so the farmhouse they grew it for never held a grain of it and
nothing was ever carried anywhere.

1. **Grown** in the beds — `FarmPlot` on a real world tick, unchanged.
2. **Cut** by the villager on their circuit (`NpcMarker._work_field_cell`).
3. **Stored at the farmhouse** — `_store_harvest` deposits into that
   building's own `StructureStock` (`EarthChunkManager.deposit_to_structure_at`),
   the same per-building stock the placeable Farm and the Sägewerk already
   use. The villager knows *which* farmhouse because `VillageRenderer` hands
   `farmhouse_cell` out with `field_cells` — it is the only thing that knows
   whose is whose.
4. **Carried to the village** at the end of the work block
   (`haul_farmhouse_stock_to_village`, from `_step_farm`'s off-the-clock
   branch). The whole crop moves, and reaches the market through the same
   `record_real_harvest` a farmer without a farmhouse uses — so it is
   stocked and paid **once**, when it arrives rather than when it is cut.

Two edges, both deliberate:

- **A farmer with no farmhouse** — a village that has not raised one, or one
  there was no room for — sells where they stand, exactly as before. A
  harvest with nowhere to go would otherwise vanish, which is worse than the
  missing link this closes.
- **The end of the work block is the moment**, not "when there is nothing
  left to do". A field with beds in it always has *something* worth a visit
  (`next_action`'s thirstiest-bed fallback), so an idle moment never
  reliably arrives; the end of the block does, every day.

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

### A bed has to survive the night (2026-09-19)

The paragraph that used to stand here said crops wither overnight, the
farmer re-tills in the morning, and against 50–66 harvests a day that is a
rounding error. **It was wrong, and measuring said so.** Reported three
times over, most recently with the field in shot: *"Planted crops still
vanish and don't grow and no harvest happens"*.

`tools/probe_village_farming.gd` against a real village, ten simulated days:
**thirteen of eighteen beds ended withered**, one farmhouse took in fifteen
wheat and the other two took in **none at all**. The farmer was working 2750
of 6000 ticks throughout — not idle, simply unable to be there.

The arithmetic is not close, and it is about the OTHER day clock. A villager
works to `NpcMarker.SECONDS_PER_SIMULATED_DAY` — sixty seconds, four blocks
— not to the ecology day above, and nobody farms while they sleep. So a
field goes untended for up to three blocks, **forty-five seconds**, on every
day of its life, against a whole drought tolerance of ten to thirty. Every
bed died every night; the morning re-till was not a rounding error, it was
the entire day's work.

So a bed's tolerance has a **floor of one night**
(`FarmPlot.MIN_WATER_GRACE_SECONDS`), taken from that day and those blocks
and pinned against both by test rather than restated by import — a pure
gameplay rule does not reach into the chunk manager. The crop-scaled window
is kept beside it and the longer of the two wins; with today's 20–60 s growth
times the night always does, and a test says so out loud instead of leaving
it implied. `VillageFarm.action_for` reads the bed's real window too, so the
farmer waters against the deadline that actually exists.

This is not a forgiving number chosen to make a field work. A field is not a
pot on a windowsill, and a crop that dies because nobody came for one evening
is a crop nobody in this world could farm, the player included.

Measured again on the same village afterwards: **zero withered beds**, and
the three farmhouses taking in **51, 70 and 73** wheat where they took 15, 0
and 0. `FIELD_YIELD_PER_WORK_BLOCK` was re-measured at **278** from 225 by
the same test that pinned the old one — the roster had been sized against a
field that lost beds every night.

That number is the stub world's, a villager standing at a field with no
walk to it, and it is no longer what the roster is sized by. A real field
on a real chunk yields about **five units a lived day**
(`FIELD_YIELD_PER_LIVED_DAY`, 299 units in twenty lived days over three
fields), 3.7× less, because the walk between cottage and field eats most
of a 27.5-second work window; `SettlementFoodDemand` reads the real
figure ([village_economy_balance.md](village_economy_balance.md)
mechanism 6).

### Every field sows wheat, for now (2026-09-19) — superseded

Asked directly, with a field of unrecognisable purple plants in shot: *"i
don't even know what the purple crops are it plants.. atm it should plant
only wheat which grows and gets harvested properly"*. The purple was the
herbalist's own herb, dying overnight exactly as the wheat beside it was.

`CROP_BY_OCCUPATION` was narrowed to `{"farmer": "wheat", "herbalist":
"wheat"}` — deliberately a narrowing of the CROP, not of who farms.

**That narrowing is withdrawn by the section below.** It was the right
answer to "the crop dies before it ripens" and the wrong one to keep once
the night bug was fixed: a village that sows nothing but wheat has nothing
edible, because wheat is not food (see below), and the herbalist's own herb
— which is — never went back in.

### What a field sows follows the village's need (2026-09-20)

Reported with the village's own panels open: *"they have 0 Herbs even though
there are 3 farm houses... so deciding what to plant must be based on
demand"*, alongside *"The warehouse shows 205 Wheat but the Villagers show
50% food"*.

Both are the same defect seen from two sides, and the second is the one that
explains it. **Wheat is `kind = "material"`, not `kind = "food"`** —
[milling_and_baking.md](milling_and_baking.md)'s own first pillar, "grain is
not food until it is milled and baked". Every filter that decides whether a
village is fed (`SettlementFood`, `VillageMarket`, `VillageEstates`'
`kind:food` token) therefore counts a full granary of wheat as **zero
food**. A village sowing nothing but wheat, with no mill standing, starves
beside it. That is not a distribution failure; it is a cropping one.

Two rules replace the occupation table:

1. **The crop is chosen at SOWING, not at hiring.** `NpcMarker._field_crop`
   was set once in `setup_economy` from the villager's occupation and never
   revisited, so a village's entire cropping plan was fixed the moment its
   villagers were built — before a single basket had ever been drawn.
2. **It is chosen from the same satisfaction reading the needs panel
   shows.** `VillageAssembly`'s state already carries `satisfaction` per
   good, straight off the real `EstateConsumption.draw`
   ([village_estates.md](village_estates.md) mechanism 8). A field sows the
   sowable crop whose good is **least satisfied**. The panel and the plough
   read one number, so what a village says it lacks and what it plants
   cannot disagree.

**What a crop answers**, and why each is in the list rather than a crop
being anything with art:

| Crop | Answers | Why |
|------|---------|-----|
| `herb` | `herb`, `kind:food` | the kossaet station good, and edible itself |
| `carrot` | `kind:food` | real `kind = "food"`, real crop art |
| `potato` | `kind:food` | the same |
| `wheat` | `bread` | **only through a mill and a bakery** |

Wheat's row is the rule that matters. It is offered **only where the
village can really bake it** — a mill and a bakery standing. Everywhere
else it answers nothing at all, so a field sows something the village can
eat on the day it is harvested rather than a material nobody can mill.

A crop is scored by the **worst-supplied** good it answers, not the mean: a
crop that would relieve a good sitting at 0.0 is worth more than one
relieving a good at 0.9, which is the same "a household with all the bread
in the world and no fuel is cold" minimum rule `EstateConsumption` already
applies one level up.

**Occupation survives as a tie-break, not as the rule.** Among crops the
village needs equally, an herbalist reaches for herbs. `VillageFarm.
crop_for` keeps its second job untouched — three callers use it as the
predicate *"does this occupation work a field at all"* (`VillageRenderer`
twice, `NpcMarker.setup_economy` once), and that question is not the same as
*"what goes in the ground today"*.

**Fail-open, like every other world hook here.** A marker with no world to
ask, or a village with no reading yet, keeps the occupation's own
traditional crop — an isolated test sows exactly what it always did.

### Persistence

Nothing new is stored. The farmhouse is an ordinary persisted building; the
field is re-derived from its origin every time; the plots live in
`EarthChunkManager._farm_plots` exactly as a player's own do, with the same
already-accepted "plot state does not survive a chunk unload" gap
[npc_farm_production.md](npc_farm_production.md) records for the placeable
Farm. A reloaded village re-derives the same field and starts tilling it
again.

### Two fields, one line of rails (2026-09-20)

Reported with both enclosures in shot: *"It should be possible to build two
rails on a single tile so both enclosures are fenced properly. also the
corner post can be removed"*.

A rail is an ordinary chunk modification and **a tile holds one id**, so
where two farmsteads sit side by side their rings meet on one column of
cells and only the first field's rail can stand there. Measured
(`tools/probe_neighbouring_fences.gd`) on a real village with four
farmhouses, printing what each field *wants* on every contested cell beside
what really stands:

```
  (23, 20)  wanted as ["0:corner_ne", "1:corner_nw"] -- stands: road
  (23, 21)  wanted as ["0:east", "1:west"]           -- stands: road
  (23, 22)  wanted as ["0:east", "1:west"]           -- stands: farm_fence_east
  (23, 23)  wanted as ["0:corner_se", "1:corner_sw"] -- stands: farm_fence_east
```

Field 0's east rail won every contested cell; field 1 had no west rail at
all, so its enclosure was open along the whole shared side. (The two `road`
cells are correct — that paving is the gate the farmer walks in through.)

**A shared line is one tile carrying both fields' rails.**
`VillageFarm.SHARED_FENCE_TILE_IDS` names the two opposite pairs, and that
is the whole set: two fields meeting share a line, and a line has a field
on each side of it. Rails meeting at right angles belong to one ring's
corner, not to two rings.

The id carries the facings for the same reason every rail id does — nothing
about a rail is persisted — and a shared id is **defined as the two
ordinary rails standing there** (`fence_pieces_of`). That is what makes it
cost nothing downstream: each piece keeps the art and the inner edge it
already had, `_spawn_structure_art_for` raises one sprite per piece, and
`rails_block_step` refuses the crop on both sides because there is one on
each. Only the *opposite* rail shares a line, and never the same rail
twice, so a reload still re-derives the ring and builds nothing — which
`_fence_the_fields`' own idempotence rule requires.

### A corner draws no post of its own (2026-09-20)

Asked for in the same breath: *"also the corner post can be removed"*.

Every cell of `fence.png` is a **whole panel** — a post at each end with
rails between — and `tools/probe_fence_posts.gd` measured those two posts
12.5px apart inside a 16px tile. So the two runs meeting at a corner
already carry a post each, and the corner cell drew a **third** one beside
them: the same doubled-post look that probe was written about, at every
turn of every ring.

**The corner cell is still a rail.** It is what refuses the diagonal into
the crop (see "The rail's own hitbox" below, and
`_rail_stops_step`'s own corner branch), and an id that stopped reading as
a fence would lose its collider *and* stop being overlay-only, painting a
bare earth square on ground somebody has already walked past. What changed
is only that it has no entry in the art registry, so nothing is spawned for
it.

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

### The rail's own hitbox

Every walker but one already respected the rails: `rails_block_step` is an
ask-before-you-step query, and a marker is a `Sprite2D` that asks it. The
**player** is a real `CharacterBody2D`, which cannot ask anything -- it needs
something in the world to hit, and a rail is not a `BuildingPiece`, so
nothing was ever spawned for it. The player walked through every fence in the
game (reported, and carried open for several rounds).

The fix is an **edge** body, never a tile-sized one, because a rail stands on
the inner edge of its cell and the rest of that cell is street.
`fence_collider_normal` and `fence_collider_rect` own it, reading the same
inner edge `rails_block_step` shuts -- so what stops the player and what
stops everybody else cannot drift apart about *which* crossing a rail
refuses.

A **corner post gets none.** Its inner direction is diagonal, so an edge
collider would lie along one of the two runs it caps, and walling either
would shut the walkable ring -- the same thing `_rail_stops_step` already
refuses for the same reason. The diagonal it blocks is closed by the two
neighbouring runs' colliders meeting at the shared corner.

`FENCE_COLLIDER_THICKNESS_PX` is derived and test-bounded on both sides: at
least one 60Hz tick of the fastest the player can be (a maximum-fitness
mount, 3.0 px), and at most a quarter tile so it stays a line.

### A farmstead is sited where its FENCE fits, not only its beds (2026-09-20)

Reported with the hamlet in shot: *"The two farmhouses collide and only one
gets an enclosure"*. Measured on real villages
(`tools/probe_farmstead_collisions.gd` — 465 chunks, 10 villages with a
farmhouse, 7 of them with two or more):

```
VILLAGE (679, 141)
  farmhouse (13,19)  rails standing  9/14
  farmhouse (20,19)  rails standing  6/14
    gaps: (23,22) mod='road'  (23,23) mod='road'  (23,24) mod='road'
```

Two farmsteads can fail to be fenced for two different reasons, and only
one of them is answered by the shared line above.

**A contested cell is not the problem any more.** Two fields meeting share
one line of rails (`SHARED_FENCE_TILE_IDS`, "Two fields share one line of
rails"), so a cell both want carries both. That is a better village than
two farmsteads shoved to opposite outskirts, and the first cut of the rule
below got it wrong by refusing a neighbour's rail line outright.

**A road down the fence line still is.** A rail and a road are not two
halves of one tile, so a spur running along the column a farmstead's east
rail needs simply costs it that side — measured at three of fourteen rails
on the village above, with the shared line already in place.

The cause is that siting asked only whether the **beds** fit. A fence is
not decoration round a field; it is what makes the beds a field, so the
ground it needs has to be asked for at the same moment. That is the same
lesson `_may_sow` already carries one function up — *a rule that decides
where to build has to be the rule that decides what gets built* — applied
to the half of the farmstead it had not yet reached.

`VillageFarm.fence_has_room` is the pure half: every cell of the ring
allowed by a caller-supplied `may_rail`, and empty beds answer **false**
rather than vacuously true. `VillageRenderer._may_rail` is that predicate:
a street row is fine (the gate), a cell already carrying the neighbour's
rail is fine (the shared line will join it), and anything else must be
clear of water, buildings and paving.

Measured after, on freshly founded villages — the probe scrubs each chunk
first, because chunks persist on unload and an A/B against a reload of
one's own earlier founding comes back byte-identical and means nothing:

| | shared line only | + this rule |
| --- | --- | --- |
| worst enclosure measured | 6 of 14 | 8 of 12 |
| farmhouses with no field | 0 | 0 |
| villages with a farmhouse (of which 2+) | 10 (7) | 10 (7) |

No village lost a farm to the stricter rule; a farmstead whose fence line
is a road simply moves off the crowded street row to ground where a whole
enclosure fits.

> Exposed one latent bug on the way: `_sited_plot` — the scan behind
> `outskirt_plot` and `industry_plot` — never returned a `facing`, and
> `_place_farms_if_missing` reads `plot["facing"]` on any world without
> `place_building_over_roads`. It had simply never been reached before,
> because the street-frontage search almost always answered first. Pinned
> by `test_every_plot_says_which_way_its_building_faces`.

#### A horizontal rail stands at the foot of its wood

Reported once the bodies were in: *"The horizontal fences should have the
hitbox at the bottom of the rail ... so it should use fence height instead
of thickness"*.

Naming the edge is not the same as knowing where on that edge the fence
actually *stands*. The two horizontal facings anchor their art to **opposite
ends** of their cell (`IllustratedStructureSprite.footprint_offset`:
`inner.y > 0` bottom-anchors, `inner.y < 0` top-anchors), so pinning both
colliders to the edge their normal names is right for one and wrong for the
other:

| rail | inner | wood, tile-local | collider was | correct |
| --- | --- | --- | --- | --- |
| north | `(0, 1)` | `y = 5.5 .. 16.0` | `12.0 .. 16.0` | yes |
| south | `(0, -1)` | `y = 0.0 .. 10.9` | `0.0 .. 4.0` | no |

A south rail's wood hangs *down* from the tile's top edge, so a collider on
that edge stopped the player at the rail's **head**, seven pixels short of
the line they could see. A fence stops things where its posts meet the
ground and nowhere else, so `fence_collider_rect` takes the height of the
wood as drawn and puts the strip at its **foot** — `tile_size` when the art
is bottom-anchored, the wood's own height when it is top-anchored, clamped
into the cell so art that measures oddly can never stand a body in the
neighbour's tile. The strip stays `FENCE_COLLIDER_THICKNESS_PX` deep; it is
*where* it sits that the height decides, not how thick it is.

A **vertical** rail is anchored left or right, has no foot on the `y` axis
at all, and is untouched.

Finding that foot means redoing the band arithmetic `footprint_offset`
already does, and a second copy of it in `EarthChunkManager` is a second
copy to get wrong — losing exactly the detail that the two facings land at
opposite ends. So `IllustratedStructureSprite.placed_art_rect` answers
"where does this subject's ink actually land inside its tile", both
`footprint_offset` and the collider read it, and `EarthChunkManager` only
forwards the number.

This is the one place the player and the markers stop at different *lines*:
`rails_block_step` is a cell-grid rule and refuses the crossing at the cell
boundary, while the body refuses it a few pixels later, inside the cell.
They still refuse the same crossings — and the rest of a rail's tile being
ordinary ground is the rule, not an accident, so standing in it is allowed.

## Status

- ✅ **A field sows what the village is short of** (2026-09-20) —
  `VillageCropChoice`, reading `VillageAssembly`'s own per-good
  satisfaction so the needs panel and the plough share one number. Wheat is
  offered only where a mill AND a bakery stand, because wheat is
  `kind = "material"` and a granary of it counts as zero food — which is
  what *"the warehouse shows 205 Wheat but the Villagers show 50% food"*
  really was. The crop is chosen at sowing rather than frozen in
  `setup_economy`, and the haul reads the shelf rather than one assumed id,
  since a farmhouse may now hold a crop its villager was never built with.
  `CROP_BY_OCCUPATION` survives as the TRADITIONAL crop — a tie-break and
  the fallback — with the herbalist's herb restored. 15/15 + 4/4 wiring.
- ✅ **A farmhouse is only raised where its field will really be derived**
  (2026-09-19) — see "One rule, two callers" above. Siting and derivation
  were two copies of the same question that had drifted apart, so a
  farmhouse could be raised on ground the derivation then refused it: no
  beds, no fence, reported as *"a farmhouse without bed enclosure"*. They
  are one predicate now. **Honestly: not reproduced before fixing.** 29
  farmhouses across 14 villages of flat stub ground all took a full six-cell
  field, with landmarks reserved and with the two rules agreeing every time
  (`tools/probe_farmhouse_fields.gd`), so the gaps are real and proven by
  construction rather than caught in the act on real terrain.
- ✅ **A farmer sows the field before sowing any of it twice** (2026-09-19)
  — reported as *"the NPC only sows 4 / 6 tiles"*, and measured: every field
  in the sample held six cells with the LAST one "never tilled" after a full
  work block, for both farmers in the village. `next_action` returned the
  first bed wanting the top-priority job, and unbroken ground asks to be
  planted exactly like a bed that has already been harvested — so once the
  earlier beds began cycling, one of them was always an earlier "plant" and
  the end of the field was never broken. Unbroken ground now wins among beds
  asking for the same thing; a ripe crop and a dying bed still come first.
  Re-measured after the fix: every field 6/6.
- ✅ **A fence with nothing left to enclose comes down.**
  `VillageRenderer._clear_rails_with_nothing_to_enclose` now asks whether a
  rail is on a real frame this visit — a farmhouse's ring around its own
  beds, or a pond's ring around its own water — rather than how near it
  stands to a surviving building. Measured: 113 rails across four real
  villages, none lost, and a rail planted on a standing farmhouse's own
  doorstep with no frame under it comes down (it did not before).
- ✅ **A farmstead clears its own ground.**
  `EarthChunkManager.clear_vegetation_at_global(cells)` is the public door
  onto the same `_clear_vegetation_on_cells` sweep `place_building` and
  `build_at_global` already run over the cells they write, and
  `VillageRenderer._clear_the_beds` calls it on exactly the cells a
  farmstead's fence encloses — no margin, and the rails clear their own
  cells as they are laid. Idempotent, so it runs on every visit and heals a
  village founded before it existed.
  `test_earth_chunk_manager_clear_vegetation.gd` 7/7 (new),
  `test_village_renderer.gd` 124/124.
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
- ✅ **A growth farmhouse is sited where its field fits** (2026-09-20).
  `VillageRenderer.farm_plot_with_field` is the one search for a farmstead's
  plot; `_place_farms_if_missing` and `EarthChunkManager._growth_site_for`
  both ask it (`test_earth_chunk_manager_farm_growth_site.gd`: the site
  fits a field, it is the founding search's own answer, and the next farm
  keeps off the first one's ground).
- ✅ **Two yards keep a rail line between them** (2026-09-20).
  `VillageFarm.yards_touch` (pure, `test_village_farm.gd`, 5 pins) and the
  shared search refusing a touching plot; every farmstead on the stub
  villages fully enclosed again (`test_village_renderer.gd`).
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

- ✅ **A rail is solid to the player, at the foot of its wood** (2026-09-20)
  — `VillageFarm.fence_collider_normal`/`fence_collider_rect` and
  `EarthChunkManager._sync_piece_collision`/`_spawn_rail_collision`. Two
  reports, one after the other: *"fix the fence collision"* (markers
  respected the rails and the `CharacterBody2D` player had nothing to hit,
  because a rail is not a `BuildingPiece`), then *"The horizontal fences
  should have the hitbox at the bottom of the rail ... so it should use
  fence height instead of thickness"* (a south rail's art hangs down from
  its top edge, so a collider on that edge stopped the player at the rail's
  head). Corner posts get no body at all. See "The rail's own hitbox" above.

- ✅ **A herb bed is visible.** Reported in play with the field in shot:
  *"it plows the soil but then the soil mound sprites don't appear and
  nothing gets planted, nothing grows and nothing gets harvested"* — and
  measured before anything was touched (`tools/probe_village_farming.gd`,
  against a real village east of Berlin): every part of it WAS happening.
  The field's villager was a **herbalist**, every bed really was sown
  (`sown=herb`), the crop really grew (`grown=29.5/57.2`), beds really
  withered, and 8 real herbs really reached the village market over one
  stretch of work. None of it was ever drawn.

  `IllustratedCropSprite` has sheets for carrot and potato only, so
  `leaf_texture("herb", ...)` returned null — and `FarmPlotMarker` put a
  **visible** `Sprite2D` carrying **no texture** over a full tile of bare
  tilled earth. A visible sprite with a null texture draws nothing while
  claiming to draw something, which from the player's side is
  indistinguishable from a field where the farming loop is broken.

  Closed by `ProceduralHerbSprite`: an upright culinary herb (stem, leaf
  pairs climbing it, side shoots as it matures, a flowering tip when ripe)
  in `ProceduralLandmarkSprite`'s own `HERB_COLOR`, so a herbalist's bed and
  a herbalist's `garden` workspot prop read as the same plant rather than
  two. Hand-drawn in the same offline-art style as `ProceduralSoilSprite`,
  behind `IllustratedCropSprite.has_crop()`, so real art can replace it
  later with no marker change.

  **Root-pinned, not centred.** A procedural herb fills its own canvas from
  the bottom row up, so centring it would bury the lower half of every plant
  in the soil. The illustrated crops keep their centring, because their
  sheets are authored with the plant high in the canvas above a baseline —
  one rule for both would be wrong for one of them. Same offset the wheat
  blades already use for the same reason.

  The cross-pin matters more than the sprite:
  `test_every_crop_a_village_farm_sows_really_draws_something` is driven off
  `VillageFarm.CROP_BY_OCCUPATION` itself, so a NEW crop a village can sow
  but a bed cannot draw fails there rather than in somebody's screenshot.
  A crop with neither illustrated nor procedural art now leaves the sprite
  **hidden** rather than visible-and-textureless.

- ✅ **The store is carried in ONCE, at the end of the block.** Reported live
  with the farmhouse panel open: *"der Farmer scheint was zu ernten und
  läuft dann zum Farmhouse aber es wird kein Weizen eingelagert"*. The haul
  ran on **every** off-clock frame, so anything that reached the store
  outside the work block was drained again within a frame and a store could
  never hold a thing overnight. `_carried_in_since_work` is that edge: one
  flag for the field and the pond alike, because a villager works one or the
  other and both carry their take in at the same moment.

  **Say plainly what this does and does not change.** Measured before the
  fix (`tools/probe_village_farming.gd`), the chain was already working —
  ten separate deposits, a peak of six held in the farmhouse — and the store
  fills during the work block either way. What changed is that a store can
  now hold what reaches it *after* the block ends, instead of being a chute.
  A farmhouse whose villager was never paired with it (a leftover from an
  earlier roster, `wanted_by=0`) still reads empty, and always will: nobody
  deposits into it.

Honest gaps, each real:

- 🚧 **`herb` has no INVENTORY art** and falls back to the procedural item
  sprite. The plant in the bed is drawn now (see "A herb bed is visible"
  below); the item in a bag still is not.
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
