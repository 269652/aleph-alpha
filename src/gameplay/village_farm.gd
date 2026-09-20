extends RefCounted

## The pure rule set behind a village's own farms (see docs/concept/
## village_farms.md): which ground a farmhouse owns, what its villager
## grows there, and what to do next on it. NpcMarker owns the world effect
## -- walking out, tilling, watering, harvesting -- exactly the split
## HuntableQuarry already draws for the hunter and the fisher.
##
## Reported in play: "every tile of wheat planted adjacent to a farm house
## may be tied to a farm house (so you can build multiple farms)". That
## sentence is owner_of below, and it is deliberately GEOMETRY rather than
## a stored record: nothing is persisted, so two farmhouses in one village
## each work their own ground, the answer is the same on every reload, and
## no tile can ever answer to two owners.
##
## Deliberately NOT the placeable Farm of docs/concept/
## npc_farm_production.md, which is the PLAYER's own farm tile with a
## narrow-purpose FarmerMarker tending three plots at fixed offsets. The
## two share FarmPlot/FarmPlotMarker/FarmerBehavior and the action priority
## below; nothing else.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const FarmPlot = preload("res://src/gameplay/farm_plot.gd")

## The village's farm building -- the catalog's own, never a second id.
const FARM_BUILDING_ID := "farmhouse"

## The rail a farmhouse fences its beds with, one tile id per facing.
##
## Four ids rather than one because the facing has to SURVIVE: nothing about
## a village farm is persisted, and a rail is an ordinary chunk modification
## whose id is the only thing stored about it. Carrying the facing in the id
## is what lets the sheet's own four orientation columns still be drawn on
## the next load, with no record of which field the rail once belonged to --
## the same shape BuildingPiece's wall_wood/floor_stone ids already use.
##
## Deliberately NOT the placeable `wooden_fence`: that one GATES a player
## Farm's Farmer (EarthChunkManager.FARM_FENCE_GATE_RADIUS_TILES), and a
## village farm's rails standing nearby must not staff one by accident.
const FENCE_TILE_IDS := {
	"north": "farm_fence_north",
	"south": "farm_fence_south",
	"east": "farm_fence_east",
	"west": "farm_fence_west",
	"corner_nw": "farm_fence_corner_nw",
	"corner_ne": "farm_fence_corner_ne",
	"corner_sw": "farm_fence_corner_sw",
	"corner_se": "farm_fence_corner_se",
}

## Rails a village RAISED under an older scheme and may still have standing.
## Nothing produces one any more -- fence_facing names a corner by both the
## sides it caps now, because one of them is which run's line the post has
## to sit on (see FENCE_INNER_DIRECTIONS). They stay recognised because a
## rail is an ordinary chunk modification: an id that stopped reading as a
## fence would lose its art AND stop being overlay-only, painting a bare
## earth square on ground somebody has already walked past.
const LEGACY_FENCE_TILE_IDS: Array[String] = [
	"farm_fence_corner_west", "farm_fence_corner_east",
]

## The shapes a farmhouse's field may take -- asked for directly, with the
## broken ring circled in a screenshot: "The fence should enclose a 2x3 or
## 3x2 area". Six beds either way, which is also exactly where the measured
## yield table peaks (see MAX_WORKED_CELLS).
const FIELD_SHAPES: Array[Vector2i] = [Vector2i(3, 2), Vector2i(2, 3)]

## What each farming occupation grows. Same table shape NpcMarker.
## QUARRY_KIND_BY_OCCUPATION already uses for hunter/fisher; an occupation
## absent from it has no field at all, which is the honest answer for every
## villager who is not a farmer or a herbalist.
## The TRADITIONAL crop of each farming occupation -- what they reach for,
## not what necessarily goes in the ground.
##
## What is actually sown is the village's own worst-supplied need
## (VillageCropChoice, docs/concept/village_farms.md "What a field sows
## follows the village's need"); this table breaks a tie between crops the
## village needs equally, and is the whole answer where there is no reading
## to go on.
##
## It briefly read {"farmer": "wheat", "herbalist": "wheat"}, asked for
## directly with a field of unrecognisable purple plants in shot: *"i don't
## even know what the purple crops are it plants.. atm it should plant only
## wheat"*. The purple was the herbalist's own herb dying overnight exactly
## as the wheat beside it was (FarmPlot.MIN_WATER_GRACE_SECONDS, fixed in
## the same pass). That narrowing is withdrawn -- reported next was *"they
## have 0 Herbs even though there are 3 farm houses"*, and this one entry is
## what had removed them.
##
## An occupation absent from it has no field at all, which is the honest
## answer for every villager who is not a farmer or a herbalist.
const CROP_BY_OCCUPATION := {"farmer": "wheat", "herbalist": "herb"}

