extends GutTest

const CreatureWander = preload("res://src/rendering/creature_wander.gd")

var wander: CreatureWander


func before_each():
	wander = CreatureWander.new()


func test_direction_is_a_unit_vector():
	var direction := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 42)
	assert_almost_eq(direction.length(), 1.0, 0.001)


func test_roam_direction_is_a_unit_vector():
	assert_almost_eq(wander.roam_direction(0.0, 42).length(), 1.0, 0.001)


func test_roam_direction_is_stable_within_a_change_interval_and_ignores_home():
	# Unlike direction_at, roam has no home bias -- it's a free exploration
	# heading, the same for any position within a given interval.
	var early := wander.roam_direction(0.1, 7)
	var late := wander.roam_direction(CreatureWander.DIRECTION_CHANGE_INTERVAL - 0.1, 7)
	assert_eq(early, late)


func test_roam_direction_changes_between_intervals():
	var first := wander.roam_direction(0.0, 7)
	var second := wander.roam_direction(CreatureWander.DIRECTION_CHANGE_INTERVAL * 3.0, 7)
	assert_ne(first, second)


func test_direction_is_deterministic_for_the_same_inputs():
	var first := wander.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	var second := wander.direction_at(Vector2(10, 10), Vector2(12, 8), 3.5, 7)
	assert_eq(first, second)


func test_direction_changes_between_distinct_seeds():
	var a := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 1)
	var b := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.0, 2)
	assert_ne(a, b)


func test_direction_is_stable_within_one_change_interval():
	var early := wander.direction_at(Vector2.ZERO, Vector2.ZERO, 0.1, 7)
	var late := wander.direction_at(Vector2.ZERO, Vector2.ZERO, CreatureWander.DIRECTION_CHANGE_INTERVAL - 0.1, 7)
	assert_eq(early, late)


func test_direction_biases_back_toward_home_once_far_enough_away():
	var home := Vector2.ZERO
	var far_away := Vector2(CreatureWander.WANDER_RADIUS * 3, 0)
	var direction := wander.direction_at(home, far_away, 0.0, 7)
	# Should point roughly back toward home (negative x), regardless of the
	# pseudo-random seed that would otherwise pick an arbitrary direction.
	assert_lt(direction.x, 0.0)


func test_step_position_moves_by_speed_times_delta():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var next := wander.step_position(home, current, 0.0, 1.0, 7)
	assert_almost_eq(next.distance_to(current), CreatureWander.WANDER_SPEED, 0.001)


func test_step_position_never_strands_far_beyond_the_wander_radius():
	var home := Vector2.ZERO
	var current := Vector2.ZERO
	var elapsed := 0.0
	for i in 200:
		current = wander.step_position(home, current, elapsed, 0.5, 7)
		elapsed += 0.5
	# The home-bias should keep it roughly bounded, not drifting away forever.
	assert_lt(current.distance_to(home), CreatureWander.WANDER_RADIUS * 2.0)
