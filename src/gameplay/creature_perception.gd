extends RefCounted

## Lets a creature sense its surroundings: which other creatures/players are
## within sense range, and which way the nearest water or food is. The world
## is duck-typed (anything exposing biome_at_global(x, y) -> String, e.g.
## EarthChunkManager), so this stays unit-testable against a stub.
##
## - "water" is the ocean biome (the only water body this project models).
## - "food" (herbivore grazing) is any biome whose vegetation carrying
##   capacity is meaningful; barren biomes (desert/tundra/ocean/mountain) are
##   not food, so a herbivore on barren ground will trek toward greener tiles.

const VegetationGrowthModel = preload("res://src/world/vegetation_growth_model.gd")

const WATER_BIOME := "ocean"
## A biome counts as grazing food if its vegetation ceiling is at least this;
## picks out grassland/forest/rainforest and excludes sparse desert/tundra.
const MIN_FOOD_CAPACITY := 0.5

var _vegetation_model := VegetationGrowthModel.new()


## Positions from `candidates` within `radius` (in world/pixel units) of origin.
func nearby(origin: Vector2, candidates: Array, radius: float) -> Array:
	var result: Array = []
	for candidate in candidates:
		if origin.distance_to(candidate) <= radius:
			result.append(candidate)
	return result


## Whether the tile the creature is standing on is water/food itself.
func is_on(world, tile: Vector2i, kind: String) -> bool:
	return _matches(world, tile, kind)


## Normalized direction from origin_tile toward the nearest tile of `kind`
## ("water" or "food") within radius_tiles (Chebyshev). Returns ZERO if the
## origin tile already is that kind (nowhere to travel -- feed/drink in place)
## or if none is found in range.
func nearest_direction(origin_tile: Vector2i, world, radius_tiles: int, kind: String) -> Vector2:
	if _matches(world, origin_tile, kind):
		return Vector2.ZERO

	var best_offset := Vector2i.ZERO
	var best_distance := -1
	for dy in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			if dx == 0 and dy == 0:
				continue
			var tile := origin_tile + Vector2i(dx, dy)
			if not _matches(world, tile, kind):
				continue
			var distance := dx * dx + dy * dy
			if best_distance < 0 or distance < best_distance:
				best_distance = distance
				best_offset = Vector2i(dx, dy)

	if best_distance < 0:
		return Vector2.ZERO
	return Vector2(best_offset).normalized()


func _matches(world, tile: Vector2i, kind: String) -> bool:
	var biome: String = world.biome_at_global(tile.x, tile.y)
	if biome == "":
		return false
	match kind:
		"water":
			return biome == WATER_BIOME
		"food":
			return _vegetation_model.carrying_capacity_for_biome(biome) >= MIN_FOOD_CAPACITY
		_:
			return false
