extends GutTest

const WeaponSwing = preload("res://src/gameplay/weapon_swing.gd")

var swing: WeaponSwing


func before_each():
	swing = WeaponSwing.new()


func test_swing_starts_and_ends_at_the_base_orientation_offset_by_the_amplitude():
	# A pendulum swing: progress 0 -> base - amplitude, progress 1 -> base + amplitude.
	var start := swing.rotation_at(0.0, "right")
	var end := swing.rotation_at(1.0, "right")
	assert_almost_eq(start, 0.0 - WeaponSwing.AMPLITUDE, 0.01)
	assert_almost_eq(end, 0.0 + WeaponSwing.AMPLITUDE, 0.01)


func test_midpoint_of_the_swing_is_at_the_base_orientation():
	assert_almost_eq(swing.rotation_at(0.5, "right"), 0.0, 0.01)
	assert_almost_eq(swing.rotation_at(0.5, "down"), PI / 2.0, 0.01)


func test_left_and_right_are_horizontal_and_face_opposite_base_orientations():
	assert_almost_eq(swing.rotation_at(0.5, "right"), 0.0, 0.01)
	assert_almost_eq(swing.rotation_at(0.5, "left"), PI, 0.01)


func test_up_and_down_are_vertical_and_face_opposite_base_orientations():
	assert_almost_eq(swing.rotation_at(0.5, "down"), PI / 2.0, 0.01)
	assert_almost_eq(swing.rotation_at(0.5, "up"), -PI / 2.0, 0.01)


func test_unknown_facing_falls_back_to_a_valid_angle_rather_than_crashing():
	var angle := swing.rotation_at(0.5, "sideways")
	assert_true(is_finite(angle))


func test_progress_is_clamped_to_the_0_to_1_range():
	var below := swing.rotation_at(-1.0, "right")
	var at_zero := swing.rotation_at(0.0, "right")
	assert_almost_eq(below, at_zero, 0.01)

	var above := swing.rotation_at(2.0, "right")
	var at_one := swing.rotation_at(1.0, "right")
	assert_almost_eq(above, at_one, 0.01)
