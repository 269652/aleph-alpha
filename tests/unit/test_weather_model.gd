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


# -- soil moisture (see docs/concept/soil_fauna.md) --------------------------
#
# How wet the GROUND is under a given sky, which is what drives earthworms up
# to the surface (and therefore whether a robin has anything to hunt). Kept
# here rather than in the worm sim itself: it is a property of weather, the
# same as warmth_factor and wind_strength_for already are.

func test_soil_moisture_increases_with_wetter_weather():
	assert_lt(weather.soil_moisture("clear"), weather.soil_moisture("cloudy"))
	assert_lt(weather.soil_moisture("cloudy"), weather.soil_moisture("rain"))
	assert_lt(weather.soil_moisture("rain"), weather.soil_moisture("storm"))


func test_soil_moisture_stays_in_unit_range():
	for w in KNOWN_STATES:
		assert_between(weather.soil_moisture(w), 0.0, 1.0)


## Clear is half of all weather rolls (see CLEAR_THRESHOLD). If dry ground
## were bone dry, worms -- and therefore every robin that hunts them -- would
## be invisible for most of a play session. Dry soil keeps a real baseline;
## rain multiplies it (see soil_fauna.md's surfacing drive).
func test_clear_weather_still_leaves_the_soil_somewhat_moist():
	assert_gt(weather.soil_moisture("clear"), 0.0)


func test_a_storm_soaks_the_ground_completely():
	assert_almost_eq(weather.soil_moisture("storm"), 1.0, 0.001)


func test_soil_moisture_unrecognized_state_falls_back_to_dry_baseline():
	assert_eq(weather.soil_moisture("blizzard"), weather.soil_moisture("clear"))


# -- forcing the weather (/weather) ------------------------------------------

## `/weather <state>` pins the sky so a weather-dependent thing can actually be
## looked at.
##
## Weather is a deterministic roll on the day and the region, which is right for
## the world and useless for inspection: to see snow settle you would otherwise
## have to wait for a rainy day to come round in winter. The override sits on
## the model rather than at the call sites so that EVERY reader agrees -- the
## rain overlay, soil moisture, wind strength and snowfall all reach weather
## through weather_at, and an override that only reached the overlay would give
## a downpour that never wet the ground.
func test_forcing_the_weather_overrides_the_roll():
	for state in KNOWN_STATES:
		weather.force_weather(state)
		assert_eq(weather.weather_at(1, 1), state)
		assert_eq(weather.weather_at(999, 4242), state, "every day and region agrees")


func test_clearing_the_override_restores_the_natural_roll():
	var natural := weather.weather_at(7, 11)
	weather.force_weather("storm")
	assert_eq(weather.weather_at(7, 11), "storm", "precondition")
	weather.clear_forced_weather()
	assert_eq(weather.weather_at(7, 11), natural)


func test_nothing_is_forced_to_begin_with():
	assert_false(weather.is_forced())
	weather.force_weather("rain")
	assert_true(weather.is_forced())
	weather.clear_forced_weather()
	assert_false(weather.is_forced())


## An unrecognised state is refused rather than pinning the sky to nonsense
## that every downstream `match` would then fall through.
func test_an_unknown_state_is_refused():
	assert_false(weather.force_weather("sunny"))
	assert_false(weather.is_forced())
	assert_true(weather.force_weather("clear"))
