extends GutTest

const WeatherModel = preload("res://src/world/weather_model.gd")

var weather: WeatherModel

const KNOWN_STATES := ["clear", "cloudy", "rain", "storm"]


func before_each():
	weather = WeatherModel.new()


func test_weather_at_is_deterministic_for_the_same_day_and_region_seed():
	var first := weather.weather_at(10, 42)
	var second := weather.weather_at(10, 42)
	assert_eq(first, second)


func test_different_region_seeds_on_the_same_day_can_differ():
	var day := 5
	var results := {}
	for region_seed in range(60):
		results[weather.weather_at(day, region_seed)] = true
	assert_gt(results.size(), 1)


func test_different_days_for_the_same_region_can_differ():
	var region_seed := 7
	var results := {}
	for day in range(60):
		results[weather.weather_at(day, region_seed)] = true
	assert_gt(results.size(), 1)


func test_weather_at_only_ever_returns_a_known_state():
	for day in range(60):
		for region_seed in range(5):
			var state := weather.weather_at(day, region_seed)
			assert_true(KNOWN_STATES.has(state), "unexpected state: %s" % state)


func test_all_four_states_appear_across_enough_sampled_days():
	var seen := {}
	for day in range(60):
		seen[weather.weather_at(day, 1)] = true
	for state in KNOWN_STATES:
		assert_true(seen.has(state), "state never appeared: %s" % state)


func test_clear_is_the_most_common_state_across_many_samples():
	var counts := {"clear": 0, "cloudy": 0, "rain": 0, "storm": 0}
	var samples := 0
	for day in range(200):
		for region_seed in range(5):
			counts[weather.weather_at(day, region_seed)] += 1
			samples += 1
	for state in ["cloudy", "rain", "storm"]:
		assert_gt(counts["clear"], counts[state])


func test_movement_speed_modifier_clear_is_unmodified():
	assert_eq(weather.movement_speed_modifier("clear"), 1.0)


func test_movement_speed_modifier_cloudy_is_unmodified():
	assert_eq(weather.movement_speed_modifier("cloudy"), 1.0)


func test_movement_speed_modifier_storm_is_slower_than_rain_is_slower_than_normal():
	var rain_modifier := weather.movement_speed_modifier("rain")
	var storm_modifier := weather.movement_speed_modifier("storm")
	assert_lt(storm_modifier, rain_modifier)
	assert_lt(rain_modifier, 1.0)


func test_movement_speed_modifier_unrecognized_state_falls_back_to_no_effect():
	assert_eq(weather.movement_speed_modifier("blizzard"), 1.0)
	assert_eq(weather.movement_speed_modifier(""), 1.0)


func test_warmth_factor_is_colder_in_wet_weather():
	assert_eq(weather.warmth_factor("clear"), 1.0)
	assert_lt(weather.warmth_factor("rain"), weather.warmth_factor("cloudy"))
	assert_lt(weather.warmth_factor("storm"), weather.warmth_factor("rain"))
	for w in ["clear", "cloudy", "rain", "storm"]:
		assert_between(weather.warmth_factor(w), 0.0, 1.0)


func test_warmth_factor_unknown_state_is_neutral():
	assert_eq(weather.warmth_factor("not_a_weather"), 1.0)


## Drives water-shader pacing (see WaterShader wind_strength uniform): calm
## water on a clear day, progressively more energetic chop as weather worsens.
func test_wind_strength_increases_with_weather_severity():
	var clear := weather.wind_strength_for("clear")
	var cloudy := weather.wind_strength_for("cloudy")
	var rain := weather.wind_strength_for("rain")
	var storm := weather.wind_strength_for("storm")
	assert_lt(clear, cloudy)
	assert_lt(cloudy, rain)
	assert_lt(rain, storm)


func test_wind_strength_stays_within_a_sane_unit_ish_range():
	for w in KNOWN_STATES:
		assert_between(weather.wind_strength_for(w), 0.0, 2.0)


func test_wind_strength_unrecognized_state_falls_back_to_calm():
	assert_eq(weather.wind_strength_for("blizzard"), weather.wind_strength_for("clear"))


## Regression: "clear" is by far the most common weather (50% of rolls, see
## CLEAR_THRESHOLD), so it must reproduce WaterShader's original always-on
## pace (its old fixed scroll_speed, before this per-weather scaling existed
## at all) rather than throttle the common case down -- worse weather should
## ADD energy on top of that baseline, not have calm weather subtract from
## it. A too-low "clear" value previously made most water read as static
## (reported: "the water ripples are gone").
func test_clear_weather_matches_the_waters_original_always_on_pace():
	assert_almost_eq(weather.wind_strength_for("clear"), 1.0, 0.01)
