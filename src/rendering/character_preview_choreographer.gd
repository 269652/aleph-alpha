extends RefCounted
class_name CharacterPreviewChoreographer

## Deterministic, looping choreography for the character creator's live
## preview stage (see scenes/character_preview_stage.gd): walk back and
## forth through the grass, swing the sword, then walk to a pebble, pick it
## up, and throw or kick it away (alternating by loop) -- kept to one fixed,
## readable sequence rather than a generalized behavior system, since this
## is a decorative vignette, not gameplay.
##
## Pure functions of (t, loop_index) -- no wall-clock/random dependency, so
## every case is a plain input->output assertion (mirrors this codebase's
## other pure choreography helpers: WeaponSwing.rotation_at,
## Kick.landing_position). The caller (CharacterPreviewStage) owns the
## actual running clock and feeds it in.

const CharacterView = preload("res://scenes/character_view.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## A representative small pebble -- real mass derived from a real diameter
## (StoneSize.mass_kg_for, called where used rather than cached in a const:
## GDScript const initializers can't call another script's static function),
## the same physics every other stone in the game uses, not an invented
## number. Comfortably inside Kick.is_kickable's pebble range
## (< StoneSize.LEG_MASS_KG).
const PEBBLE_DIAMETER_CM := 4.0

## A deliberate, full-power throw -- the showcase should read as a real
## throw, not a half-hearted toss (see HeldItemThrow.release_speed_mps's own
## MIN/MAX bounds).
const THROW_POWER_FRACTION := 1.0

## Phase durations, in seconds -- pacing for a decorative loop (animation
## timing, the same category as WALK_CYCLE_SPEED/SWIM_CYCLE_SPEED in
## character_view.gd, both plain untested constants already), not a
## gameplay-tuned threshold.
const WALK_OUT_DURATION := 2.5
const WALK_BACK_DURATION := 2.5
const SWING_DURATION := 1.0
const WALK_TO_PEBBLE_DURATION := 2.0
const PICKUP_DURATION := 0.5
const THROW_OR_KICK_DURATION := 1.0
const RETURN_DURATION := 2.0

const LOOP_DURATION := (
	WALK_OUT_DURATION + WALK_BACK_DURATION + SWING_DURATION + WALK_TO_PEBBLE_DURATION
	+ PICKUP_DURATION + THROW_OR_KICK_DURATION + RETURN_DURATION
)

# Phase start times, derived from the durations above so a phase's boundary
# can never drift out of sync with its own duration or with LOOP_DURATION.
const _WALK_BACK_START := WALK_OUT_DURATION
const _SWING_START := _WALK_BACK_START + WALK_BACK_DURATION
const _WALK_TO_PEBBLE_START := _SWING_START + SWING_DURATION
const _PICKUP_START := _WALK_TO_PEBBLE_START + WALK_TO_PEBBLE_DURATION
const _THROW_OR_KICK_START := _PICKUP_START + PICKUP_DURATION
const _RETURN_START := _THROW_OR_KICK_START + THROW_OR_KICK_DURATION

## How far the character walks out from center, and where the pebble sits --
## world px, sized for this scene's own small stage footprint.
const WALK_RANGE := 20.0
const CENTER_X := 0.0
const PEBBLE_X := -14.0
const PEBBLE_Y := 0.0


## The character/pebble's continuous pose at `t` (the caller loops this into
## [0, LOOP_DURATION] itself -- see event_at for the one-shot events).
## `loop_index` alternates throw vs. kick between consecutive loops.
func state_at(t: float, loop_index: int = 0) -> Dictionary:
	var clamped := clampf(t, 0.0, LOOP_DURATION)
	return {
		"character_x": _character_x_at(clamped),
		"facing": _facing_at(clamped),
		"movement_state": _movement_state_at(clamped),
		"pebble_position": _pebble_position_at(clamped, loop_index),
		"pebble_visible": _pebble_visible_at(clamped),
	}


func _character_x_at(t: float) -> float:
	if t < _WALK_BACK_START:
		return lerpf(CENTER_X, CENTER_X + WALK_RANGE, t / WALK_OUT_DURATION)
	if t < _SWING_START:
		return lerpf(CENTER_X + WALK_RANGE, CENTER_X, (t - _WALK_BACK_START) / WALK_BACK_DURATION)
	if t < _WALK_TO_PEBBLE_START:
		return CENTER_X
	if t < _PICKUP_START:
		return lerpf(CENTER_X, PEBBLE_X, (t - _WALK_TO_PEBBLE_START) / WALK_TO_PEBBLE_DURATION)
	if t < _RETURN_START:
		return PEBBLE_X
	return lerpf(PEBBLE_X, CENTER_X, (t - _RETURN_START) / RETURN_DURATION)


func _facing_at(t: float) -> Vector2:
	if t < _WALK_BACK_START:
		return Vector2.RIGHT
	if t < _SWING_START:
		return Vector2.LEFT
	if t < _WALK_TO_PEBBLE_START:
		return Vector2.DOWN
	if t < _RETURN_START:
		return Vector2.LEFT
	return Vector2.RIGHT


func _movement_state_at(t: float) -> int:
	var idle := (t >= _SWING_START and t < _WALK_TO_PEBBLE_START) or (t >= _PICKUP_START and t < _RETURN_START)
	return CharacterView.MovementState.IDLE if idle else CharacterView.MovementState.WALKING


func _pebble_visible_at(t: float) -> bool:
	return t < _PICKUP_START or t >= _THROW_OR_KICK_START


func _pebble_position_at(t: float, loop_index: int) -> Vector2:
	var origin := Vector2(PEBBLE_X, PEBBLE_Y)
	if t < _THROW_OR_KICK_START:
		return origin
	var landing := _landing_position(loop_index)
	if t >= _RETURN_START:
		return landing
	var progress := (t - _THROW_OR_KICK_START) / THROW_OR_KICK_DURATION
	return origin.lerp(landing, progress)


## Even loops throw it (arm release, HeldItemThrow's own real throw-distance
## kinematics); odd loops kick it (Kick's own real momentum-vs-mass
## kinematics) -- reusing the SAME landing math actual gameplay uses rather
## than inventing preview-only physics.
func _landing_position(loop_index: int) -> Vector2:
	var origin := Vector2(PEBBLE_X, PEBBLE_Y)
	if loop_index % 2 == 0:
		return origin + Vector2.LEFT * HeldItemThrow.throw_distance_px(THROW_POWER_FRACTION)
	var mass_kg := StoneSize.mass_kg_for(PEBBLE_DIAMETER_CM)
	return Kick.landing_position(Vector2(CENTER_X, PEBBLE_Y), origin, mass_kg)


## Edge-triggered one-shot: "" unless a phase boundary was crossed between
## `t_prev` and `t_now` (mirrors the just_pressed pattern player.gd uses
## throughout, e.g. _attack_step), in which case the caller should trigger
## that phase's one-time action exactly once. `loop_index` picks whether the
## pebble phase's event is "throw" or "kick".
func event_at(t_prev: float, t_now: float, loop_index: int = 0) -> String:
	if _crossed(t_prev, t_now, _SWING_START):
		return "swing"
	if _crossed(t_prev, t_now, _PICKUP_START):
		return "pickup"
	if _crossed(t_prev, t_now, _THROW_OR_KICK_START):
		return "throw" if loop_index % 2 == 0 else "kick"
	return ""


func _crossed(t_prev: float, t_now: float, boundary: float) -> bool:
	return t_prev < boundary and t_now >= boundary
