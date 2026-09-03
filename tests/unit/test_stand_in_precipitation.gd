extends GutTest

## docs/concept/hydrology.md "Implementation order" phase 1: until the
## climate grid exists, discharge comes from a placeholder rain curve over
## latitude alone -- the three-cell circulation flattened to one function
## (wet equator, dry subtropics, wet mid-latitudes, dry poles), the same
## shape climate_dynamics.md's baseline_pressure(latitude) describes.

const StandInPrecipitation = preload("res://src/world/stand_in_precipitation.gd")


func test_rain_is_within_zero_and_one_at_every_latitude():
	for tenth in range(-900, 901):
		var rain: float = StandInPrecipitation.at_latitude(tenth / 10.0)
		assert_between(rain, 0.0, 1.0)


func test_the_equator_is_wetter_than_the_subtropics():
	assert_gt(StandInPrecipitation.at_latitude(0.0), StandInPrecipitation.at_latitude(25.0))


func test_the_mid_latitudes_are_wetter_than_the_subtropics():
	assert_gt(StandInPrecipitation.at_latitude(55.0), StandInPrecipitation.at_latitude(25.0))


func test_the_poles_are_drier_than_the_mid_latitudes():
	assert_lt(StandInPrecipitation.at_latitude(90.0), StandInPrecipitation.at_latitude(55.0))


func test_the_subtropical_minimum_sits_in_the_desert_belt():
	# Real deserts cluster near 25-30 degrees on every continent.
	var driest_latitude := 0.0
	var driest := 2.0
	for degree in range(0, 46):
		var rain: float = StandInPrecipitation.at_latitude(float(degree))
		if rain < driest:
			driest = rain
			driest_latitude = float(degree)
	assert_between(driest_latitude, 20.0, 35.0)


func test_the_curve_is_symmetric_across_the_equator():
	for degree in range(0, 91, 5):
		assert_almost_eq(
			StandInPrecipitation.at_latitude(float(degree)),
			StandInPrecipitation.at_latitude(-float(degree)),
			1e-9
		)
