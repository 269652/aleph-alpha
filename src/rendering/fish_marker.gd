extends Sprite2D

## A swimming pond/ocean fish -- deliberately lightweight compared to
## CreatureMarker: no needs/perception/behavior AI, just CreatureWander's pure
## idle-drift pattern (see creature_wander.gd) confined to water tiles, so a
## small pond's fish read as "alive" without wandering up onto the grass.
## Caught via Player's fishing rod interaction (see FishRenderer,
## EarthChunkManager's fish spawn/despawn wiring).

const CreatureWander = preload("res://src/rendering/creature_wander.gd")

## How much open water the fish keeps around its center on every side --
## roughly the sprite's half-extent, so no part of the fish visually overlaps
## the beach regardless of which way it's pointing (the reported "stranded at
## the shoreline" look was its flank/nose hanging over land while the center
## was still on the last water pixel). Pinned by
## test_fish_clearance_keeps_it_clear_of_the_waterline.
const CLEARANCE_PX := 6.0

## The compass points around a candidate position that must all be water for
## the move to count (see CLEARANCE_PX).
const _CLEARANCE_PROBES: Array[Vector2] = [
	Vector2(CLEARANCE_PX, 0), Vector2(-CLEARANCE_PX, 0),
	Vector2(0, CLEARANCE_PX), Vector2(0, -CLEARANCE_PX),
]

## Headings tried in order when the wander direction would beach the fish:
## straight first, then increasingly sharp deflections to either side, then a
## full reversal -- so a fish meeting the shore slides along it (or turns
## back) instead of freezing in place for the whole direction interval.
const _DEFLECTION_TURNS: Array[float] = [
	0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0, PI
]

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
	if _world == null:
		position = _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
		return

	# Try the wander heading first; if any part of the fish would end up over
	# land there, deflect through _DEFLECTION_TURNS until a heading keeps the
	# whole sprite wet. Only a fully-enclosed fish (a 1-tile pond) holds still.
	var direction := _wander.direction_at(home, position, _elapsed_time, wander_seed)
	for turn in _DEFLECTION_TURNS:
		var heading := direction.rotated(turn)
		var candidate := position + heading * CreatureWander.WANDER_SPEED * delta
		if _has_water_clearance(candidate):
			position = candidate
			return


## True when `center` and every CLEARANCE_PX compass probe around it are over
## water -- i.e. the whole sprite would sit visibly in the water there.
func _has_water_clearance(center: Vector2) -> bool:
	if not _is_water(center):
		return false
	for probe in _CLEARANCE_PROBES:
		if not _is_water(center + probe):
			return false
	return true


func _is_water(pixel_position: Vector2) -> bool:
	var tile_x := int(floor(pixel_position.x / _tile_size))
	var tile_y := int(floor(pixel_position.y / _tile_size))
	return _world.biome_at_global(tile_x, tile_y) == "ocean"
