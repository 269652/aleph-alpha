extends Sprite2D

## A swimming pond/ocean fish -- deliberately lightweight compared to
## CreatureMarker: no needs/perception/behavior AI, just CreatureWander's pure
## idle-drift pattern (see creature_wander.gd) confined to water tiles, so a
## small pond's fish read as "alive" without wandering up onto the grass.
## Caught via Player's fishing rod interaction (see FishRenderer,
## EarthChunkManager's fish spawn/despawn wiring).

const CreatureWander = preload("res://src/rendering/creature_wander.gd")

var home := Vector2.ZERO
var wander_seed := 0
var species := "goldfish"

var _wander := CreatureWander.new()
var _elapsed_time := 0.0
var _world = null
var _tile_size := 16


## `world` (duck-typed biome_at_global, same contract as CreatureMarker.setup)
## lets the fish check a candidate step is still over water before committing
## to it. Left unset (default null), the fish swims unconfined -- the same
## isolated-test fallback CreatureMarker uses.
func setup(world, tile_size: int) -> void:
	_world = world
	_tile_size = tile_size


func _process(delta: float) -> void:
	_elapsed_time += delta
	var candidate := _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
	if _world != null and not _is_water(candidate):
		return  # would beach itself -- stay put this frame instead
	position = candidate


func _is_water(pixel_position: Vector2) -> bool:
	var tile_x := int(floor(pixel_position.x / _tile_size))
	var tile_y := int(floor(pixel_position.y / _tile_size))
	return _world.biome_at_global(tile_x, tile_y) == "ocean"
