extends GutTest

## Snow instead of rain when it is cold, and snow lying on the ground (see
## docs/concept/weather.md).
##
## Rain falling on a frozen world is the same class of mistake as a canopy
## carrying apples under snow: the weather and the calendar not talking to each
## other.

const Snowfall = preload("res://src/world/snowfall.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- what falls --------------------------------------------------------------

func test_precipitation_falls_as_snow_when_it_is_cold():
	assert_true(Snowfall.falls_as_snow("rain", 0.0))
	assert_true(Snowfall.falls_as_snow("storm", 0.0))


func test_precipitation_falls_as_rain_when_it_is_warm():
	assert_false(Snowfall.falls_as_snow("rain", 1.0))
	assert_false(Snowfall.falls_as_snow("storm", 1.0))


## Dry weather is dry, however cold it is -- a clear frozen day is not a
## blizzard.
func test_clear_cold_weather_is_not_snow():
	for weather in ["clear", "cloudy"]:
		assert_false(Snowfall.falls_as_snow(weather, 0.0), weather)


## It is TEMPERATURE that decides, not the season name: a cold snap in autumn
## snows and a mild winter rains, which is what makes weather feel like weather
## rather than a label.
func test_temperature_decides_not_the_season():
	assert_true(Snowfall.falls_as_snow("rain", Snowfall.FREEZING_WARMTH - 0.01))
	assert_false(Snowfall.falls_as_snow("rain", Snowfall.FREEZING_WARMTH + 0.01))


## It does NOT snow on the blossom.
##
## Winter carries warmth 0.00-0.14 and the shoulder seasons run 0.15-0.85, and
## the threshold sat at 0.25 -- well into spring -- so it snowed in spring
## (reported). Measured against the season curve now rather than guessed.
func test_it_does_not_snow_in_an_ordinary_spring():
	var cycle := SeasonCycle.new()
	var year := SeasonCycle.SECONDS_PER_YEAR
	for step in 400:
		var t := float(step) / 399.0 * year
		if cycle.season_at(t) != "spring":
			continue
		# Mid-spring onward: the very first instant of spring is still the
		# tail of winter's cold and may legitimately snow.
		if cycle.warmth_modifier(t) < Snowfall.FREEZING_WARMTH:
			continue
		assert_false(
			Snowfall.falls_as_snow("rain", cycle.warmth_modifier(t)),
			"it snowed in spring at warmth %.2f" % cycle.warmth_modifier(t)
		)


## Never in summer, at any point.
func test_it_never_snows_in_summer():
	var cycle := SeasonCycle.new()
	var year := SeasonCycle.SECONDS_PER_YEAR
	for step in 400:
		var t := float(step) / 399.0 * year
		if cycle.season_at(t) != "summer":
			continue
		assert_false(Snowfall.falls_as_snow("storm", cycle.warmth_modifier(t)))


## Winter is cold enough to snow in, or the feature never fires.
func test_winter_is_cold_enough_to_snow():
	var cycle := SeasonCycle.new()
	var year := SeasonCycle.SECONDS_PER_YEAR
	var snowed := false
	for step in 200:
		var t := float(step) / 199.0 * year
		if cycle.season_at(t) != "winter":
			continue
		if Snowfall.falls_as_snow("rain", cycle.warmth_modifier(t)):
			snowed = true
	assert_true(snowed, "it should be able to snow in winter")


# -- it lies on the ground ---------------------------------------------------

## Snow ACCUMULATES: the ground gets whiter the longer it falls, rather than
## flicking between bare and covered.
## Non-decreasing all the way, and it reaches full cover.
##
## Asserted strictly increasing over twenty one-minute steps, which stopped
## holding the moment covering was made fast enough to finish inside a weather
## spell -- the last dozen steps are flat at full cover, which is correct
## behaviour, not a regression.
func test_snow_builds_up_while_it_falls():
	var depth := 0.0
	var previous := -1.0
	var step := Snowfall.SECONDS_TO_COVER / 20.0
	for _i in 20:
		depth = Snowfall.accumulate(depth, true, 0.0, step)
		assert_gte(depth, previous, "snow went backwards while falling")
		previous = depth
	assert_almost_eq(depth, 1.0, 0.001, "a full snowfall should reach full cover")


func test_snow_stops_building_at_full_cover():
	var depth := 0.0
	for step in 400:
		depth = Snowfall.accumulate(depth, true, 0.0, 60.0)
	assert_lte(depth, 1.0)
	assert_almost_eq(depth, 1.0, 0.001, "a long snowfall should fully cover the ground")


## And it MELTS when it warms up, so a thaw is something the player watches
## rather than a switch.
## Non-increasing all the way, and it reaches bare ground -- same reason as
## the build-up above.
func test_snow_melts_when_it_warms():
	var depth := 1.0
	var previous := 2.0
	var step := Snowfall.SECONDS_TO_THAW / 20.0
	for _i in 20:
		depth = Snowfall.accumulate(depth, false, 1.0, step)
		assert_lte(depth, previous, "snow deepened during a thaw")
		previous = depth
	assert_almost_eq(depth, 0.0, 0.001, "a full thaw should clear the ground")


func test_snow_does_not_melt_while_it_is_still_freezing():
	var depth := 0.5
	var held := Snowfall.accumulate(depth, false, 0.0, 60.0)
	assert_almost_eq(held, depth, 0.001, "snow should lie while it stays cold")


func test_melting_bottoms_out_at_bare_ground():
	var depth := 0.2
	for step in 200:
		depth = Snowfall.accumulate(depth, false, 1.0, 60.0)
	assert_eq(depth, 0.0)


## Covering has to FINISH inside a snowfall.
##
## These were 45 and 30 real minutes against a weather spell of ten, so a
## snowfall ended long before it could cover anything and the ground never went
## properly white (reported). The numbers were picked against "how long should
## a player watch this take" without checking what the weather would allow.
func test_the_ground_is_covered_before_the_snowfall_ends():
	assert_lte(
		Snowfall.SECONDS_TO_COVER, WeatherModel.WEATHER_PERIOD_SECONDS,
		"a snowfall must be able to cover the ground within one spell of weather"
	)


## ...and still take long enough to watch arrive.
func test_covering_still_takes_long_enough_to_watch():
	assert_gt(Snowfall.SECONDS_TO_COVER, WeatherModel.WEATHER_PERIOD_SECONDS * 0.25)


## Snow lingers after the cold does, so a thaw outlasts the fall that made it.
func test_a_thaw_outlasts_the_snowfall():
	assert_gt(Snowfall.SECONDS_TO_THAW, Snowfall.SECONDS_TO_COVER)


## Reported live: "increase the snow covering speed 20%". Speed is the
## INVERSE of SECONDS_TO_COVER (depth per second, not seconds per depth), so
## a 20% FASTER cover is 1/1.2 of the previous TIME, not the previous
## multiplier reduced by 20% -- 0.6 / 1.2 = 0.5 exactly, which is why the
## spell-fraction multiplier moved from 0.6 to 0.5 rather than to 0.48.
func test_covering_speed_was_increased_twenty_percent_over_the_previous_tuning():
	var previous_seconds_to_cover := WeatherModel.WEATHER_PERIOD_SECONDS * 0.6
	assert_almost_eq(
		previous_seconds_to_cover / Snowfall.SECONDS_TO_COVER, 1.2, 0.0001,
		"covering should now finish 20% faster (in 1/1.2 of the time) than the previous tuning"
	)


## A whole snowfall really does cover the ground.
func test_one_spell_of_snow_covers_bare_ground():
	var depth := 0.0
	var elapsed := 0.0
	while elapsed < WeatherModel.WEATHER_PERIOD_SECONDS:
		depth = Snowfall.accumulate(depth, true, 0.0, 10.0)
		elapsed += 10.0
	assert_almost_eq(depth, 1.0, 0.001, "a full spell of snow should cover the ground")


# -- it has to LOOK like snow ------------------------------------------------

## Snow is white, drifts rather than streaking, and falls far slower than rain.
## Reusing the rain overlay unchanged would give white rain, which reads as a
## recolour rather than as weather.
func test_snow_looks_and_falls_differently_from_rain():
	var RainOverlay := load("res://src/rendering/rain_overlay.gd")
	assert_gt(
		Snowfall.FLAKE_COLOR.v, RainOverlay.DROP_COLOR.v, "snow should be brighter than rain"
	)
	assert_lt(
		Snowfall.FLAKE_COLOR.s, RainOverlay.DROP_COLOR.s, "snow should be whiter than rain"
	)
	assert_lt(Snowfall.FLAKE_FALL_SPEED, RainOverlay.FALL_SPEED, "snow should fall slower")
	assert_lt(Snowfall.FLAKE_SLANT, RainOverlay.SLANT, "snow should drift, not slant")
