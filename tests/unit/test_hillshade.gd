extends GutTest

const Hillshade = preload("res://src/rendering/hillshade.gd")


func test_illumination_is_zero_when_the_sun_is_below_the_horizon():
	assert_eq(Hillshade.illumination(20.0, 90.0, -5.0, 180.0), 0.0)
	assert_eq(Hillshade.illumination(20.0, 90.0, 0.0, 180.0), 0.0)


## On perfectly flat ground, aspect is meaningless (see terrain_relief.gd's
## own -1 "undefined" convention) -- illumination must not depend on it at
## all, only on how high the sun is.
func test_flat_ground_illumination_depends_only_on_sun_elevation_not_aspect():
	var one_aspect := Hillshade.illumination(0.0, 45.0, 30.0, 180.0)
	var another_aspect := Hillshade.illumination(0.0, 270.0, 30.0, 180.0)
	var undefined_aspect := Hillshade.illumination(0.0, -1.0, 30.0, 180.0)
	assert_almost_eq(one_aspect, another_aspect, 0.0001)
	assert_almost_eq(one_aspect, undefined_aspect, 0.0001)


func test_flat_ground_illumination_matches_sunlight_intensitys_own_formula():
	# Same "sin(elevation)" shape SolarPosition.sunlight_intensity already
	# uses for flat, unslanted ground -- both describe the same physical
	# quantity (direct light on a horizontal surface), so they must agree.
	var illumination := Hillshade.illumination(0.0, 0.0, 30.0, 0.0)
	assert_almost_eq(illumination, sin(deg_to_rad(30.0)), 0.001)


func test_a_slope_facing_the_sun_is_brighter_than_the_same_slope_facing_away():
	var sun_azimuth := 180.0
	var facing_sun := Hillshade.illumination(40.0, sun_azimuth, 30.0, sun_azimuth)
	var facing_away := Hillshade.illumination(40.0, sun_azimuth + 180.0, 30.0, sun_azimuth)
	assert_gt(facing_sun, facing_away)


func test_a_slope_facing_the_sun_is_brighter_than_flat_ground_under_a_low_sun():
	# The real "mountainside lights up at sunrise" effect: a slope tilted
	# TOWARD a low sun catches more direct light than flat ground does.
	var sun_elevation := 10.0
	var sun_azimuth := 90.0
	var flat := Hillshade.illumination(0.0, -1.0, sun_elevation, sun_azimuth)
	var tilted_toward_sun := Hillshade.illumination(45.0, sun_azimuth, sun_elevation, sun_azimuth)
	assert_gt(tilted_toward_sun, flat)


func test_illumination_never_exceeds_one():
	# Sun nearly overhead, slope facing it directly.
	assert_lte(Hillshade.illumination(10.0, 90.0, 89.0, 90.0), 1.0)


func test_illumination_never_drops_below_zero():
	# A steep slope facing directly AWAY from a low sun -- self-shadowed.
	assert_gte(Hillshade.illumination(80.0, 270.0, 10.0, 90.0), 0.0)


func test_illumination_is_deterministic():
	var a := Hillshade.illumination(35.0, 120.0, 40.0, 200.0)
	var b := Hillshade.illumination(35.0, 120.0, 40.0, 200.0)
	assert_eq(a, b)
