extends GutTest

## Pure timeline tests -- no scene tree needed (see the class's own doc
## comment). One phase boundary at a time, mirroring how this codebase
## tests its other pure choreography helpers (WeaponSwing, Kick).

const CharacterPreviewChoreographer = preload("res://src/rendering/character_preview_choreographer.gd")
const CharacterView = preload("res://scenes/character_view.gd")
const Kick = preload("res://src/gameplay/kick.gd")
const HeldItemThrow = preload("res://src/gameplay/held_item_throw.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

var choreo: CharacterPreviewChoreographer


func before_each():
	choreo = CharacterPreviewChoreographer.new()


# -- walking out and back, through the "grass" -------------------------------

func test_starts_at_center_facing_right_and_walking():
	var state := choreo.state_at(0.0)
	assert_almost_eq(state.character_x, CharacterPreviewChoreographer.CENTER_X, 0.01)
	assert_eq(state.facing, Vector2.RIGHT)
	assert_eq(state.movement_state, CharacterView.MovementState.WALKING)


func test_walks_out_to_the_right_partway_through_the_first_phase():
	var t := CharacterPreviewChoreographer.WALK_OUT_DURATION * 0.5
	var state := choreo.state_at(t)
	assert_gt(state.character_x, CharacterPreviewChoreographer.CENTER_X)
	assert_lt(state.character_x, CharacterPreviewChoreographer.CENTER_X + CharacterPreviewChoreographer.WALK_RANGE)
	assert_eq(state.movement_state, CharacterView.MovementState.WALKING)


func test_reaches_full_walk_range_at_the_end_of_the_first_phase():
	var t := CharacterPreviewChoreographer.WALK_OUT_DURATION
	var state := choreo.state_at(t)
	assert_almost_eq(
		state.character_x, CharacterPreviewChoreographer.CENTER_X + CharacterPreviewChoreographer.WALK_RANGE, 0.01
	)
	assert_eq(state.facing, Vector2.LEFT, "should already be facing back left for the return leg")


func test_walks_back_to_center_by_the_end_of_the_second_phase():
	var t := CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
	var state := choreo.state_at(t)
	assert_almost_eq(state.character_x, CharacterPreviewChoreographer.CENTER_X, 0.01)


# -- the idle sword swing -----------------------------------------------------

func test_stands_idle_facing_down_during_the_swing_phase():
	var t := CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION + 0.1
	var state := choreo.state_at(t)
	assert_eq(state.movement_state, CharacterView.MovementState.IDLE)
	assert_eq(state.facing, Vector2.DOWN)
	assert_almost_eq(state.character_x, CharacterPreviewChoreographer.CENTER_X, 0.01)


func test_swing_event_fires_exactly_once_at_the_swing_phase_boundary():
	var boundary: float = CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
	assert_eq(choreo.event_at(boundary - 0.01, boundary, 0), "swing")
	assert_eq(choreo.event_at(boundary, boundary + 0.5, 0), "", "must not re-fire once already past the boundary")
	assert_eq(choreo.event_at(boundary - 0.5, boundary - 0.2, 0), "", "must not fire before reaching the boundary")


# -- walking to the pebble and picking it up ---------------------------------

func test_walks_left_toward_the_pebble_after_the_swing():
	var swing_end: float = (
		CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
		+ CharacterPreviewChoreographer.SWING_DURATION
	)
	var state := choreo.state_at(swing_end + 0.1)
	assert_eq(state.facing, Vector2.LEFT)
	assert_eq(state.movement_state, CharacterView.MovementState.WALKING)
	assert_lt(state.character_x, CharacterPreviewChoreographer.CENTER_X)


func test_reaches_the_pebble_at_the_end_of_the_walk_to_pebble_phase():
	var t: float = (
		CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
		+ CharacterPreviewChoreographer.SWING_DURATION + CharacterPreviewChoreographer.WALK_TO_PEBBLE_DURATION
	)
	var state := choreo.state_at(t)
	assert_almost_eq(state.character_x, CharacterPreviewChoreographer.PEBBLE_X, 0.01)


func test_pebble_is_visible_and_at_rest_before_it_is_picked_up():
	var state := choreo.state_at(0.0)
	assert_true(state.pebble_visible)
	assert_almost_eq(state.pebble_position.x, CharacterPreviewChoreographer.PEBBLE_X, 0.01)


func test_pickup_event_fires_once_reaching_the_pebble():
	var boundary: float = (
		CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
		+ CharacterPreviewChoreographer.SWING_DURATION + CharacterPreviewChoreographer.WALK_TO_PEBBLE_DURATION
	)
	assert_eq(choreo.event_at(boundary - 0.01, boundary, 0), "pickup")


func test_pebble_becomes_hidden_once_picked_up():
	var boundary: float = (
		CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
		+ CharacterPreviewChoreographer.SWING_DURATION + CharacterPreviewChoreographer.WALK_TO_PEBBLE_DURATION
	)
	var state := choreo.state_at(boundary + 0.1)
	assert_false(state.pebble_visible)
	assert_eq(state.movement_state, CharacterView.MovementState.IDLE, "should stand still while holding it")


# -- throwing (even loops) or kicking (odd loops) it away --------------------

func _throw_or_kick_start() -> float:
	return (
		CharacterPreviewChoreographer.WALK_OUT_DURATION + CharacterPreviewChoreographer.WALK_BACK_DURATION
		+ CharacterPreviewChoreographer.SWING_DURATION + CharacterPreviewChoreographer.WALK_TO_PEBBLE_DURATION
		+ CharacterPreviewChoreographer.PICKUP_DURATION
	)


func test_throw_event_fires_on_an_even_loop():
	var boundary := _throw_or_kick_start()
	assert_eq(choreo.event_at(boundary - 0.01, boundary, 0), "throw")


func test_kick_event_fires_on_an_odd_loop():
	var boundary := _throw_or_kick_start()
	assert_eq(choreo.event_at(boundary - 0.01, boundary, 1), "kick")


func test_pebble_reappears_and_animates_toward_a_thrown_landing_spot():
	var boundary := _throw_or_kick_start()
	var just_after := choreo.state_at(boundary + 0.01, 0)
	assert_true(just_after.pebble_visible)

	var landing := Vector2(
		CharacterPreviewChoreographer.PEBBLE_X, CharacterPreviewChoreographer.PEBBLE_Y
	) + Vector2.LEFT * HeldItemThrow.throw_distance_px(CharacterPreviewChoreographer.THROW_POWER_FRACTION)
	var end_of_phase := choreo.state_at(boundary + CharacterPreviewChoreographer.THROW_OR_KICK_DURATION, 0)
	assert_almost_eq(end_of_phase.pebble_position.x, landing.x, 0.01)


func test_pebble_animates_toward_a_kicked_landing_spot_on_an_odd_loop():
	var boundary := _throw_or_kick_start()
	var mass_kg := StoneSize.mass_kg_for(CharacterPreviewChoreographer.PEBBLE_DIAMETER_CM)
	var landing := Kick.landing_position(
		Vector2(CharacterPreviewChoreographer.CENTER_X, CharacterPreviewChoreographer.PEBBLE_Y),
		Vector2(CharacterPreviewChoreographer.PEBBLE_X, CharacterPreviewChoreographer.PEBBLE_Y),
		mass_kg
	)
	var end_of_phase := choreo.state_at(boundary + CharacterPreviewChoreographer.THROW_OR_KICK_DURATION, 1)
	assert_almost_eq(end_of_phase.pebble_position.x, landing.x, 0.01)


# -- walking back to center, and the loop wrapping around --------------------

func test_walks_right_back_to_center_in_the_final_phase():
	var t := CharacterPreviewChoreographer.LOOP_DURATION - 0.1
	var state := choreo.state_at(t)
	assert_eq(state.facing, Vector2.RIGHT)
	assert_eq(state.movement_state, CharacterView.MovementState.WALKING)


func test_loop_ends_back_at_the_same_pose_it_started_with():
	var end_state := choreo.state_at(CharacterPreviewChoreographer.LOOP_DURATION)
	var start_state := choreo.state_at(0.0)
	assert_almost_eq(end_state.character_x, start_state.character_x, 0.01)
	assert_eq(end_state.facing, start_state.facing)
	assert_eq(end_state.movement_state, start_state.movement_state)


## The pebble itself DOES pop back to its origin at the seam (still sitting
## at its thrown/kicked landing spot through the end of one loop, but back
## at the start spot for the next) -- a deliberate "looping GIF" reset
## rather than an animated walk-back-to-fetch-it, the same simplification
## real gait/swim cycles in character_view.gd already make.
func test_pebble_resets_to_its_origin_at_the_start_of_the_next_loop():
	var end_of_loop := choreo.state_at(CharacterPreviewChoreographer.LOOP_DURATION, 0)
	assert_ne(end_of_loop.pebble_position.x, CharacterPreviewChoreographer.PEBBLE_X)

	var start_of_next_loop := choreo.state_at(0.0, 1)
	assert_almost_eq(start_of_next_loop.pebble_position.x, CharacterPreviewChoreographer.PEBBLE_X, 0.01)
	assert_true(start_of_next_loop.pebble_visible)
