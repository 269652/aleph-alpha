extends GutTest

const CharacterStroll = preload("res://src/rendering/character_stroll.gd")


func test_advance_moves_toward_the_target():
	var start := Vector2(0, 0)
	var target := Vector2(100, 0)
	var moved := CharacterStroll.advance(start, target, 1.0, 10.0)
	assert_almost_eq(moved.x, 10.0, 0.01)
	assert_almost_eq(moved.y, 0.0, 0.01)


func test_advance_moves_along_a_diagonal_at_the_given_speed():
	var start := Vector2(0, 0)
	var target := Vector2(100, 100)
	var moved := CharacterStroll.advance(start, target, 1.0, 10.0)
	# Speed is the magnitude of travel, not per-axis -- a diagonal step
	# covers 10 units of actual distance, not 10 on each axis.
	assert_almost_eq(start.distance_to(moved), 10.0, 0.01)


func test_advance_never_overshoots_the_target():
	var start := Vector2(0, 0)
	var target := Vector2(5, 0)
	# A single huge step (delta * speed = 100) must land exactly ON the
	# target, not fly past it.
	var moved := CharacterStroll.advance(start, target, 1.0, 100.0)
	assert_eq(moved, target)


func test_advance_returns_the_target_unchanged_once_already_there():
	var target := Vector2(42, 17)
	var moved := CharacterStroll.advance(target, target, 1.0, 10.0)
	assert_eq(moved, target)


func test_has_arrived_is_false_while_still_far_from_the_target():
	assert_false(CharacterStroll.has_arrived(Vector2(0, 0), Vector2(50, 0)))


func test_has_arrived_is_true_within_the_arrival_radius():
	var target := Vector2(50, 50)
	var close := target + Vector2(CharacterStroll.ARRIVAL_RADIUS * 0.5, 0)
	assert_true(CharacterStroll.has_arrived(close, target))


func test_has_arrived_is_true_exactly_at_the_target():
	var target := Vector2(50, 50)
	assert_true(CharacterStroll.has_arrived(target, target))


func test_pick_target_stays_within_bounds():
	var bounds := Rect2(Vector2(10, 20), Vector2(30, 40))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in 50:
		var target: Vector2 = CharacterStroll.pick_target(bounds, rng)
		assert_true(bounds.has_point(target), "target %s should be inside %s" % [target, bounds])


func test_pick_target_is_deterministic_for_the_same_rng_seed():
	var bounds := Rect2(Vector2(0, 0), Vector2(50, 50))
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 7
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	assert_eq(CharacterStroll.pick_target(bounds, rng_a), CharacterStroll.pick_target(bounds, rng_b))
