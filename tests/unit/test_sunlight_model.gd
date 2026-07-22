extends GutTest

const SunlightModel = preload("res://src/world/sunlight_model.gd")

var sunlight: SunlightModel


func before_each():
	sunlight = SunlightModel.new()


func test_intensity_is_zero_at_midnight_at_the_equator():
	assert_eq(sunlight.intensity_at(0.0, 0.0), 0.0)


func test_intensity_is_maximum_at_noon_at_the_equator():
	assert_almost_eq(sunlight.intensity_at(0.5, 0.0), 1.0, 0.01)


func test_noon_intensity_is_lower_at_the_poles_than_at_the_equator():
	var equator_noon := sunlight.intensity_at(0.5, 0.0)
	var pole_noon := sunlight.intensity_at(0.5, 1.0)
	assert_lt(pole_noon, equator_noon)


func test_intensity_never_goes_negative_at_night_at_the_poles():
	assert_eq(sunlight.intensity_at(0.0, 1.0), 0.0)


func test_intensity_curve_is_symmetric_around_noon():
	var before_noon := sunlight.intensity_at(0.4, 0.0)
	var after_noon := sunlight.intensity_at(0.6, 0.0)
	assert_almost_eq(before_noon, after_noon, 0.01)
