extends RefCounted

## Deterministic per-day, per-region weather (concept/weather.md "Dynamic
## Weather System" / "Regional Weather Variety"): weather_at hashes day and
## region_seed together so neighboring regions can be in different weather
## states on the same simulated day, while the same (day, region_seed) pair
## always reproduces the same state.

## Cumulative probability thresholds over [0, 1) for weather_at's roll,
## checked in order: clear 50%, cloudy +25% (=75%), rain +20% (=95%),
## storm the remaining 5%.
const CLEAR_THRESHOLD := 0.5
const CLOUDY_THRESHOLD := 0.75
const RAIN_THRESHOLD := 0.95


## Deterministic weather state ("clear"/"cloudy"/"rain"/"storm") for a given
## simulated day and region.
func weather_at(day: int, region_seed: int) -> String:
	var roll := float(absi(hash("%d_%d_weather" % [day, region_seed])) % 10000) / 10000.0
	if roll < CLEAR_THRESHOLD:
		return "clear"
	if roll < CLOUDY_THRESHOLD:
		return "cloudy"
	if roll < RAIN_THRESHOLD:
		return "rain"
	return "storm"


## Multiplier applied to movement speed for a weather state: unaffected by
## clear/cloudy, slowed by rain, slowed further by storm. Unrecognized
## states fall back to 1.0 rather than erroring.
func movement_speed_modifier(weather: String) -> float:
	match weather:
		"rain":
			return 0.85
		"storm":
			return 0.65
		_:
			return 1.0


## How warm a weather state feels, [0,1] -- scales ambient warmth for the
## survival warmth meter (see SurvivalMeters.regulate_temperature). Clear is
## full warmth; overcast/wet weather is progressively colder. Unknown states
## are neutral (1.0).
func warmth_factor(weather: String) -> float:
	match weather:
		"cloudy":
			return 0.8
		"rain":
			return 0.55
		"storm":
			return 0.4
		_:
			return 1.0


## How energetic the water's GPU wave motion should feel for a weather state,
## [0,2]-ish -- scales WaterShader's effective wave speed (see
## EarthChunkManager.set_wind_strength). "clear" reproduces the water's
## original always-on pace (WaterShader's fixed scroll_speed, from before
## per-weather scaling existed) rather than throttling the common case down
## -- clear is the majority state (50% of rolls, see CLEAR_THRESHOLD), so a
## calmer-than-1.0 baseline there previously read as "the water stopped
## moving" for most of a play session. Worse weather instead ADDS energy on
## top of that baseline, progressively more hectic toward a storm.
## Unrecognized states fall back to the clear/baseline value.
func wind_strength_for(weather: String) -> float:
	match weather:
		"cloudy":
			return 1.15
		"rain":
			return 1.4
		"storm":
			return 1.8
		_:
			return 1.0
