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
}

## What each farming occupation grows. Same table shape NpcMarker.
## QUARRY_KIND_BY_OCCUPATION already uses for hunter/fisher; an occupation
## absent from it has no field at all, which is the honest answer for every
## villager who is not a farmer or a herbalist.
const CROP_BY_OCCUPATION := {"farmer": "wheat", "herbalist": "herb"}

## Re-water a growing plot once it has used up this much of its own real
## wither grace window (FarmPlot.WATER_GRACE_FRACTION) -- a real margin
## before the actual wither point, grounded in a farmer checking crops on a
## walking circuit and watering ahead of visible wilting rather than only
## once a plant has started to droop. Shared with the placeable Farm's own
## worker (FarmerMarker) so the two cannot drift apart.
const WATER_BEFORE_WITHER_FRACTION := 0.5

## How much workable ground a farmhouse's own field ring must really have
## before a village raises one there -- a farmhouse with nowhere to farm is
## a farmhouse that should not have been built. NOT a fresh guess: it is
## the plot count the placeable Farm's own worker already tends
## (FarmerMarker.PLOT_COUNT), which is the one number in this codebase that
## has been measured against what a single farmer can actually keep
## watered. Pinned to it by test_the_smallest_worthwhile_field_is_what_one_
## farmer_can_already_tend rather than preloaded here, so this module stays
## free of any rendering dependency.
const MIN_FIELD_CELLS := 3

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
const MAX_WORKED_CELLS := 10

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
static func field_cells(origin: Vector2i, building_id: String) -> Array:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return []
	var cells: Array = []
	for y in range(origin.y, origin.y + footprint.y + FIELD_REACH_TILES):
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
	if (
		plot.state == "growing"
		and plot.time_since_watered >= (
			plot.growth_time * FarmPlot.WATER_GRACE_FRACTION * WATER_BEFORE_WITHER_FRACTION
		)
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
		for i in plots.size():
			if action_for(plots[i]) == kind:
				return i
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
	if beds.has(cell + Vector2i(0, 1)):
		return "north"
	if beds.has(cell + Vector2i(0, -1)):
		return "south"
	if beds.has(cell + Vector2i(-1, 0)):
		return "east"
	if beds.has(cell + Vector2i(1, 0)):
		return "west"
	# Only a diagonal bed touches this cell: a corner post. Take the side
	# the bed lies on vertically, for the same reason a corner does above.
	for dy in [1, -1]:
		for dx in [1, -1]:
			if beds.has(cell + Vector2i(dx, dy)):
				return "north" if dy > 0 else "south"
	return ""


## The rail tile for a facing, or "" for a direction nobody drew.
static func fence_tile_for(facing: String) -> String:
	return FENCE_TILE_IDS.get(facing, "")


## Whether this tile id is one of a village farm's rails, whichever way it
## faces -- the one question a creature's movement and the art registry both
## have to ask, so neither re-lists the ids.
static func is_fence_tile(tile_id: String) -> bool:
	return tile_id != "" and FENCE_TILE_IDS.values().has(tile_id)
