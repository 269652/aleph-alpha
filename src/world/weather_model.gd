extends RefCounted

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")

## Deterministic per-day, per-region weather (concept/weather.md "Dynamic
## Weather System" / "Regional Weather Variety"): weather_at hashes day and
## region_seed together so neighboring regions can be in different weather
## states on the same simulated day, while the same (day, region_seed) pair
## always reproduces the same state.

## Cumulative probability thresholds over [0, 1) for weather_at's roll,
## checked in order: clear 50%, cloudy +25% (=75%), rain +20% (=95%),
## storm the remaining 5%.
## How long one weather spell lasts.
##
## Named here, with the weather, rather than only inside the chunk manager that
## divides by it -- anything reasoning about how long a rain or a snowfall gets
## to act needs this number, and a second copy of it would drift.
const WEATHER_PERIOD_SECONDS := 600.0

const CLEAR_THRESHOLD := 0.5
const CLOUDY_THRESHOLD := 0.75
const RAIN_THRESHOLD := 0.95


## Every weather state the model can be in. Named here so an override can be
## checked against the list rather than pinning the sky to something every
## downstream `match` would fall through.
const STATES := ["clear", "cloudy", "rain", "storm"]

## A weather state pinned by /weather, or "" for the natural roll.
##
## The override lives on the MODEL rather than at the call sites so that every
## reader agrees. The rain overlay, soil moisture, wind strength and snowfall
## all reach weather through weather_at; an override that only reached the
## overlay would give a downpour that never wet the ground.
var _forced := ""


## Pins the weather to `state`. Returns whether it was a state we have.
func force_weather(state: String) -> bool:
	if not STATES.has(state):
		return false
	_forced = state
	return true


func clear_forced_weather() -> void:
	_forced = ""


func is_forced() -> bool:
	return _forced != ""


func forced_weather() -> String:
	return _forced


## Deterministic weather state ("clear"/"cloudy"/"rain"/"storm") for a given
## simulated day and region -- unless /weather has pinned one.
func weather_at(day: int, region_seed: int) -> String:
	if _forced != "":
		return _forced
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


## How wet the SOIL is under a given sky, [0,1] -- the input that drives
## earthworms up to the surface, and therefore whether a robin has anything to
## hunt (see EarthwormPatch.surface_drive / docs/concept/soil_fauna.md). Wet
## soil lets a worm respire and move above ground without desiccating; drying
## soil sends it back down, which is the real reason robins famously forage
## after rain.
##
## Clear deliberately keeps a real baseline rather than going to zero: it is
## half of all weather rolls (see CLEAR_THRESHOLD), and a mechanic the player
## only ever sees during rain is a mechanic they mostly never see. Dry ground
## still holds some worms near the surface; rain multiplies how many.
## Unrecognized states fall back to that dry baseline.
func soil_moisture(weather: String) -> float:
	match weather:
		"cloudy":
			return 0.5
		"rain":
			return 0.85
		"storm":
			return 1.0
		_:
			return 0.25


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


## ## Which way the wind blows
##
## Varies day to day rather than being a fixed prevailing wind: one that never
## turned would drive every meadow in the world in one direction forever, and a
## meadow that only ever creeps north-east reads as a bug rather than as
## weather.
##
## Derived from the day and the region, like everything else here, so every
## plant dispersing on the same day in the same place agrees about the wind
## without anything being passed between them.
##
## How far the direction can swing from one day to the next. A wind that
## reversed nightly would average out to no wind at all over a season, which is
## the same as not simulating it; a wind that barely moved would be the fixed
## prevailing wind this exists to avoid.
const WIND_TURN_PER_DAY := 0.9


func wind_direction_for(day: int, region_seed: int) -> Vector2:
	# A slow walk rather than an independent roll per day: weather turns, it
	# does not teleport, and a seed shed on consecutive days should mostly go
	# the same way.
	var walk := 0.0
	for step in maxi(day, 0) + 1:
		var turn := float(PixelNoise.range_index(region_seed + step, 83, 0, 2001)) / 1000.0 - 1.0
		walk += turn * WIND_TURN_PER_DAY
	return Vector2(cos(walk), sin(walk))
