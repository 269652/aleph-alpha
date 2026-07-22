extends GutTest

const Sickness = preload("res://src/gameplay/sickness.gd")

var sickness: Sickness


func before_each():
	sickness = Sickness.new()


func test_infection_chance_increases_with_exposure_level_alone():
	var low := sickness.infection_chance(0.1, 0.5)
	var high := sickness.infection_chance(0.9, 0.5)
	assert_gt(high, low)


func test_infection_chance_decreases_with_resistance_alone():
	var low_resistance := sickness.infection_chance(0.5, 0.1)
	var high_resistance := sickness.infection_chance(0.5, 0.9)
	assert_gt(low_resistance, high_resistance)


func test_infection_chance_is_clamped_to_zero_and_one_at_extremes():
	var high := sickness.infection_chance(1.0, 0.0)
	var low := sickness.infection_chance(0.0, 1.0)
	assert_lte(high, 1.0)
	assert_gte(low, 0.0)
	assert_eq(low, 0.0)


func test_attempt_infect_is_deterministic_for_same_chance_and_seed():
	var first := sickness.attempt_infect(0.5, 42)
	var second := sickness.attempt_infect(0.5, 42)
	assert_eq(first, second)


func test_attempt_infect_with_zero_chance_never_succeeds():
	for seed_value in range(200):
		assert_false(sickness.attempt_infect(0.0, seed_value))


func test_attempt_infect_with_one_chance_always_succeeds():
	for seed_value in range(200):
		assert_true(sickness.attempt_infect(1.0, seed_value))


func test_progress_increases_severity_when_not_being_treated():
	var result := sickness.progress(0.3, 1.0, false)
	assert_gt(result, 0.3)


func test_progress_decreases_severity_when_being_treated():
	var result := sickness.progress(0.5, 1.0, true)
	assert_lt(result, 0.5)


func test_progress_clamps_at_zero():
	var result := sickness.progress(0.05, 10.0, true)
	assert_eq(result, 0.0)


func test_progress_clamps_at_one():
	var result := sickness.progress(0.95, 10.0, false)
	assert_eq(result, 1.0)


func test_is_recovered_true_at_and_below_zero_severity():
	assert_true(sickness.is_recovered(0.0))
	assert_true(sickness.is_recovered(-0.1))


func test_is_recovered_false_above_zero_severity():
	assert_false(sickness.is_recovered(0.01))


func test_diagnose_is_deterministic_for_same_inputs():
	var first := sickness.diagnose(0.6, 0.5, 7)
	var second := sickness.diagnose(0.6, 0.5, 7)
	assert_eq(first, second)


func test_diagnose_succeeds_more_often_at_higher_diagnosis_skill():
	var low_skill_successes := 0
	var high_skill_successes := 0
	var samples := 300
	for seed_value in range(samples):
		if sickness.diagnose(0.5, 0.1, seed_value):
			low_skill_successes += 1
		if sickness.diagnose(0.5, 0.9, seed_value):
			high_skill_successes += 1
	assert_gt(high_skill_successes, low_skill_successes)
