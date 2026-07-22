extends GutTest

const SolarPosition = preload("res://src/world/solar_position.gd")

var solar: SolarPosition


func before_each():
	solar = SolarPosition.new()


func test_equator_near_equinox_at_local_solar_noon_is_nearly_overhead():
	# day_of_year=80 (~March equinox), longitude=0 so UTC noon == local solar noon.
	var elevation := solar.elevation_degrees(0.0, 0.0, 80, 12.0)
	assert_gt(elevation, 85.0)


func test_summer_solstice_local_midnight_at_mid_latitude_is_below_horizon():
	# lat=45N, longitude=0, day_of_year=172 (~June solstice), UTC=0 == local solar midnight.
	var elevation := solar.elevation_degrees(45.0, 0.0, 172, 0.0)
	assert_lt(elevation, 0.0)


func test_late_evening_in_central_europe_is_below_horizon():
	# Germany: lat~51N, lon~10E. UTC 22:00 is well after sunset there year-round.
	var elevation := solar.elevation_degrees(51.0, 10.0, 172, 22.0)
	assert_lt(elevation, 0.0)


func test_opposite_longitudes_at_the_same_utc_moment_differ_in_elevation():
	var here := solar.elevation_degrees(30.0, 0.0, 80, 12.0)
	var opposite_side_of_the_planet := solar.elevation_degrees(30.0, 180.0, 80, 12.0)
	assert_ne(here, opposite_side_of_the_planet)


func test_sunlight_intensity_is_zero_when_the_sun_is_below_the_horizon():
	assert_eq(solar.sunlight_intensity(-10.0), 0.0)


func test_sunlight_intensity_is_maximal_when_the_sun_is_directly_overhead():
	assert_almost_eq(solar.sunlight_intensity(90.0), 1.0, 0.001)


func test_sunlight_intensity_increases_as_the_sun_climbs_higher():
	var lower := solar.sunlight_intensity(20.0)
	var higher := solar.sunlight_intensity(60.0)
	assert_gt(higher, lower)


func test_day_of_year_january_first_is_day_one():
	assert_eq(solar.day_of_year(2026, 1, 1), 1)


func test_day_of_year_december_31_in_a_non_leap_year_is_365():
	assert_eq(solar.day_of_year(2025, 12, 31), 365)


func test_day_of_year_december_31_in_a_leap_year_is_366():
	assert_eq(solar.day_of_year(2024, 12, 31), 366)


func test_day_of_year_march_first_accounts_for_february_29_in_leap_years():
	assert_eq(solar.day_of_year(2024, 3, 1), 61)
	assert_eq(solar.day_of_year(2025, 3, 1), 60)