## Re-water a growing plot once it has used up this much of its own real
## wither grace window (FarmPlot.WATER_GRACE_FRACTION) -- a real margin
## before the actual wither point, grounded in a farmer checking crops on a
## walking circuit and watering ahead of visible wilting rather than only
## once a plant has started to droop. Shared with the placeable Farm's own
## worker (FarmerMarker) so the two cannot drift apart.
const WATER_BEFORE_WITHER_FRACTION := 0.5

## How much ground one villager can actually keep alive at once -- and
## therefore the most any single farmhouse hands its worker, however much
## clear ground its ring happens to have.
##
## MEASURED, not chosen. A villager walks at NpcMarker.WALK_SPEED and
## kneels for FarmerBehavior.WORK_SECONDS per plot, against a wither grace
## of half a 20-60s growth time (FarmPlot.WATER_GRACE_FRACTION). Over one
## real work block the yield does not taper past the limit -- it falls off
## a cliff, because a circuit longer than the grace window means every plot
## dies before it ripens and the farmer spends the whole block replanting
## ground that dies again:
##
##     2 cells ->  34 wheat     5 cells ->   2 wheat
##     3 cells ->  90 wheat     6 cells ->   0 wheat
##     4 cells ->  90 wheat
##
## Pinned by test_a_field_of_the_capped_size_really_produces_over_a_work_
## block and test_one_tile_more_than_the_cap_collapses_to_nothing
## (tests/unit/test_npc_marker_farming.gd), against a LINE of tiles -- the
## worst real case for a walking circuit, so the cap is conservative for a
## real farmhouse ring, which is more compact.
##
## This is exactly why a village grows its output by raising a SECOND
## farmhouse rather than a bigger field, which is the shape the report
## asked for ("so you can build multiple farms").
##
## Six, not ten, since the field became a compact rectangle (FIELD_SHAPES).
## Both answers point the same way and neither is a fresh guess: the report
## asked for "a 2x3 or 3x2 area", and six is where the measured yield table
## PEAKS -- 225 wheat per work block against 215 for everything from eight
## to fourteen (see "What a field costs to keep" in the concept doc). The
## four tiles this gives up were never worth anything.
const MAX_WORKED_CELLS := 6

## How long one work block is, in world seconds -- the stretch of a
## villager's day their schedule marks as work (NpcSchedule's own blocks),
## and the window every field yield in this file is measured over. Written
## here because the yield below is meaningless without it, and pinned to the
## measurement's own block by
## test_the_work_block_the_yield_is_measured_over_is_the_real_one.
const WORK_BLOCK_SECONDS := 900.0

## What a field of MAX_WORKED_CELLS really yields over one work block.
##
## MEASURED, not described. This number had only ever lived in a doc comment
## ("~215 wheat per work block"), and the founding roster now has to reason
## about it: a village lives on REAL WORK, not on the ambient drip, so "how
## many food producers does this village need" is its own subsistence draw
## divided by this (see SettlementDemand and
## docs/concept/settlement_food_calibration.md -- the drip is 0.22 per
## assessment against a draw of 6, so no amount of foraging feeds five
## households, and that is correct).
##
## Held to the real thing by
## test_a_capped_fields_yield_per_work_block_is_what_the_roster_is_told_it_is,
## which runs a real villager over a real field for a real work block. The
## tolerance there is deliberately loose (10%): the figure comes out of a
## walking circuit against a growth clock, not out of arithmetic, and
## pinning it tighter would make an honest measurement read as a flake.
##
## RE-MEASURED at 278 (from 225) once a bed stopped dying every night (see
## FarmPlot.MIN_WATER_GRACE_SECONDS): the old figure was the yield of a field
## that lost beds to the dark and spent part of every block replanting them,
## so a village sized against it was sized against a field that was partly
## broken. Re-measured by the same test that pinned the old one, not adjusted
## by hand.
const FIELD_YIELD_PER_WORK_BLOCK := 278.0

## The day a farmer's own schedule turns on: NpcMarker.SECONDS_PER_
## SIMULATED_DAY's own VALUE (60), restated here for the reason
## VillageImmigration gives for its copy -- a rendering node is not
## something a pure gameplay module may depend on -- and cross-checked by
## test_the_fields_day_is_the_farmers_own_clock so the two cannot drift.
const SECONDS_PER_LIVED_DAY := 60.0

