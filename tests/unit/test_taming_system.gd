extends GutTest

const TamingSystem = preload("res://src/gameplay/taming_system.gd")

var taming: TamingSystem


func before_each():
	taming = TamingSystem.new()


func test_calm_temperament_beats_aggressive_at_equal_health_and_food():
	var calm_chance := taming.taming_chance("calm", 0.5, 0.5)
	var aggressive_chance := taming.taming_chance("aggressive", 0.5, 0.5)
	assert_gt(calm_chance, aggressive_chance)


func test_lower_health_fraction_increases_chance():
	var weak_chance := taming.taming_chance("calm", 0.2, 0.5)
	var full_chance := taming.taming_chance("calm", 1.0, 0.5)
	assert_gt(weak_chance, full_chance)


func test_higher_food_quality_increases_chance():
	var good_food_chance := taming.taming_chance("calm", 0.5, 0.9)
	var poor_food_chance := taming.taming_chance("calm", 0.5, 0.1)
	assert_gt(good_food_chance, poor_food_chance)


func test_chance_is_clamped_to_zero_and_one_at_extremes():
	var high := taming.taming_chance("calm", 0.0, 1.0)
	var low := taming.taming_chance("aggressive", 1.0, 0.0)
	assert_lte(high, 1.0)
	assert_gte(low, 0.0)


func test_attempt_tame_is_deterministic_for_same_chance_and_seed():
	var first := taming.attempt_tame(0.5, 42)
	var second := taming.attempt_tame(0.5, 42)
	assert_eq(first, second)


func test_attempt_tame_with_zero_chance_never_succeeds():
	for seed_value in range(200):
		assert_false(taming.attempt_tame(0.0, seed_value))


func test_attempt_tame_with_one_chance_always_succeeds():
	for seed_value in range(200):
		assert_true(taming.attempt_tame(1.0, seed_value))


func test_attempt_tame_with_half_chance_succeeds_roughly_half_the_time():
	var successes := 0
	var total := 200
	for seed_value in range(total):
		if taming.attempt_tame(0.5, seed_value):
			successes += 1
	var fraction := float(successes) / total
	assert_almost_eq(fraction, 0.5, 0.15)


func test_temperament_alone_does_not_saturate_chance_at_extremes():
	# All three inputs must visibly matter -- temperament shouldn't already
	# be clamped to 0 or 1 before health/food are even factored in.
	var calm_chance := taming.taming_chance("calm", 0.5, 0.5)
	var aggressive_chance := taming.taming_chance("aggressive", 0.5, 0.5)
	assert_lt(calm_chance, 1.0)
	assert_gt(aggressive_chance, 0.0)


func test_unknown_temperament_falls_between_calm_and_aggressive():
	var calm_chance := taming.taming_chance("calm", 0.5, 0.5)
	var aggressive_chance := taming.taming_chance("aggressive", 0.5, 0.5)
	var unknown_chance := taming.taming_chance("neutral", 0.5, 0.5)
	assert_lt(unknown_chance, calm_chance)
	assert_gt(unknown_chance, aggressive_chance)
