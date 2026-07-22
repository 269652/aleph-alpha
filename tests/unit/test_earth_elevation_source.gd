extends GutTest

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")

var source: EarthElevationSource


func before_each():
	source = EarthElevationSource.new()


func test_the_deepest_ocean_trench_has_very_low_elevation():
	# Mariana Trench, measured directly from the bundled asset at ~0.0431.
	assert_lt(source.elevation_at(11.0, 142.0), 0.1)


func test_the_highest_mountain_has_very_high_elevation():
	# Everest, measured directly from the bundled asset at ~0.9765.
	assert_gt(source.elevation_at(27.99, 86.92), 0.9)


func test_low_lying_land_is_close_to_the_sea_level_threshold():
	# Amazon basin, measured directly from the bundled asset at ~0.5647.
	assert_almost_eq(source.elevation_at(-3.0, -60.0), 0.5556, 0.05)


func test_open_ocean_is_below_sea_level():
	# Mid-Pacific, measured directly from the bundled asset at ~0.1882.
	assert_lt(source.elevation_at(0.0, -160.0), 0.5556)


func test_longitude_wraps_continuously_across_the_date_line():
	var just_west_of_the_date_line := source.elevation_at(0.0, 179.9)
	var just_east_of_the_date_line := source.elevation_at(0.0, -179.9)
	assert_almost_eq(just_west_of_the_date_line, just_east_of_the_date_line, 0.1)
