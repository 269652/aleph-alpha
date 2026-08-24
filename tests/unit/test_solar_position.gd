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


## Reported: "if a player from Japan has his character in Berlin, it's still
## GMT+2 for him" -- the displayed clock showed raw UTC regardless of the
## character's in-game longitude, even though elevation_degrees ALREADY
## computes the astronomically-correct local solar time internally
## (local_solar_time := utc_hour + longitude_deg / 15.0) purely for lighting.
## local_hour exposes that same formula so the displayed clock can use it
## too -- one source of truth for "what time is it here", not two.
func test_local_hour_at_zero_longitude_equals_utc():
	assert_almost_eq(solar.local_hour(12.0, 0.0), 12.0, 0.001)


## Berlin sits at roughly 13 degrees East -- close to but not exactly
## Germany's real civil GMT+2 (Germany spans a political timezone, not a
## point on the solar-longitude line), which is the honest, documented
## limitation: this approximates LOCAL SOLAR time from longitude, the same
## astronomy already driving lighting, not real political timezone
## boundaries (a whole separate, messier dataset this game doesn't carry).
func test_local_hour_east_of_greenwich_is_later_than_utc():
	var local := solar.local_hour(12.0, 13.4)
	assert_gt(local, 12.0)
	assert_almost_eq(local, 12.0 + 13.4 / 15.0, 0.001)


func test_local_hour_west_of_greenwich_is_earlier_than_utc():
	var local := solar.local_hour(12.0, -74.0)  # roughly New York's longitude
	assert_lt(local, 12.0)


## Must wrap into a real 0..24 clock face, not print "25:00" or "-1:00".
func test_local_hour_wraps_within_a_24_hour_clock():
	assert_almost_eq(solar.local_hour(23.0, 45.0), 2.0, 0.001)  # 23 + 3 -> 26 -> wraps to 2
	assert_almost_eq(solar.local_hour(1.0, -45.0), 22.0, 0.001)  # 1 - 3 -> -2 -> wraps to 22


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


# -- azimuth_degrees: real sun compass bearing, for hillshading (see terrain_relief.md) -

func test_azimuth_is_within_a_valid_compass_range():
	var azimuth := solar.azimuth_degrees(52.5, 13.4, 172, 10.0)
	assert_gte(azimuth, 0.0)
	assert_lt(azimuth, 360.0)


## Berlin-latitude, well before local solar noon -- the sun should still be
## in the eastern half of the sky (its compass bearing under 180, the
## north-through-east-to-south sweep), not yet past the meridian.
func test_sun_is_in_the_eastern_half_of_the_sky_in_the_morning_at_a_northern_mid_latitude():
	# longitude=0 so utc_hour IS local solar time; 8am is well before noon.
	var azimuth := solar.azimuth_degrees(52.5, 0.0, 172, 8.0)
	assert_lt(azimuth, 180.0)


func test_sun_is_in_the_western_half_of_the_sky_in_the_afternoon_at_a_northern_mid_latitude():
	var azimuth := solar.azimuth_degrees(52.5, 0.0, 172, 16.0)
	assert_gt(azimuth, 180.0)


func test_azimuth_sweeps_from_morning_toward_afternoon_over_the_course_of_a_day():
	var morning := solar.azimuth_degrees(52.5, 0.0, 172, 8.0)
	var afternoon := solar.azimuth_degrees(52.5, 0.0, 172, 16.0)
	assert_lt(morning, afternoon)


## Same shape as the existing elevation test just above it in this file --
## the real longitude correction (via local_hour) should carry through to
## azimuth exactly the way it already does for elevation.
func test_opposite_longitudes_at_the_same_utc_moment_can_differ_in_azimuth():
	var here := solar.azimuth_degrees(30.0, 0.0, 80, 12.0)
	var opposite_side_of_the_planet := solar.azimuth_degrees(30.0, 180.0, 80, 12.0)
	assert_ne(here, opposite_side_of_the_planet)
