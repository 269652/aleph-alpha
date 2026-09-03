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


## Whether a basin holds water at all in the stand-in: its catchment's
## accumulated rain per lake cell against the evaporation a cell of open
## water loses. First playtest: "ponds don't spawn everywhere -- just
## where water flows and rain accumulates".
func test_a_basin_holds_water_only_when_its_catchment_out_delivers_evaporation():
	var threshold: float = StandInPrecipitation.LAKE_MIN_INFLOW_PER_CELL
	assert_true(StandInPrecipitation.lake_holds_water(threshold * 10.0, 10))
	assert_false(StandInPrecipitation.lake_holds_water(threshold * 5.0, 10))
	assert_false(StandInPrecipitation.lake_holds_water(0.0, 1))


func test_a_desert_pocket_dries_out_and_a_humid_basin_of_the_same_size_does_not():
	# Same 4-cell basin fed by a 4-cell catchment: at the subtropical
	# minimum the inflow is a trickle; at the equator it is plenty.
	var desert_inflow: float = 4.0 * StandInPrecipitation.at_latitude(StandInPrecipitation.SUBTROPICAL_DRY_LATITUDE)
	var humid_inflow: float = 4.0 * StandInPrecipitation.at_latitude(0.0)
	assert_false(StandInPrecipitation.lake_holds_water(desert_inflow, 4))
	assert_true(StandInPrecipitation.lake_holds_water(humid_inflow, 4))


func test_the_curve_is_symmetric_across_the_equator():
	for degree in range(0, 91, 5):
		assert_almost_eq(
			StandInPrecipitation.at_latitude(float(degree)),
			StandInPrecipitation.at_latitude(-float(degree)),
			1e-9
		)
