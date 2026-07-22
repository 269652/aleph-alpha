extends GutTest

const ClimateModel = preload("res://src/world/climate_model.gd")

var climate: ClimateModel


func before_each():
	climate = ClimateModel.new()


func test_equator_at_sea_level_is_hottest():
	var temperature := climate.temperature_at(0.0, 0.0)
	assert_almost_eq(temperature, 1.0, 0.01)


func test_pole_at_sea_level_is_coldest():
	var temperature := climate.temperature_at(1.0, 0.0)
	assert_almost_eq(temperature, 0.0, 0.01)


func test_higher_elevation_is_colder_than_sea_level_at_the_same_latitude():
	var sea_level_temp := climate.temperature_at(0.3, 0.0)
	var mountain_temp := climate.temperature_at(0.3, 1.0)
	assert_lt(mountain_temp, sea_level_temp)


func test_temperature_stays_within_zero_and_one_at_the_extremes():
	var temperature := climate.temperature_at(1.0, 1.0)
	assert_between(temperature, 0.0, 1.0)