## What a real field yields in one lived day (docs/concept/
## village_economy_balance.md mechanism 6), and the number a village SIZES
## its food works by -- SettlementFoodDemand.producers_needed and the
## assembly's "outnumbered" test read this, not the work-block figure
## above.
##
## MEASURED (tools/probe_village_economy.gd, tools/probe_field_timeline.gd,
## a real village east of Berlin): three six-bed fields harvested 299 units
## onto their farmhouse shelves in 20 lived days, and 163 in 10 -- five a
## field a day. FIELD_YIELD_PER_WORK_BLOCK works out to 18.5 a day, and it
## is not wrong about what it measures: a field worked for 900 seconds by a
## farmer who never leaves it. A real farmer works the day's two work
## blocks (eleven hours of twenty-four), walks between a cottage a street
## away and the field at walking pace -- a commute that eats most of a
## 27-second work window -- fetches water, and leaves beds empty for most
## of the day (the timeline probe reads five of six empty at many samples).
## A roster sized against the stub's figure founded a village of ten on two
## fields, raised three, and ate its shelves to zero.
##
## A literal, because it is a measurement; pinned in test_settlement_food_
## demand.gd below the stub's continuous-work day (the commute is real)
## and above one household's day of meals (a farmhouse is never a building
## for nobody). The two levers that would raise it are the commute and the
## well, and both are recorded in the concept doc rather than tuned here.
const FIELD_YIELD_PER_LIVED_DAY := 5.0

## How far out from the farmhouse a field may reach. Not the field's size
## -- MAX_WORKED_CELLS is that -- but how far the search looks for cells
## worth working when the near ones are water, road or already built on.
## Pinned by test_the_field_can_always_offer_a_full_cap_on_open_ground: a
## reach that could not offer MAX_WORKED_CELLS even on empty ground would
## cap the field below its own cap.
const FIELD_REACH_TILES := 3


## The ground a farmhouse at `origin` may work: out to the SIDES and
## DOWNWARDS of it, never north, nearest to the building first. Empty for a
## building the catalog does not know.
##
## Asked for directly: "the farmhouses should be placed adjacent to the
## main street and the fields be placed sideways and downwards of it". A
## village house fronts the street with its door south, so the ground north
## of a farmhouse is the next row of buildings, not somewhere to sow --
## which is why the field is a directed region and not the ring this used
## to return.
##
## More candidates are offered than any farmhouse will work: the caller
## filters them for water, paving and what is already built on, then takes
## the first MAX_WORKED_CELLS (see nearest_cells). Offering them nearest
## first is what makes that "the biggest field that actually fits", rather
## than whichever cells happened to come up.
## `behind` widens the reach NORTH of the building, exactly as it does for
## field_rect -- so a caller that SITED something behind the house (a
## fisher's pond, VillagePond.pond_rect) can look in the same place it put
## it. Without that the two disagreed, and a reload that could not find the
## pond it had already dug dug another one.
## The tallest shape a field (or a pond) can take -- how far north of a
## building `behind` has to reach to cover every rectangle field_rect could
## have placed there.
static func _tallest_field_shape() -> int:
	var tallest := 0
	for shape in FIELD_SHAPES:
		tallest = maxi(tallest, (shape as Vector2i).y)
	return tallest


static func field_cells(origin: Vector2i, building_id: String, behind: bool = false) -> Array:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return []
	var cells: Array = []
	var first_y := origin.y - (FIELD_REACH_TILES + _tallest_field_shape() if behind else 0)
	for y in range(first_y, origin.y + footprint.y + FIELD_REACH_TILES):
		for x in range(origin.x - FIELD_REACH_TILES, origin.x + footprint.x + FIELD_REACH_TILES):
			var cell := Vector2i(x, y)
			if _ring_distance(cell, origin, footprint) == 0:
				continue  # the building stands here -- not field
			cells.append(cell)
	return _ordered_by_nearness(cells, origin, footprint)


