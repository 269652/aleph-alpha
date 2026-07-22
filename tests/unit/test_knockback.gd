extends GutTest

const Knockback = preload("res://src/gameplay/knockback.gd")

var knockback: Knockback


func before_each():
	knockback = Knockback.new()


func test_a_single_full_duration_step_consumes_the_whole_displacement():
	var result := knockback.step(Vector2(30, 0), 0.15, 0.15)
	assert_eq(result.step, Vector2(30, 0))
	assert_eq(result.remaining, Vector2.ZERO)
	assert_eq(result.time_remaining, 0.0)


func test_a_partial_step_moves_only_part_of_the_way_and_leaves_a_remainder():
	var result := knockback.step(Vector2(30, 0), 0.15, 0.05)
	assert_gt(result.step.x, 0.0)
	assert_lt(result.step.x, 30.0)
	assert_gt(result.remaining.x, 0.0)
	assert_lt(result.remaining.x, 30.0)
	assert_almost_eq(result.time_remaining, 0.10, 0.001)


func test_repeated_steps_sum_to_the_full_original_displacement():
	var remaining := Vector2(40, -20)
	var time_remaining := 0.15
	var total_moved := Vector2.ZERO
	while time_remaining > 0.0:
		var result := knockback.step(remaining, time_remaining, 0.016)
		total_moved += result.step
		remaining = result.remaining
		time_remaining = result.time_remaining
	assert_almost_eq(total_moved.x, 40.0, 0.01)
	assert_almost_eq(total_moved.y, -20.0, 0.01)


func test_zero_time_remaining_produces_no_step():
	var result := knockback.step(Vector2(30, 0), 0.0, 0.016)
	assert_eq(result.step, Vector2.ZERO)
	assert_eq(result.remaining, Vector2.ZERO)


func test_zero_remaining_displacement_produces_no_step():
	var result := knockback.step(Vector2.ZERO, 0.1, 0.016)
	assert_eq(result.step, Vector2.ZERO)
	assert_eq(result.time_remaining, 0.0)


func test_a_delta_larger_than_time_remaining_still_only_consumes_what_is_left():
	var result := knockback.step(Vector2(30, 0), 0.05, 1.0)
	assert_eq(result.step, Vector2(30, 0))
	assert_eq(result.time_remaining, 0.0)
