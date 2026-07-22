extends GutTest

const Throwable = preload("res://src/gameplay/throwable.gd")

var throwable: Throwable


func before_each():
	throwable = Throwable.new()


func test_travel_time_scales_linearly_with_distance():
	var short_time := throwable.travel_time(10.0, 5.0)
	var long_time := throwable.travel_time(20.0, 5.0)
	assert_almost_eq(long_time, short_time * 2.0, 0.001)


func test_travel_time_is_distance_over_speed():
	assert_almost_eq(throwable.travel_time(10.0, 5.0), 2.0, 0.001)


func test_travel_time_guards_against_zero_speed():
	assert_eq(throwable.travel_time(10.0, 0.0), INF)


func test_travel_time_guards_against_negative_speed():
	assert_eq(throwable.travel_time(10.0, -3.0), INF)


func test_damage_at_distance_equals_base_damage_at_zero():
	assert_almost_eq(throwable.damage_at_distance(100.0, 0.0, 10.0), 100.0, 0.001)


func test_damage_at_distance_is_between_min_and_base_at_mid_range():
	var damage := throwable.damage_at_distance(100.0, 5.0, 10.0)
	assert_true(damage < 100.0)
	assert_true(damage > 20.0)


func test_damage_at_distance_hits_minimum_fraction_at_effective_range():
	assert_almost_eq(throwable.damage_at_distance(100.0, 10.0, 10.0), 20.0, 0.001)


func test_damage_at_distance_stays_at_minimum_beyond_effective_range():
	assert_almost_eq(throwable.damage_at_distance(100.0, 50.0, 10.0), 20.0, 0.001)


func test_damage_at_distance_does_not_drop_below_minimum_far_past_range():
	var damage := throwable.damage_at_distance(100.0, 1000.0, 10.0)
	assert_almost_eq(damage, 20.0, 0.001)


func test_impact_knockback_increases_with_mass_at_fixed_speed():
	var light := throwable.impact_knockback(1.0, 10.0)
	var heavy := throwable.impact_knockback(5.0, 10.0)
	assert_true(heavy > light)


func test_impact_knockback_increases_with_speed_at_fixed_mass():
	var slow := throwable.impact_knockback(2.0, 5.0)
	var fast := throwable.impact_knockback(2.0, 15.0)
	assert_true(fast > slow)