## Nearest the farmhouse first: by real distance out from its own walls,
## then by distance from its centre, then (y, x) so the answer never
## depends on which order the cells were generated in.
static func _ordered_by_nearness(cells: Array, origin: Vector2i, footprint: Vector2i) -> Array:
	var centre := Vector2(origin) + Vector2(footprint) * 0.5
	var ordered: Array = cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ra := _ring_distance(a, origin, footprint)
		var rb := _ring_distance(b, origin, footprint)
		if ra != rb:
			return ra < rb
		var da := (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(centre)
		var db := (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(centre)
		if not is_equal_approx(da, db):
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return ordered


## Whether `cell` is ground a farmhouse at `origin` could work at all: out
## to the sides or downwards, within reach, and not under the building.
static func _is_field_cell(cell: Vector2i, origin: Vector2i, footprint: Vector2i) -> bool:
	if cell.y < origin.y:
		return false  # north of a farmhouse is the next row of buildings
	var reach := _ring_distance(cell, origin, footprint)
	return reach >= 1 and reach <= FIELD_REACH_TILES


## The `limit` cells of `cells` a villager should actually work: the ones
## nearest the farmhouse itself, so the circuit between them stays short
## (see MAX_WORKED_CELLS -- a longer circuit than the wither grace yields
## nothing at all). Measured to the footprint's own centre, ties broken by
## (y, x), so the same farmhouse hands out the same field every time with
## nothing persisted.
static func nearest_cells(cells: Array, origin: Vector2i, building_id: String, limit: int) -> Array:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO or limit <= 0:
		return []
	var ordered := _ordered_by_nearness(cells, origin, footprint)
	return ordered.slice(0, mini(limit, ordered.size()))


## Which farmhouse in `origins` works `cell`, or null when none does.
##
## A farmhouse claims the ground its own footprint touches. Where two claim
## the same tile -- two farmsteads near each other, the ground between them
## split as it always was -- the nearer one takes it, measured from the
## footprint's own centre, and an exact tie goes to the lower (y, x) origin
## so the answer never depends on what order the farmhouses were listed in.
## Ground UNDER any farmhouse belongs to nobody: it is a building, not a
## field.
static func owner_of(cell: Vector2i, origins: Array, building_id: String):
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return null
	var best = null
	var best_key: Array = []
	for candidate in origins:
		var origin: Vector2i = candidate
		if _ring_distance(cell, origin, footprint) == 0:
			return null  # the cell is under a farmhouse, whichever one it is
		if not _is_field_cell(cell, origin, footprint):
			continue
		var centre := Vector2(origin) + Vector2(footprint) * 0.5
		var key: Array = [
			_ring_distance(cell, origin, footprint),
			(Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(centre), origin.y, origin.x
		]
		if best == null or key < best_key:
			best = origin
			best_key = key
	return best


## Chebyshev distance from `cell` to the footprint rectangle: 0 inside it,
## 1 for the ring field_cells returns, more further out.
static func _ring_distance(cell: Vector2i, origin: Vector2i, footprint: Vector2i) -> int:
	var dx: int = maxi(maxi(origin.x - cell.x, cell.x - (origin.x + footprint.x - 1)), 0)
	var dy: int = maxi(maxi(origin.y - cell.y, cell.y - (origin.y + footprint.y - 1)), 0)
	return maxi(dx, dy)


## The crop this occupation's own field grows, or "" for a villager with no
## field at all.
static func crop_for(occupation: String) -> String:
	return CROP_BY_OCCUPATION.get(occupation, "")


## What wants doing on one plot -- "harvest", "plant", "water", or "" for a
## plot that needs nothing right now. `plot` is null for ground nobody has
## ever tilled, which is the first thing a field needs.
static func action_for(plot) -> String:
	if plot == null:
		return "plant"
	if plot.state == "ready":
		return "harvest"
	if plot.state == "empty" or plot.state == "withered":
		return "plant"
	# Against the bed's OWN real window (FarmPlot.grace_seconds), not against
	# growth_time: a bed's tolerance has a floor of one night now, and a
	# threshold computed from growth time alone would describe a different,
	# shorter bed than the one that actually dies -- sending the farmer back
	# to soak ground in no danger while the field's real deadline moved.
	if (
		plot.state == "growing"
		and plot.time_since_watered >= plot.grace_seconds() * WATER_BEFORE_WITHER_FRACTION
	):
		return "water"
	return ""


## Which plot to work next: a ready one (harvest -- get real value off the
## field), then a growing one near its wither point (water it -- a bed
## already sown is work already done), then an empty or withered one
## (plant -- break new ground). -1 when nothing on this field needs
## attention.
##
## Watering used to come LAST, and measuring a real work block showed what
## that cost: a field of any size usually has an empty or withered bed
## somewhere, so the farmer planted instead of watering, every bed died on
## the vine, and the whole block went into replanting ground that died
## again. A three-tile field yielded ZERO wheat that way. Watering a sown
## bed costs one trip; losing it costs the entire growth cycle.
static func next_action(plots: Array) -> int:
	for kind in ["harvest", "water", "plant"]:
		var first := -1
		for i in plots.size():
			if action_for(plots[i]) != kind:
				continue
			# Unbroken ground first, among beds asking for the same thing.
			# Reported live with the field in shot: *"the NPC only sows 4 / 6
			# tiles"*, and measured (tools/probe_village_farming.gd): every
			# field in the sample held six cells, five cycling normally and
			# the sixth reporting "no marker, never tilled" after a full
			# 600-second work block -- the same bed, for both farmers in the
			# village.
			#
			# Ground nobody has tilled asks to be planted, and so does a bed
			# that was sown, ripened and harvested. Returning the first match
			# meant that once the earlier beds started cycling, one of them
			# was always an earlier "plant" than the ground at the end, and
			# the last bed was never broken at all. A farmer sows the FIELD
			# before sowing any of it twice.
			#
			# Only ever reorders beds wanting the SAME thing: a null plot's
			# action is "plant" and nothing else, so a ripe crop and a dying
			# bed still come first, which is what the kind order is for.
			if plots[i] == null:
				return i
			if first == -1:
				first = i
		if first != -1:
			return first
	# Nothing ripe, nothing dying, nothing bare -- so tend the THIRSTIEST
	# bed rather than stand still. A farmer in their own field always has
	# something to do, and this is what keeps a field alive: measured with
	# the farmer idling between thresholds, a three-tile field over a real
	# work block ran 108 replants, 72 waterings and ZERO harvests, because
	# beds died faster than the circuit came back round.
	var thirstiest := -1
	var worst := -1.0
	for i in plots.size():
		var plot = plots[i]
		if plot == null or plot.state != "growing" or plot.growth_time <= 0.0:
			continue
		var used: float = plot.time_since_watered / (plot.growth_time * FarmPlot.WATER_GRACE_FRACTION)
		if used > worst:
			worst = used
			thirstiest = i
	return thirstiest


## The fence line around the beds a villager actually works (see
## docs/concept/village_farms.md, "The fence around the beds"): every cell
## TOUCHING a worked bed that is not itself a bed and not the farmhouse's
## own footprint, nearest-of-(y, x) order so the same field fences the same
## ring every time with nothing persisted.
##
## Asked for directly, with the field circled in a screenshot: "the
## farmhouse should build a fence around the bed so no animals enter". A
## farm without a fence is a field that feeds deer.
##
## Diagonal neighbours count. A ring of only the four orthogonal ones has
## an open corner at every turn, which is not a fence -- it is four walls
## that miss each other.
##
## Only the WORKED beds are fenced, never the whole reachable ring: you
## fence what you sow, and the fallow part of a farmhouse's ring
## (MAX_WORKED_CELLS leaves ten of fourteen tiles fallow -- see that
## constant) is not the farm's yard.
##
## Pure geometry, exactly like field_cells and owner_of. Whether a rail can
## really stand on a given cell -- water, paving, something already built
## there -- is the caller's question, and the caller leaving the paving open
## is what makes the gate.
static func fence_cells(worked_cells: Array, origin: Vector2i, building_id: String) -> Array:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO or worked_cells.is_empty():
		return []
	var beds: Dictionary = {}
	for cell in worked_cells:
		beds[cell] = true
	var rails: Dictionary = {}
	for cell in worked_cells:
		var bed: Vector2i = cell
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var rail := bed + Vector2i(dx, dy)
				if beds.has(rail):
					continue  # a rail between two beds fences nothing
				if _ring_distance(rail, origin, footprint) == 0:
					continue  # the farmhouse's own wall closes that side
				rails[rail] = true
	var ordered: Array = rails.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return ordered


## Which side of the field this rail stands on -- "north", "south", "east"
## or "west", or "" for a cell that touches no bed at all. The sheet has one
## orientation column per answer (docs/concept/village_farms.md's art
## contract), so a run along the field's north edge is drawn back-on and a
## run down its east edge as posts seen from above.
##
## Measured from the bed the rail actually touches: a rail NORTH of a bed
## closes that bed's north side. A corner touches beds on two sides at once,
## and takes the vertical answer -- a corner post is drawn as part of the
## run it caps, and the north/south art is the piece that reads as a fence
## rather than a single post.
static func fence_facing(cell: Vector2i, worked_cells: Array) -> String:
	var beds: Dictionary = {}
	for bed in worked_cells:
		beds[bed] = true
	# A cell touched only on the DIAGONAL caps two runs at once: it is a
	# corner post, not a length of rail. Checked first, because a rail drawn
	# across a corner is exactly the broken look the report points at
	# ("corner pieces added so it doesn't look that broken").
	var orthogonal := 0
	for step in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if beds.has(cell + step):
			orthogonal += 1
	if orthogonal == 0:
		# Which SIDE the corner caps matters: the side wall below it is drawn
		# on its own inner edge (fence_inner_direction, applied by
		# IllustratedStructureSprite.footprint_offset), so a post that did
		# not know its side would sit half a tile off the run it caps -- a
		# visibly broken joint, and the opposite of what "corner pieces added
		# so it doesn't look that broken" asked for.
		for dy in [1, -1]:
			for dx in [1, -1]:
				if beds.has(cell + Vector2i(dx, dy)):
					# Both sides, not just the side wall: a corner post has
					# a ground POINT, not a ground line, and the run it sits
					# on is the one named by dy.
					if dx > 0:
						return "corner_nw" if dy > 0 else "corner_sw"
					return "corner_ne" if dy > 0 else "corner_se"
		return ""
	if beds.has(cell + Vector2i(0, 1)):
		return "north"
	if beds.has(cell + Vector2i(0, -1)):
		return "south"
	if beds.has(cell + Vector2i(-1, 0)):
		return "east"
	return "west"


## The rail tile for a facing, or "" for a direction nobody drew.
static func fence_tile_for(facing: String) -> String:
	return FENCE_TILE_IDS.get(facing, "")


## Whether this tile id is one of a village farm's rails, whichever way it
## faces -- the one question a creature's movement and the art registry both
## have to ask, so neither re-lists the ids.
static func is_fence_tile(tile_id: String) -> bool:
	if tile_id == "":
		return false
	return FENCE_TILE_IDS.values().has(tile_id) or LEGACY_FENCE_TILE_IDS.has(tile_id)


## Which way the beds lie from a rail cell -- and therefore which of that
## cell's own four edges the rails are actually DRAWN on, and the only line
## an animal may not cross. Vector2i.ZERO for anything that is not a rail.
##
## Asked for directly, with two sides of a real ring arrowed in a
## screenshot: *"move the fences to the inner edge of the enclosure and
## treat the rest of the tile as street"*. A rail used to be a whole solid
## tile -- ground no animal could stand on, painted as a bare earth square
## over whatever was already there. It is a LINE on ONE edge now, so the
## rest of its own tile is ordinary walkable ground and the ring round a
## field reads as the path the farmer walks rather than a brown moat.
##
## The direction is the INVERSE of what the facing names: a rail closing the
## field's NORTH side stands north of the beds, so its beds -- and its rails
## -- lie SOUTH of it. That is the same relation fence_facing measures in
## the other direction, and
## test_the_inner_edge_really_points_at_the_bed_the_rail_encloses pins the
## two against each other rather than trusting two hand-written tables.
## A run closes ONE side, so its inner direction is one axis: the edge of its
## own tile that faces the beds, and the line its rails are drawn on.
##
## A CORNER closes two at once, so its direction is the diagonal and what it
## names is a POINT -- the corner of its own tile where the two runs meet.
## Reported with all three visible corners crossed out ("the fences still
## aren't optimal"): while a corner knew only which side WALL it capped, its
## art was placed as a full tile of vertical rail with nothing saying where
## along that tile to stop, so the frame overshot by a whole tile at every
## corner. The second component is what stops that.
##
## It is also the honest answer for what an animal may cross there: the one
## way through a corner into the crop is that diagonal, and walking on round
## the turn is not blocked at all.
const FENCE_INNER_DIRECTIONS := {
	"north": Vector2i(0, 1),
	"south": Vector2i(0, -1),
	"east": Vector2i(-1, 0),
	"west": Vector2i(1, 0),
	"corner_nw": Vector2i(1, 1),
	"corner_ne": Vector2i(-1, 1),
	"corner_sw": Vector2i(1, -1),
	"corner_se": Vector2i(-1, -1),
}

## What a LEGACY corner knew: one axis, which is all a two-id corner ever
## carried. Enough to keep one drawn and out of the ground cover; not enough
## to sit it on the join, which is why the scheme changed.
const LEGACY_FENCE_INNER_DIRECTIONS := {
	"farm_fence_corner_west": Vector2i(1, 0),
	"farm_fence_corner_east": Vector2i(-1, 0),
}


## The facing a rail's tile id carries, or "" for anything that is not a
## rail -- the reverse of fence_tile_for, so nothing re-lists the ids.
static func fence_facing_of(tile_id: String) -> String:
	if tile_id == "":
		return ""
	for facing in FENCE_TILE_IDS:
		if FENCE_TILE_IDS[facing] == tile_id:
			return facing
	return ""


static func fence_inner_direction(tile_id: String) -> Vector2i:
	var facing := fence_facing_of(tile_id)
	if facing == "":
		return LEGACY_FENCE_INNER_DIRECTIONS.get(tile_id, Vector2i.ZERO)
	return FENCE_INNER_DIRECTIONS.get(facing, Vector2i.ZERO)


## Whether this rail is a corner POST rather than a length of rail -- a cell
## the beds touch only on the DIAGONAL, capping the two runs that meet
## there (see fence_facing).
static func is_fence_corner_tile(tile_id: String) -> bool:
	if LEGACY_FENCE_TILE_IDS.has(tile_id):
		return true
	return fence_facing_of(tile_id).begins_with("corner")


## How thick a rail's own collider is, in pixels.
##
## Derived, not chosen. The floor is the fastest the player can ever be --
## mounted on a maximum-fitness horse, Taming.MOUNTED_SPEED *
## MAX_FITNESS_SPEED_MULTIPLIER = 180 px/s, which is 3.0 px in one 60Hz
## physics tick -- so the rail holds even if a step is ever resolved without
## sweeping. The ceiling is a quarter of a tile, because a rail has to stay a
## LINE on one edge rather than a wall filling the cell, which is the whole
## distinction the walkable ring depends on. Both bounds are pinned by
## test_village_farm.gd rather than written down in this comment and trusted.
const FENCE_COLLIDER_THICKNESS_PX := 4.0


## The edge a rail's own collider sits on, as an outward normal -- the same
## inner edge rails_block_step already shuts, so what stops the PLAYER
## (physics) and what stops everybody else (that query) cannot disagree
## about a given rail.
##
## Vector2i.ZERO for anything that gets no collider at all: ordinary ground,
## and a CORNER post. The corner is the load-bearing case. Its inner
## direction is DIAGONAL, so an edge collider would have to lie along one of
## its two cardinal sides -- and both of those are the runs it caps. Walling
## either shuts the ring itself, the exact opposite of "treat the rest of the
## tile as street" and precisely what _rail_stops_step already refuses. The
## diagonal a corner does block needs no collider of its own: the two
## neighbouring runs' colliders meet at the shared corner point, and a body
## with any width at all cannot thread that.
static func fence_collider_normal(tile_id: String) -> Vector2i:
	if not is_fence_tile(tile_id) or is_fence_corner_tile(tile_id):
		return Vector2i.ZERO
	return fence_inner_direction(tile_id)


## That collider as a rectangle in TILE-LOCAL pixels -- (0, 0) is the tile's
## own top-left corner. Rect2() (zero size) for a tile that gets none.
##
## It spans the tile FULLY across the edge it lies on, so two rails side by
## side meet and leave no seam to squeeze through, and it never reaches
## outside its own tile.
##
## `fence_height` is how tall this rail's WOOD is actually drawn, in the same
## tile-local pixels -- because a HORIZONTAL rail stands at the FOOT of its
## wood, not on the tile edge its normal names. Reported live: "The
## horizontal fences should have the hitbox at the bottom of the rail ... so
## it should use fence height instead of thickness".
##
## It matters because the two horizontal facings anchor their art to
## OPPOSITE ends of the cell (IllustratedStructureSprite.footprint_offset:
## `inner.y > 0` bottom-anchors, `inner.y < 0` top-anchors). A north rail's
## wood really does end at the tile's bottom edge, so its collider never
## moved. A south rail's hangs DOWN from the top edge, so pinning its
## collider to that named edge stopped the player at the rail's HEAD --
## seven pixels short of the line they could see. A fence stops things where
## its posts meet the ground, and nowhere else.
##
## The height only ever moves a horizontal rail. A VERTICAL one is anchored
## left or right, so its foot is not a y coordinate at all and the edge its
## normal names is still exactly where it stands.
##
## The foot is clamped into [thickness, tile_size] so the strip stays inside
## its own cell whatever height it is handed -- art that measures taller than
## the tile, or shorter than the strip is deep, must not put a rail body in
## the NEIGHBOUR'S cell and wall a run that should be open.
static func fence_collider_rect(
	tile_id: String, tile_size: float, thickness: float, fence_height: float
) -> Rect2:
	var normal := fence_collider_normal(tile_id)
	if normal == Vector2i.ZERO:
		return Rect2()
	if normal.x != 0:
		var x := tile_size - thickness if normal.x > 0 else 0.0
		return Rect2(x, 0.0, thickness, tile_size)
	var foot := tile_size if normal.y > 0 else fence_height
	foot = clampf(foot, thickness, tile_size)
	return Rect2(0.0, foot - thickness, tile_size, thickness)


## Whether a step from one cell to the next CROSSES a rail's inner edge --
## the one thing a rail stops. `step` is the move as a cell delta (only its
## sign per axis matters); `from_tile_id`/`to_tile_id` are the modifications
## standing on each end of it.
##
## Blocked when the animal LEAVES a rail cell over that cell's own inner
## edge, or ENTERS a rail cell over ITS inner edge -- the same line, walked
## from the field side. Never otherwise, and that is precisely what makes
## the rest of a rail's tile ordinary ground: stepping onto the ring, along
## it, or away from the beds is all free, so the ring is a path an animal
## may walk and a farmer may work from.
##
## A diagonal crosses both of its own edges, so it is blocked whenever
## either component would be -- an animal must not slip round a corner of
## the ring that no cardinal step can pass.
static func rails_block_step(from_tile_id: String, to_tile_id: String, step: Vector2i) -> bool:
	return _rail_stops_step(from_tile_id, step) or _rail_stops_step(to_tile_id, -step)


## Whether the rail on ONE end of a step stops it, seen from that rail's own
## cell -- so the destination is asked with the step reversed, which is the
## same line walked from the field side.
##
## A CORNER post is the exception, and a load-bearing one: its beds are
## diagonal, so the only way through it into the crop is a diagonal. Its
## cardinal neighbours are the two runs it caps, and stopping a step along a
## run stops an animal walking the ring -- the exact opposite of "treat the
## rest of the tile as street", and caught by
## test_the_ring_of_a_rectangular_field_is_walkable_all_the_way_round, which
## a first pass failed at all four corners. Nothing is opened by it: every
## cardinal way in is still shut by the run's own rail.
static func _rail_stops_step(tile_id: String, step: Vector2i) -> bool:
	var inner := fence_inner_direction(tile_id)
	if inner == Vector2i.ZERO or step == Vector2i.ZERO:
		return false
	var crosses := (
		(inner.x != 0 and signi(step.x) == inner.x)
		or (inner.y != 0 and signi(step.y) == inner.y)
	)
	if not crosses:
		return false
	if is_fence_corner_tile(tile_id):
		# The one way through a corner into the crop is the diagonal it
		# actually faces. Its cardinal neighbours are the two runs it caps,
		# and stopping a step along a run stops an animal walking the ring.
		return signi(step.x) == inner.x and signi(step.y) == inner.y
	return true


## The compact rectangle of beds a farmhouse at `origin` works, or null when
## no shape fits anywhere in reach.
##
## Asked for directly, with the broken ring circled in a screenshot: "The
## fence should enclose a 2x3 or 3x2 area". A field used to be whichever
## cells of the reachable ring happened to be clear, taken nearest-first --
## and a scattered bed set has a RAGGED border, which is exactly what reads
## as broken fencing. A rectangle has a frame.
##
## Sited by the same rule the ring followed: to the sides and DOWNWARDS of
## the farmhouse, never north (a village house fronts the street with its
## door south, so the ground above it is the next row of buildings), nearest
## the building first, ties broken by (y, x) so the same farmhouse lays out
## the same field on every reload with nothing persisted.
##
## `is_free` answers for ONE cell: is this ground this farmhouse may sow?
## The caller owns what that means -- inside the chunk, dry, unbuilt, and
## owned by this farmhouse rather than its neighbour. Every cell of a
## rectangle must pass, because a field with a rock in the middle of it is
## not the rectangle that was asked for.
## `behind` opens the ground NORTH of the building to the search. Off by
## default, because for a farmhouse north really is the next row of
## buildings (see _rect_is_free). A fisher's pond passes it: measured at the
## first grassland village with a fisher, every free cell on the fisher's
## own side of the street was north of their house -- 32 of them -- so a
## search that could only look south had nowhere to go but across the road.
## `accepts_rect` is the caller's own further condition about the WHOLE
## rectangle — the same shape VillageLayout.street_plot's `accepts_origin`
## already has, and for the same reason it has it. A farmhouse with nowhere
## to farm is a farmhouse that should not have been raised; a fisher's pond
## with nowhere to put its hut is water that should have been dug
## elsewhere. A refused rectangle simply keeps the search going, so the
## caller gets the next-best site that does work rather than nothing.
##
## Omitted, the search is exactly the one this function has always done.
static func field_rect(
	origin: Vector2i, building_id: String, is_free: Callable, behind: bool = false,
	accepts_rect: Callable = Callable()
):
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return null
	var best = null
	var best_key: Array = []
	var centre := Vector2(origin) + Vector2(footprint) * 0.5
	for shape in FIELD_SHAPES:
		var size: Vector2i = shape
		var first_top := origin.y - (FIELD_REACH_TILES + size.y if behind else 0)
		for top in range(first_top, origin.y + footprint.y + FIELD_REACH_TILES):
			for left in range(origin.x - FIELD_REACH_TILES, origin.x + footprint.x + FIELD_REACH_TILES):
				var rect := Rect2i(left, top, size.x, size.y)
				if not _rect_is_free(rect, origin, footprint, is_free, behind):
					continue
				# Asked AFTER the cheap geometry, because it is the
				# expensive half: the pond's own use of it searches a whole
				# bank for somewhere a hut could stand.
				if accepts_rect.is_valid() and not accepts_rect.call(rect):
					continue
				var key: Array = [
					_rect_reach(rect, origin, footprint),
					(rect.get_center() as Vector2i as Vector2).distance_squared_to(centre),
					rect.position.y, rect.position.x, size.y, size.x,
				]
				if best == null or key < best_key:
					best = rect
					best_key = key
	return best


## Every cell of `rect` is ground this farmhouse may really sow: not north
## of the building, not under it, and accepted by the caller's own rule.
static func _rect_is_free(
	rect: Rect2i, origin: Vector2i, footprint: Vector2i, is_free: Callable,
	behind: bool = false
) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			if cell.y < origin.y and not behind:
				return false  # north of a farmhouse is the next row of buildings
			if _ring_distance(cell, origin, footprint) == 0:
				return false  # the building stands here
			if not is_free.call(cell):
				return false
	return true


## How far the WHOLE rectangle stands from the farmhouse's own walls -- its
## nearest cell, so a field that touches the building beats one a tile out.
static func _rect_reach(rect: Rect2i, origin: Vector2i, footprint: Vector2i) -> int:
	var nearest := 0x7FFFFFFF
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			nearest = mini(nearest, _ring_distance(Vector2i(x, y), origin, footprint))
	return nearest
