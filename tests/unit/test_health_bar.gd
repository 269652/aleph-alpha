extends GutTest

const HealthBar = preload("res://src/gameplay/health_bar.gd")

var bar: HealthBar


func before_each():
	bar = HealthBar.new()


func test_full_health_fills_the_whole_bar():
	assert_almost_eq(bar.fill_width(20.0, 20.0, 14.0), 14.0, 0.001)


func test_zero_health_fills_nothing():
	assert_almost_eq(bar.fill_width(0.0, 20.0, 14.0), 0.0, 0.001)


func test_half_health_fills_half_the_bar():
	assert_almost_eq(bar.fill_width(10.0, 20.0, 14.0), 7.0, 0.001)


func test_health_above_max_clamps_to_the_full_bar():
	assert_almost_eq(bar.fill_width(999.0, 20.0, 14.0), 14.0, 0.001)


func test_zero_max_health_does_not_crash_and_fills_nothing():
	assert_almost_eq(bar.fill_width(0.0, 0.0, 14.0), 0.0, 0.001)
