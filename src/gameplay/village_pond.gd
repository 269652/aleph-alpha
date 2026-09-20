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
