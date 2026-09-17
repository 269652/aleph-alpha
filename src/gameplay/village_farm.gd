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
const MAX_WORKED_CELLS := 4


## The ring of tiles directly around `building_id`'s footprint at `origin`
## -- its field. Row-major from the north-west corner, so the order is
## deterministic. Empty for a building the catalog does not know.
##
## The ring is DERIVED from the catalog footprint rather than written down:
## the rectangle one tile out on every side, minus the ground the building
## itself stands on. For the 3x2 farmhouse that is 5x4 - 6 = 14 tiles.
static func field_cells(origin: Vector2i, building_id: String) -> Array:
	var footprint := BuildingCatalog.footprint_of(building_id)
	if footprint == Vector2i.ZERO:
		return []
	var cells: Array = []
	for y in range(origin.y - 1, origin.y + footprint.y + 1):
		for x in range(origin.x - 1, origin.x + footprint.x + 1):
			if x >= origin.x and x < origin.x + footprint.x and y >= origin.y and y < origin.y + footprint.y:
				continue  # the building stands here -- not field
			cells.append(Vector2i(x, y))
	return cells


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
	var centre := Vector2(origin) + Vector2(footprint) * 0.5
	var ordered: Array = cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(centre)
		var db := (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(centre)
		if not is_equal_approx(da, db):
			return da < db
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
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
		var reach := _ring_distance(cell, origin, footprint)
		if reach == 0:
			return null  # the cell is under a farmhouse, whichever one it is
		if reach != 1:
			continue
		var centre := Vector2(origin) + Vector2(footprint) * 0.5
		var key: Array = [
			reach, (Vector2(cell) + Vector2(0.5, 0.5)).distance_squared_to(centre), origin.y, origin.x
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
## field) beats an empty or withered one (plant -- start the next cycle)
## beats a growing one near its wither point (water it). -1 when nothing on
## this field needs attention.
static func next_action(plots: Array) -> int:
	for kind in ["harvest", "plant", "water"]:
		for i in plots.size():
			if action_for(plots[i]) == kind:
				return i
	return -1
