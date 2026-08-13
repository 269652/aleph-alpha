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

## Headings tried in order when the current heading would beach the fish:
## straight first, then increasingly sharp deflections to either side, then a
## full reversal -- so a fish meeting the shore slides along it (or turns
## back) instead of freezing in place for the whole direction interval.
const _DEFLECTION_TURNS: Array[float] = [
	0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0, PI
]

## How fast a fish can turn to face a new heading, in radians/sec.
## CreatureWander's own target heading only changes once per
## DIRECTION_CHANGE_INTERVAL (1.5s) -- applying it instantly made a fish swim
## in a dead-straight line for a second and a half, then teleport its
## heading, which read as robotic rather than swimming (the reported "still
## don't move naturally"). Turning gradually toward the target instead, and
## rotating the sprite to face it, reads as a fish actually steering. Pinned
## by test_heading_turn_rate_is_bounded_per_frame.
const TURN_RATE := 3.0

var home := Vector2.ZERO
var wander_seed := 0
var species := "goldfish"

var _wander := CreatureWander.new()
var _elapsed_time := 0.0
var _world = null
var _tile_size := 16
## The fish's smoothed swim heading -- turns gradually toward CreatureWander's
## target each frame (see TURN_RATE) rather than snapping to it, and drives
## the sprite's rotation so the fish visibly faces the way it's swimming.
var _current_heading := Vector2.RIGHT

## A world position this fish steers toward instead of its normal wander
## target (see EarthChunkManager.set_attraction_point, driven by a cast
## fishing line -- Player._fishing_step) -- null for "no attraction, wander
## normally". Still goes through the same turn-rate smoothing and shore
## deflection as ordinary wandering, so an attracted fish steers in, not
## teleports, and never follows a lure up onto the beach.
var attract_target = null

## Once within this many pixels of attract_target, resume normal wandering
## instead of trying to close the last few pixels exactly (avoids jittering
## in place on top of the target).
const _ATTRACTION_STOP_DISTANCE := 6.0


func set_attraction(target: Vector2) -> void:
	attract_target = target


func clear_attraction() -> void:
	attract_target = null


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
		var before := position
		position = _wander.step_position(home, position, _elapsed_time, delta, wander_seed)
		_face_along(position - before)
		return

	# Turn the swim heading gradually toward the target rather than snapping
	# straight to it (see TURN_RATE) -- either an active attraction (a cast
	# line nearby) once far enough from it to matter, or ordinary wandering.
	var target: Vector2
	if attract_target != null and position.distance_to(attract_target) > _ATTRACTION_STOP_DISTANCE:
		target = (attract_target - position).normalized()
	else:
		target = _wander.direction_at(home, position, _elapsed_time, wander_seed)
	_current_heading = Vector2.from_angle(
		lerp_angle(_current_heading.angle(), target.angle(), clampf(TURN_RATE * delta, 0.0, 1.0))
	)

	# Try the (now-smoothed) heading first; if any part of the fish would end
	# up over land there, deflect through _DEFLECTION_TURNS until one keeps
	# the whole sprite wet -- and COMMIT that deflection as the new heading,
	# so a fish sliding along a shore visibly turns instead of jumping
	# between unrelated angles frame to frame. Only a fully-enclosed fish (a
	# 1-tile pond) ever holds still.
	for turn in _DEFLECTION_TURNS:
		var heading := _current_heading.rotated(turn)
		var candidate := position + heading * CreatureWander.WANDER_SPEED * delta
		if _has_water_clearance(candidate):
			position = candidate
			_current_heading = heading
			rotation = heading.angle()
			return


## Faces the sprite along an actual movement delta -- used by the unconfined
## (no-world) fallback, which doesn't compute a heading of its own.
func _face_along(movement: Vector2) -> void:
	if movement.length() > 0.001:
		_current_heading = movement.normalized()
		rotation = _current_heading.angle()


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
