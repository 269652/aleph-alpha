extends GutTest

const PetLoyalty = preload("res://src/gameplay/pet_loyalty.gd")

var loyalty_model: PetLoyalty


func before_each():
	loyalty_model = PetLoyalty.new()


func test_starts_at_documented_baseline():
	assert_eq(loyalty_model.BASELINE_LOYALTY, 0.5)


func test_feed_increases_loyalty():
	var result := loyalty_model.feed(0.5, 0.5)
	assert_gt(result, 0.5)


func test_feed_increase_is_proportional_to_food_quality():
	var low_quality_result := loyalty_model.feed(0.5, 0.2)
	var high_quality_result := loyalty_model.feed(0.5, 0.9)
	assert_gt(high_quality_result - 0.5, low_quality_result - 0.5)


func test_feed_clamps_at_one():
	var result := loyalty_model.feed(0.95, 1.0)
	assert_eq(result, 1.0)


func test_neglect_decreases_loyalty_over_time():
	var result := loyalty_model.neglect(0.5, 10.0)
	assert_lt(result, 0.5)


func test_neglect_decrease_is_proportional_to_delta():
	var short_result := loyalty_model.neglect(0.5, 1.0)
	var long_result := loyalty_model.neglect(0.5, 10.0)
	assert_lt(long_result, short_result)


func test_neglect_clamps_at_zero():
	var result := loyalty_model.neglect(0.05, 100.0)
	assert_eq(result, 0.0)


func test_will_follow_true_above_threshold():
	assert_true(loyalty_model.will_follow(loyalty_model.FOLLOW_THRESHOLD + 0.05))


func test_will_follow_false_below_threshold():
	assert_false(loyalty_model.will_follow(loyalty_model.FOLLOW_THRESHOLD - 0.05))


func test_will_guard_true_above_threshold():
	assert_true(loyalty_model.will_guard(loyalty_model.GUARD_THRESHOLD + 0.05))


func test_will_guard_false_below_threshold():
	assert_false(loyalty_model.will_guard(loyalty_model.GUARD_THRESHOLD - 0.05))


func test_guard_threshold_is_stricter_than_follow_threshold():
	assert_gt(loyalty_model.GUARD_THRESHOLD, loyalty_model.FOLLOW_THRESHOLD)


func test_loyalty_between_thresholds_follows_but_does_not_guard():
	var mid_loyalty := (loyalty_model.FOLLOW_THRESHOLD + loyalty_model.GUARD_THRESHOLD) / 2.0
	assert_true(loyalty_model.will_follow(mid_loyalty))
	assert_false(loyalty_model.will_guard(mid_loyalty))
