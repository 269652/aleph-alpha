extends RefCounted

## What ground an agent may cross, and what crossing it costs (see
## docs/concept/navigation.md).
##
## Two separate questions, and keeping them separate is the whole point:
##
##   BLOCKED -- a building, or ground too steep to climb. Absolute.
##   COSTLY  -- water. Crossable, just slow.
##
## Water is deliberately NOT blocked, and that is not a softening. Making
## it absolute would stop creatures drinking at all (a thirsty creature
## must stand ON a water tile -- see CreatureMarker's own thirst check),
## and would delete the swim animation that villagers, creatures and the
## player already have. A river is an obstacle a person walks around if
## there is a dry way and wades if there is not, which is exactly what a
## cost expresses and a block cannot.
##
## Costs are TRAVEL TIME, not distance, and they are derived rather than
## invented: if swimming is BASE_SWIM_SPEED (0.6) of walking speed, then
## crossing a water tile takes 1/0.6 as long, and a route costed in time
## should say so. Slope reads the same way through
## TerrainPassability.speed_multiplier.

const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")


## A `func(tile: Vector2i) -> bool` for ground no agent may enter, or an
## INVALID Callable when `world` can answer none of these questions --
## read by both gates as "nothing is solid", the same duck-typed fail-open
## every mover here keeps.
static func blocked_predicate_for(world, has_climbing_gear: bool = false) -> Callable:
	if world == null:
		return Callable()
	# Prefer the PIECE question over the whole-footprint one. It is the
	# same question the wall's own collision body is spawned from (see
	# NpcMarker._slid_along_walls), so what stops a player, what stops a
	# villager and what a route plans around can never disagree -- and it
	# knows a DOOR and a FLOOR are walkable, where the footprint question
	# reports the whole building solid and would mean no villager could
	# ever plan a way indoors. The footprint question stays as the fallback
	# for a world that does not offer the finer one.
	var knows_pieces: bool = world.has_method("piece_blocks_movement_at_global")
	var knows_buildings: bool = world.has_method("has_building_at_global")
	var knows_slope: bool = world.has_method("slope_at_global")
	if not knows_pieces and not knows_buildings and not knows_slope:
		return Callable()
	return func(tile: Vector2i) -> bool:
		if knows_pieces:
			if world.piece_blocks_movement_at_global(tile.x, tile.y):
				return true
		elif knows_buildings and world.has_building_at_global(tile.x, tile.y):
			return true
		if knows_slope and not TerrainPassability.is_passable(
			world.slope_at_global(tile.x, tile.y), has_climbing_gear
		):
			return true
		return false


## A `func(tile: Vector2i) -> float` giving how much longer crossing this
## tile takes than open flat ground (1.0 = no penalty), or an INVALID
## Callable when `world` cannot say. Never below 1.0: A* stays optimal only
## while the heuristic never overestimates, and the octile heuristic
## assumes a scale of 1, so a tile cheaper than open ground would quietly
## make routes wrong rather than merely odd.
static func cost_scale_for(world) -> Callable:
	if world == null:
		return Callable()
	var knows_water: bool = (
		world.has_method("is_river_at_global")
		or world.has_method("is_lake_at_global")
		or world.has_method("biome_at_global")
	)
	var knows_slope: bool = world.has_method("slope_at_global")
	if not knows_water and not knows_slope:
		return Callable()
	return func(tile: Vector2i) -> float:
		var scale := 1.0
		if knows_water and _is_water(world, tile):
			scale /= WaterMovementModel.BASE_SWIM_SPEED
		if knows_slope:
			var speed: float = TerrainPassability.speed_multiplier(
				world.slope_at_global(tile.x, tile.y)
			)
			if speed > 0.0:
				scale /= speed
		return maxf(scale, 1.0)


## River, lake or open sea -- each asked only of a world that offers it, so
## a partial stub answers for whichever it knows.
static func _is_water(world, tile: Vector2i) -> bool:
	if world.has_method("is_river_at_global") and world.is_river_at_global(tile.x, tile.y):
		return true
	if world.has_method("is_lake_at_global") and world.is_lake_at_global(tile.x, tile.y):
		return true
	return (
		world.has_method("biome_at_global")
		and world.biome_at_global(tile.x, tile.y) == "ocean"
	)
