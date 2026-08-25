extends GutTest

## Compass: pure bearing math (see docs/concept/wayfinding.md's Compass
## section). North is this world's own fixed +Y axis, not a simulated
## magnetic field -- these tests pin the compass-rose convention
## (0=N/+Y, 90=E/+X, 180=S/-Y, 270=W/-X, clockwise-positive) and the
## rough/fine quality-axis reading behavior.

const Compass = preload("res://src/gameplay/compass.gd")


# -- bearing_degrees: compass-rose convention, clockwise-positive, direction-only

func test_bearing_due_north_from_origin_is_zero_degrees():
	var bearing := Compass.bearing_degrees(Vector2.ZERO, Vector2(0, 10))
	assert_almost_eq(bearing, 0.0, 0.001)


func test_bearing_due_east_from_origin_is_ninety_degrees():
	var bearing := Compass.bearing_degrees(Vector2.ZERO, Vector2(10, 0))
	assert_almost_eq(bearing, 90.0, 0.001)


func test_bearing_due_south_from_origin_is_one_eighty_degrees():
	var bearing := Compass.bearing_degrees(Vector2.ZERO, Vector2(0, -10))
	assert_almost_eq(bearing, 180.0, 0.001)


func test_bearing_due_west_from_origin_is_two_seventy_degrees():
	var bearing := Compass.bearing_degrees(Vector2.ZERO, Vector2(-10, 0))
	assert_almost_eq(bearing, 270.0, 0.001)


func test_bearing_is_direction_only_not_distance_dependent():
	var from := Vector2(5, 5)
	var near_bearing := Compass.bearing_degrees(from, from + Vector2(1, 1))
	var far_bearing := Compass.bearing_degrees(from, from + Vector2(100, 100))
	assert_almost_eq(near_bearing, far_bearing, 0.001)


func test_bearing_from_a_nonorigin_player_position_reads_correctly():
	var bearing := Compass.bearing_degrees(Vector2(3, 3), Vector2(3, 13))
	assert_almost_eq(bearing, 0.0, 0.001)


# -- rough_reading: snaps to the nearest of the 8 compass points (45 degree steps)

func test_rough_reading_snaps_exact_cardinal_to_itself():
	assert_almost_eq(Compass.rough_reading(90.0), 90.0, 0.001)


func test_rough_reading_snaps_a_near_boundary_angle_to_the_correct_neighbor():
	# 46 degrees is just past the 22.5-degree N/NE boundary's midpoint
	# between 45 (NE) and 90 (E) -- nearest 45-degree step is 45.
	assert_almost_eq(Compass.rough_reading(46.0), 45.0, 0.001)
	# 68 degrees is closer to 90 (E) than to 45 (NE).
	assert_almost_eq(Compass.rough_reading(68.0), 90.0, 0.001)


func test_rough_reading_wraps_three_sixty_to_zero_not_three_sixty():
	# 359 degrees is nearest to the 360-degree step, which must read as 0.
	assert_almost_eq(Compass.rough_reading(359.0), 0.0, 0.001)


# -- fine_reading: identity, exact bearing, no snapping

func test_fine_reading_returns_the_exact_value_unchanged():
	assert_almost_eq(Compass.fine_reading(137.25), 137.25, 0.001)


# -- reading_for: dispatches to fine_reading or rough_reading

func test_reading_for_dispatches_to_rough_reading_when_not_fine():
	assert_almost_eq(Compass.reading_for(68.0, false), 90.0, 0.001)


func test_reading_for_dispatches_to_fine_reading_when_fine():
	assert_almost_eq(Compass.reading_for(68.0, true), 68.0, 0.001)
