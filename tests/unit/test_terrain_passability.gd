extends GutTest

const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")


# -- speed_multiplier: soft slowdown, real mountaineering-anchored thresholds ----

func test_gentle_slope_has_no_speed_penalty():
	assert_eq(TerrainPassability.speed_multiplier(0.0), 1.0)
	assert_eq(TerrainPassability.speed_multiplier(TerrainPassability.SOFT_THRESHOLD_DEG), 1.0)


func test_speed_penalty_grows_as_slope_steepens():
	var at_soft := TerrainPassability.speed_multiplier(TerrainPassability.SOFT_THRESHOLD_DEG + 1.0)
	var partway := TerrainPassability.speed_multiplier(
		(TerrainPassability.SOFT_THRESHOLD_DEG + TerrainPassability.HARD_THRESHOLD_DEG) / 2.0
	)
	var at_hard := TerrainPassability.speed_multiplier(TerrainPassability.HARD_THRESHOLD_DEG)
	assert_gt(at_soft, partway, "steeper should be slower")
	assert_gt(partway, at_hard, "steeper should be slower")


func test_speed_multiplier_reaches_its_floor_at_the_hard_threshold():
	assert_almost_eq(
		TerrainPassability.speed_multiplier(TerrainPassability.HARD_THRESHOLD_DEG),
		TerrainPassability.MIN_SPEED_MULTIPLIER,
		0.01
	)


func test_speed_multiplier_never_drops_below_its_floor_beyond_the_hard_threshold():
	assert_almost_eq(
		TerrainPassability.speed_multiplier(89.0), TerrainPassability.MIN_SPEED_MULTIPLIER, 0.01
	)


func test_speed_multiplier_never_exceeds_one_for_a_negative_or_zero_slope():
	assert_eq(TerrainPassability.speed_multiplier(0.0), 1.0)


# -- is_passable: hard refusal, and what a climbing rope actually buys ----------

func test_ordinary_hiking_slope_is_passable():
	assert_true(TerrainPassability.is_passable(10.0))


func test_a_slope_at_the_hard_threshold_is_not_passable_without_gear():
	assert_false(TerrainPassability.is_passable(TerrainPassability.HARD_THRESHOLD_DEG))


func test_a_slope_just_under_the_hard_threshold_is_still_passable():
	assert_true(TerrainPassability.is_passable(TerrainPassability.HARD_THRESHOLD_DEG - 0.1))


func test_climbing_gear_raises_the_passable_threshold():
	var slope := TerrainPassability.HARD_THRESHOLD_DEG + 5.0
	assert_false(
		TerrainPassability.is_passable(slope, false), "should still be blocked without gear"
	)
	assert_true(
		TerrainPassability.is_passable(slope, true), "a rope should open up moderately steeper terrain"
	)


func test_climbing_gear_does_not_make_genuinely_vertical_terrain_passable():
	assert_false(
		TerrainPassability.is_passable(TerrainPassability.HARD_THRESHOLD_WITH_ROPE_DEG, true),
		"a rope buys real additional steepness, not infinite steepness"
	)


func test_rope_threshold_is_strictly_steeper_than_the_bare_hand_threshold():
	assert_gt(TerrainPassability.HARD_THRESHOLD_WITH_ROPE_DEG, TerrainPassability.HARD_THRESHOLD_DEG)
