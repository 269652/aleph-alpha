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
	var knows_pieces: bool = world.has_method("piece_blocks_movement_at_global")
	var knows_buildings: bool = world.has_method("has_building_at_global")
	var knows_slope: bool = world.has_method("slope_at_global")
	if not knows_pieces and not knows_buildings and not knows_slope:
		return Callable()
	return func(tile: Vector2i) -> bool:
		if structure_blocks(world, tile):
			return true
		if knows_slope and not TerrainPassability.is_passable(
			world.slope_at_global(tile.x, tile.y), has_climbing_gear
		):
			return true
		return false


## Whether a SOLID structure stands on `tile` -- the one question every
## walking marker asks about buildings, so six gates cannot answer it six
## ways.
##
## BOTH kinds of building, and that `or` is the whole point. Reported twice:
## *"Creatures and NPCs also walk through houses"*, then, after every marker
## had grown a gate, **"NPCs still walk through houses and ignore the
## hitbox"**. The gate was right; the question was half of one.
##
##   - A legacy **BuildingPiece** structure is a grid of wall/floor/door
##     tiles, and `piece_blocks_movement_at_global` is the same question its
##     wall's own collision body is spawned from -- so it knows a DOOR and a
##     FLOOR are walkable and going indoors is untouched.
##   - A **whole-building entity** -- what a village house is now (see
##     docs/concept/building.md, "Buildings are entities; interiors are
##     scenes") -- has no pieces AT ALL. `BuildingCatalog.occupies` says so:
##     "a legacy BuildingPiece or a single-tile placeable is its own thing
##     and answers false here". The piece question therefore answers `false`
##     on every cell of a cottage, while the player is stopped by a
##     `StaticBody2D` over its whole footprint.
##
## Asking only the first left the player and the markers stopped by two
## different kinds of building. They are disjoint kinds, so asking both
## costs nothing and shuts the gap.
##
## Its whole footprint is solid, and that is safe rather than coarse: a
## whole building's interior is a separate SCENE, entered from its DOORSTEP,
## which `BuildingCatalog.doorstep_of` puts "just south of the door, outside
## the footprint". Nobody ever needed to walk through the footprint to get
## in.
##
## Duck-typed, like every gate here: a world that answers neither question
## -- a test double, or a marker set up before its world exists -- simply
## reports nothing solid rather than erroring once per frame.
static func structure_blocks(world, tile: Vector2i) -> bool:
	if world == null:
		return false
	if (
		world.has_method("piece_blocks_movement_at_global")
		and world.piece_blocks_movement_at_global(tile.x, tile.y)
	):
		return true
	return (
		world.has_method("has_building_at_global")
		and world.has_building_at_global(tile.x, tile.y)
	)


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
