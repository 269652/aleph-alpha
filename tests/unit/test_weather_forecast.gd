extends GutTest

## WeatherForecast: reads weather_model.gd's own pure per-day hash function
## one period ahead (see docs/concept/wayfinding.md's Weather glass section)
## -- no new state or randomness, just the same real weather_at called at
## day+1.

const WeatherForecast = preload("res://src/gameplay/weather_forecast.gd")
const WeatherModel = preload("res://src/world/weather_model.gd")


# -- upcoming_weather: the real day+1 roll from the real WeatherModel -------

func test_upcoming_weather_reads_the_real_next_day_roll_when_unchanged():
	var weather_model := WeatherModel.new()
	# Confirmed by hand: weather_at(1, 1) == "clear", weather_at(2, 1) == "clear".
	assert_eq(weather_model.weather_at(1, 1), "clear")
	assert_eq(weather_model.weather_at(2, 1), "clear")
	assert_eq(WeatherForecast.upcoming_weather(weather_model, 1, 1), "clear")


func test_upcoming_weather_reads_the_real_next_day_roll_when_changing():
	var weather_model := WeatherModel.new()
	# Confirmed by hand: weather_at(1, 42) == "clear", weather_at(2, 42) == "cloudy".
	assert_eq(weather_model.weather_at(1, 42), "clear")
	assert_eq(weather_model.weather_at(2, 42), "cloudy")
	assert_eq(WeatherForecast.upcoming_weather(weather_model, 1, 42), "cloudy")


# -- forecast_label: instrument-grade vagueness, not an exact-hour cheat ----

func test_forecast_label_when_upcoming_matches_current():
	assert_eq(WeatherForecast.forecast_label("clear", "clear"), "no change expected")


func test_forecast_label_when_upcoming_differs_from_current():
	assert_eq(WeatherForecast.forecast_label("clear", "storm"), "storm likely")
