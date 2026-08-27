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


# -- random_point_in_circle: the shared "anywhere inside a disc" sampler --
# pick_target's own Rect2 (a SQUARE) overshoots a circular boundary at its
# corners by a factor of sqrt(2) -- fine for the wander/tree bounds it was
# built for, but wrong for anything confined to a genuinely round area (a
# pond's own containment radius). CharacterPreviewLayout.generate() already
# had this exact sqrt-weighted-radius math inlined for the fish SPAWN
# positions; CharacterPreviewDiorama's ongoing fish TARGET picking used
# pick_target's square instead, letting a swimming fish's own wander
# target land up to 41% further from the pond's centre than its spawn ever
# could (reported live: "fish are still spawned on land").

func test_random_point_in_circle_never_lands_outside_the_radius():
	var center := Vector2(100, 50)
	var radius := 21.12
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _i in 200:
		var point: Vector2 = CharacterStroll.random_point_in_circle(center, radius, rng)
		assert_true(
			point.distance_to(center) <= radius,
			"point %s should be within %.2f of %s" % [point, radius, center]
		)


## A plain uniform radius (no sqrt correction) bunches points toward the
## centre, since a thin ring near the edge covers far more AREA than an
## equally-thin ring near the centre but a uniform radius roll samples both
## equally often -- sqrt(rng) corrects for that so points land evenly across
## the disc's own area. Checked by comparing how many landed in the inner
## vs outer half of the radius (by area, i.e. inner disc of radius/sqrt(2)
## -- exactly half the full disc's area) across enough samples that an even
## split is the only plausible outcome.
func test_random_point_in_circle_is_area_weighted_not_bunched_at_the_centre():
	var center := Vector2.ZERO
	var radius := 100.0
	var inner_radius := radius / sqrt(2.0)  # bounds exactly half the disc's area
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var inner_count := 0
	var total := 2000
	for _i in total:
		var point: Vector2 = CharacterStroll.random_point_in_circle(center, radius, rng)
		if point.distance_to(center) <= inner_radius:
			inner_count += 1
	var inner_fraction := float(inner_count) / float(total)
	assert_almost_eq(inner_fraction, 0.5, 0.06, "expected roughly half the points inside the equal-area inner radius")


func test_random_point_in_circle_is_deterministic_for_the_same_rng_seed():
	var center := Vector2(10, 10)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 9
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 9
	assert_eq(
		CharacterStroll.random_point_in_circle(center, 5.0, rng_a),
		CharacterStroll.random_point_in_circle(center, 5.0, rng_b)
	)
