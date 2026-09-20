extends RefCounted

## The fisher's own water: a 3x2 pond dug where the farmer's field is sown
## (docs/concept/village_ponds.md). Asked for directly: *"The Fisher should
## build a similar 3x2 enclosure but filled with water and a pond with river
## water physics and fish swimming in it which reproduce"*.
##
## "Similar" is taken literally and structurally. Siting and fencing are
## VillageFarm's, DELEGATED rather than restated: a pond that chose its own
## ground or drew its own frame would drift away from the field it is
## modelled on the first time either changed, and the two have already moved
## together twice (the rectangle, then the frame). What is genuinely this
## module's own is the WATER -- that a pond cell is a built, persisted thing
## the rest of the world reads as real water.
##
## Pure, like VillageFarm: geometry in, cells out, nothing stored.

const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const AquaticPopulationModel = preload("res://src/world/aquatic_population_model.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

## The fisher's own works, the building a farmer's farmhouse is to their
## beds. Reported live with a screenshot of a dug, fenced, EMPTY enclosure:
## "it's missing a fisher hut (use farmhouse sprite until illustration
## exists)" -- the half of "the same shape as a field" that was never
## built.
const HUT_BUILDING_ID := "fisher_hut"

## How far from its own water a hut may stand, in tiles, measured from the
## nearest cell of each. Two, not one: the water is fenced (VillageFarm's
## own rails, on the ring), so a hut demanding to touch the water could
## only ever stand on the rails themselves, and there would be no hut at
## all. Two clears the ring and still reads as a building AT the pond
## rather than one that happens to be near it.
const HUT_BANK_REACH_TILES := 2

## Where the water's own edge is, as the surface overlay reads it.
##
## Every kind of water in this world rides one overlay (docs/concept/
## hydrology.md, "ONE WATER SURFACE") over an ACROSS field: |across| below
## 1 is water, 1 is the waterline, and the shader reconstructs that field
## by interpolating between cell centres. A pond is not a channel -- it is
## a flat-bottomed hole -- so its own cells carry WATER_ACROSS, open water
## throughout, and the ring of dry cells round it carries BANK_ACROSS.
##
## Those two numbers are one decision, not two: interpolating from 0 at a
## water cell's centre to 2 at the bank's centre crosses 1 exactly halfway
## between them, which is the water cell's own edge -- the edge of the
## hole. waterline_offset_tiles states it and
## test_a_ponds_waterline_lands_on_its_own_edge pins it, so a change to
## either number that moved the waterline off the pond's edge fails there.
##
## Measured before: the pond wrote 0.75 on its own cells and left the ring
## carrying whatever the nearest river had (tens of tiles' worth), so the
## contour crossed 1 a few pixels out from each centre and a 3x2 pond read
## as a puddle -- 10.4% of its own area was water on a real render
## (tools/probe_fisher_pond_render.gd).
const WATER_ACROSS := 0.0
const BANK_ACROSS := 2.0


## How far from a water cell's own centre the waterline falls, in tiles,
## given those two. Half a tile IS that cell's edge.
static func waterline_offset_tiles() -> float:
	return (1.0 - WATER_ACROSS) / (BANK_ACROSS - WATER_ACROSS)

## What a dug pond cell persists as. An ordinary chunk modification, exactly
## like a rail -- the id is the only thing stored about it, which is what
## lets a pond survive a reload with no record of the fisher who dug it.
##
## Deliberately NOT a biome: chunk.biome is what the world GENERATED, and a
## village pond is something built on top of it. The water queries widen to
## include this id instead (EarthChunkManager.is_water_at_global /
## is_river_at_global), so every consumer that already asks "is this water"
## gets the right answer with no case of its own.
const POND_TILE_ID := "pond_water"


static func is_pond_tile(tile_id: String) -> bool:
	return tile_id != "" and tile_id == POND_TILE_ID


## The rectangle of water a fisher living at `origin` digs, or null when no
## shape fits in reach -- the FIELD rule, unchanged (see this file's own doc
## comment for why it is delegated rather than restated).
##
## `is_free` answers for ONE cell: is this ground the fisher may dig?
## Unlike a farm's beds, a pond may be dug BEHIND the house. A farmhouse
## refuses ground north of itself because that is the next row of buildings
## -- true of a farm laid out along a street, and exactly wrong for a
## fisher, whose house fronts the street to the south so that every scrap of
## their own ground is behind them. Without this the search had nowhere to
## go but over the road, which is what put the water across the street from
## its owner (reported live).
static func pond_rect(origin: Vector2i, building_id: String, is_free: Callable):
	return VillageFarm.field_rect(origin, building_id, is_free, true)


## Those cells, in the same (y, x) order everything else here returns, or []
## where no pond fits.
static func pond_cells(origin: Vector2i, building_id: String, is_free: Callable) -> Array:
	var rect = pond_rect(origin, building_id, is_free)
	if rect == null:
		return []
	var cells: Array = []
	for y in range((rect as Rect2i).position.y, (rect as Rect2i).end.y):
		for x in range((rect as Rect2i).position.x, (rect as Rect2i).end.x):
			cells.append(Vector2i(x, y))
	return cells


## The frame round that water -- the field's own ring, rails, facings and
## corner posts included.
static func fence_cells(origin: Vector2i, building_id: String, is_free: Callable) -> Array:
	return VillageFarm.fence_cells(pond_cells(origin, building_id, is_free), origin, building_id)


## How many fish a fisher puts in when they stock a pond.
##
## Two, because logistic growth from nothing is nothing: an unstocked pond
## stays empty however good its water is, which is the honest behaviour (a
## village pond is stocked deliberately -- see docs/concept/village_ponds.md)
## and also what makes the stocking a real act rather than decoration. One
## fish is a pet. Pinned by test_a_stocking_is_enough_fish_to_breed.
## How deep a dug pond is, in metres.
##
## A pond dug to KEEP fish is dug deep enough for them to overwinter in --
## roughly two metres is the standard temperate figure, and the reason a
## village fish pond is a real hole rather than a scrape. 1.8 m sits inside
## that and comfortably past WaterMovementModel.WADE_DEPTH_METERS, which is
## the part that matters in play: a fisher's pond is water to swim in, not a
## puddle to walk through. Pinned against that threshold rather than as a
## bare number (test_village_pond.gd).
##
## Reported live: "there's no real pond with river / lake water physics".
## A pond answered is_water_at_global -- so nothing built or grew on it --
## but had no depth at all, and the player's water state is the maximum of
## ocean, river and lake depth, three sources a pond was not one of.
const DEPTH_METERS := 1.8

const STOCKING_FISH := 2

## The pond's own population model. The world's OWN aquatic one, not a second
## model: a pond is a small body of water, and fish in it breed for the same
## reasons and at the same rate as fish anywhere else
## (docs/concept/fishing.md's aquatic population model). A pond with its own
## curve would be one more thing to keep in step with open water.
static var _fish := AquaticPopulationModel.new()


## How many fish this much pond water can feed at `temperature` (normalized
## [0, 1], the Chunk.temperature convention).
static func carrying_capacity(water_cells: int, temperature: float) -> float:
	return _fish.carrying_capacity(float(maxi(water_cells, 0)), temperature)


## The population after `delta_days` of breeding toward that ceiling. Zero in
## stays zero out -- a pond nobody stocked grows nothing.
static func step(population: float, water_cells: int, temperature: float, delta_days: float) -> float:
	return _fish.step(population, carrying_capacity(water_cells, temperature), delta_days)


## Where a fisher's hut stands: the free site nearest their own water,
## within HUT_BANK_REACH_TILES of it. Null when nothing fits, which is the
## honest answer a pond with no room already gives rather than a hut
## squeezed onto the rails.
##
## `is_free` answers for ONE cell, exactly as pond_rect's does: is this
## ground the village may build on? The water itself is refused here too,
## and not only through `is_free` -- a caller reading the world will refuse
## it anyway (a pond is a modification), but the rule that a hut is beside
## the water rather than in it belongs to this function, not to its caller.
##
## Deterministic by construction: candidates are walked in (y, x) order and
## only a STRICTLY nearer one displaces the site already held, so the same
## water puts the hut in the same place on every reload -- which is what
## stops a village growing a second hut every time it is walked past.
static func hut_origin(water: Array, is_free: Callable):
	if water.is_empty():
		return null
	var footprint := BuildingCatalog.footprint_of(HUT_BUILDING_ID)
	var low := water[0] as Vector2i
	var high := low
	for cell in water:
		low = Vector2i(mini(low.x, (cell as Vector2i).x), mini(low.y, (cell as Vector2i).y))
		high = Vector2i(maxi(high.x, (cell as Vector2i).x), maxi(high.y, (cell as Vector2i).y))
	var margin := HUT_BANK_REACH_TILES + maxi(footprint.x, footprint.y)
	var best = null
	var best_distance := INF
	for y in range(low.y - margin, high.y + margin + 1):
		for x in range(low.x - margin, high.x + margin + 1):
			var origin := Vector2i(x, y)
			var distance := _hut_distance_to(origin, footprint, water)
			if distance > float(HUT_BANK_REACH_TILES) or distance >= best_distance:
				continue
			if not _hut_site_is_free(origin, footprint, water, is_free):
				continue
			best = origin
			best_distance = distance
	return best


## Whether one of `hut_origins` already stands on this water's own bank --
## the idempotence question, asked of the ground rather than of a record
## nothing persists: a village walked past twice must not grow a second hut
## over the same pond.
static func hut_stands_by(water: Array, hut_origins: Array) -> bool:
	if water.is_empty():
		return false
	var footprint := BuildingCatalog.footprint_of(HUT_BUILDING_ID)
	for origin in hut_origins:
		if _hut_distance_to(origin as Vector2i, footprint, water) <= float(HUT_BANK_REACH_TILES):
			return true
	return false


## How close a hut at `origin` comes to the water, nearest cell to nearest
## cell.
static func _hut_distance_to(origin: Vector2i, footprint: Vector2i, water: Array) -> float:
	var nearest := INF
	for cell in BuildingCatalog.footprint_cells(HUT_BUILDING_ID, origin):
		for wet in water:
			nearest = minf(nearest, Vector2(cell as Vector2i).distance_to(Vector2(wet as Vector2i)))
	return nearest


## Every cell a hut at `origin` would take -- its footprint AND its
## doorstep, which is what place_building itself requires -- free ground,
## and none of it the pond's own water.
static func _hut_site_is_free(origin: Vector2i, footprint: Vector2i, water: Array, is_free: Callable) -> bool:
	var taken: Array = BuildingCatalog.footprint_cells(HUT_BUILDING_ID, origin)
	taken.append(origin + BuildingCatalog.doorstep_of(HUT_BUILDING_ID))
	for cell in taken:
		if water.has(cell):
			return false
		if not is_free.call(cell as Vector2i):
			return false
	return true
