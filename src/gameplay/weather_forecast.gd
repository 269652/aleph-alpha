extends RefCounted
## Reads weather_model.gd's own pure per-day hash function one period ahead
## -- docs/concept/wayfinding.md's Weather glass item. weather_at(day, seed)
## is a pure deterministic function of day, so "the next roll" is already a
## real, computable fact today -- this module adds no new state or
## randomness, it just calls the same real function at day+1.


## weather_model is duck-typed (any object exposing weather_at(day, seed))
## -- matches this project's own untyped-duck-typing precedent for
## cross-module params (see why.gd's explain_market's "market" param).
static func upcoming_weather(weather_model, current_day: int, region_seed: int) -> String:
	return weather_model.weather_at(current_day + 1, region_seed)


## "no change expected" if upcoming == current, else "<upcoming> likely"
## (deliberately vague timing -- instrument-grade uncertainty, not an
## exact-hour cheat-omniscient forecast, per the doc's own design pillar).
static func forecast_label(current: String, upcoming: String) -> String:
	if upcoming == current:
		return "no change expected"
	return "%s likely" % upcoming
