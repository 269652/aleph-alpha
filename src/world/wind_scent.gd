extends RefCounted

## Smell travelling on the wind (see docs/concept/olfaction.md "The wind
## carries it").
##
## `Olfaction.dilution` thins a smell by the straight-line distance from source
## to nose. That is the still-air case, and still air is the one case the world
## never actually contains: `WeatherModel.wind_direction_for` has existed and
## been tested since the weather model was written, and -- verified -- had **no
## production caller at all**. The world had a wind direction that nothing in
## the running game ever asked for.
##
## This module asks. It converts a geometric distance into the distance the
## smell BEHAVES as if it had: shorter downwind (the plume is carried to the
## nose), longer upwind (the nose has to find what the wind is taking away).
## Everything downstream -- `Olfaction.dilution`, `ScentForaging.best_source`,
## `FlightDistance.smells_player` -- keeps working unchanged on that one number,
## which is the whole reason the wind is expressed as a distance rather than as
## a new term inside each of them.
##
## **Why this is a mechanic and not a detail.** It gives the player a real,
## readable decision that costs nothing but attention: come at an animal from
## downwind and you are quiet; come from upwind and you were announced long
## before you could see it. The wind turns day to day
## (`WeatherModel.WIND_TURN_PER_DAY`), so the right line of approach to the
## same meadow is different tomorrow, and the weather glass becomes an
## instrument you use rather than a curiosity you read.
##
## Honest scope note: this is steady-state advection, not a simulated plume.
## Real odour plumes meander, pool in hollows and sink on cold nights. This
## models the one thing that decides the player's line -- which side of the
## animal the wind is on -- at the same fidelity `ScentField` chose for floral
## scent, and for the same reason.
##
## Pure and engine-free.

const WeatherModel = preload("res://src/world/weather_model.gd")

## How much a full-strength wind stretches a smell along its own direction.
## 0.8 means a gale carries a smell nearly twice as far downwind as still air
## would, which is roughly the difference field-craft actually turns on.
const ADVECTION_GAIN := 0.8

## The floor on how much of its still-air reach a smell keeps straight UPWIND.
## Not zero: a real plume is turbulent, so approaching from upwind makes you
## quiet, never invisible -- and a floor of zero would divide by nothing.
const MIN_REACH_FACTOR := 0.2

## The weather model's `wind_strength_for` is a visual energy multiplier, not a
## 0..1 fraction: 1.0 on a clear day (the water's original always-on scroll
## pace) rising to 1.8 in a storm. Normalising by the storm value keeps a clear
## day at a real ~0.56 breeze rather than at nothing, which matters because
## clear is the majority state of a session (50% of rolls, see
## `WeatherModel.CLEAR_THRESHOLD`) -- a scent-wind that only existed in bad
## weather would be off for most of the game.
const STORM_WIND_STRENGTH := 1.8


## The 0..1 advection strength for a raw `WeatherModel.wind_strength_for`
## value. Converted here, once, so no caller invents its own normalisation.
static func advection_strength(weather_wind_strength: float) -> float:
	return clampf(weather_wind_strength / STORM_WIND_STRENGTH, 0.0, 1.0)


## How much further than still air a smell reaches from `source` toward
## `nose`: above 1 downwind, below 1 upwind, exactly 1 in still air or with no
## wind direction at all.
static func reach_factor(
	source: Vector2, nose: Vector2, wind_direction: Vector2, wind_strength: float
) -> float:
	var strength := clampf(wind_strength, 0.0, 1.0)
	if strength <= 0.0 or wind_direction.length() <= 0.0:
		return 1.0
	var offset := nose - source
	if offset.length() <= 0.0:
		return 1.0
	var alignment := offset.normalized().dot(wind_direction.normalized())
	return maxf(MIN_REACH_FACTOR, 1.0 + ADVECTION_GAIN * strength * alignment)


## The distance, in tiles, that the smell from `source` behaves as if it had
## when it arrives at `nose`. Hand this to `Olfaction` in place of the
## geometric distance and every existing judgement it makes keeps working.
static func effective_distance_tiles(
	source: Vector2, nose: Vector2, wind_direction: Vector2, wind_strength: float, tile_size: float
) -> float:
	if tile_size <= 0.0:
		return 0.0
	var geometric := source.distance_to(nose) / tile_size
	if geometric <= 0.0:
		return 0.0
	return geometric / reach_factor(source, nose, wind_direction, wind_strength)


## Whether `nose` is on the receiving side of the wind from `source` -- the
## question the player is actually asking when they circle round an animal.
static func is_downwind_of(source: Vector2, nose: Vector2, wind_direction: Vector2) -> bool:
	var offset := nose - source
	if offset.length() <= 0.0 or wind_direction.length() <= 0.0:
		return false
	return offset.normalized().dot(wind_direction.normalized()) > 0.0


## Compass points, in the order `wind_name` steps through them starting from
## a wind blowing due EAST (screen +x) and turning clockwise on screen. A wind
## is named for where it comes FROM, so a wind blowing east is a *westerly* --
## the one piece of real-world convention a player brings with them, and the
## reason this is a function rather than a direction vector printed raw.
const NAMES_CLOCKWISE_FROM_EAST := [
	"westerly",  # blowing east
	"north-westerly",  # blowing south-east (screen +y is south)
	"northerly",  # blowing south
	"north-easterly",  # blowing south-west
	"easterly",  # blowing west
	"south-easterly",  # blowing north-west
	"southerly",  # blowing north
	"south-westerly",  # blowing north-east
]


## What a player would call this wind. Empty only for no wind at all.
static func wind_name(wind_direction: Vector2) -> String:
	if wind_direction.length() <= 0.0:
		return ""
	var turns := wind_direction.angle() / TAU
	var sector := int(roundf(turns * NAMES_CLOCKWISE_FROM_EAST.size()))
	return NAMES_CLOCKWISE_FROM_EAST[posmod(sector, NAMES_CLOCKWISE_FROM_EAST.size())]
