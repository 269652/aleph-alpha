extends RefCounted

const WeatherModel = preload("res://src/world/weather_model.gd")

## Snow instead of rain when it is cold, and snow lying on the ground.
##
## Rain falling on a frozen world is the same class of mistake as a canopy
## carrying apples under snow: the weather and the calendar not talking to each
## other.
##
## Pure and engine-free: what falls, and how deep it lies. Drawing it is the
## renderer's job.

## Below this warmth, precipitation falls as snow.
##
## TEMPERATURE decides, not the season name -- a cold snap in autumn snows and
## a mild winter rains, which is what makes weather feel like weather rather
## than a label on the calendar.
##
## MEASURED against the season curve rather than guessed. Winter carries warmth
## 0.00-0.14 and the shoulder seasons run 0.15-0.85, so 0.25 reached well into
## spring and it snowed on blossom (reported). At the boundary between the two,
## winter snows and spring does not -- while a genuinely cold climate still
## snows out of season, because latitude scales this before it gets here.
const FREEZING_WARMTH := 0.15

## How long a steady snowfall takes to cover the ground, and how long a thaw
## takes to clear it.
##
## Measured in WEATHER SPELLS, because that is the clock that actually governs
## them: a snowfall only lasts as long as the weather does. These were 45 and
## 30 real minutes -- four and a half spells, and three -- so a snowfall ended
## long before it could cover anything and the ground never went properly
## white. The numbers were chosen against "how long should a player watch this
## take" without checking what the weather would allow, which is the same
## two-clocks mistake as the rooting threshold and the gut-passage timer.
##
## Covering takes most of a single spell: long enough to watch arrive, short
## enough to finish. Thawing takes longer, because snow lingers after the cold
## does -- but still completes in a couple of spells rather than never.
##
## 0.5, not the original 0.6: asked directly for a 20% faster cover. Speed is
## the INVERSE of this constant (depth per second, not seconds per depth), so
## a 20% faster cover is 1/1.2 of the previous TIME -- 0.6 / 1.2 = 0.5
## exactly, not the multiplier itself reduced by 20% (which would have been
## 0.48). Pinned by test_covering_speed_was_increased_twenty_percent_over_
## the_previous_tuning.
const SECONDS_TO_COVER := WeatherModel.WEATHER_PERIOD_SECONDS * 0.5
const SECONDS_TO_THAW := WeatherModel.WEATHER_PERIOD_SECONDS * 1.5


## ## What it looks like coming down
##
## The same drop field as rain -- one MultiMesh, one draw call -- with these
## swapped in. White, far slower, and drifting rather than slanting: reusing
## rain unchanged would give white rain, which reads as a recolour rather than
## as weather.
const FLAKE_COLOR := Color(0.96, 0.97, 1.0, 0.8)
const FLAKE_FALL_SPEED := 90.0
const FLAKE_SLANT := 0.05


## Whether this weather, at this warmth, comes down as snow.
static func falls_as_snow(weather: String, warmth: float) -> bool:
	if weather != "rain" and weather != "storm":
		return false
	return warmth < FREEZING_WARMTH


## The new snow depth, 0 bare to 1 fully covered.
##
## Accumulates while it is snowing and melts once it is above freezing.
## Between the two -- cold but not snowing -- it simply lies, which is what
## makes a covered landscape persist through a clear frozen day.
static func accumulate(
	depth: float, snowing: bool, warmth: float, delta_seconds: float
) -> float:
	var current := clampf(depth, 0.0, 1.0)
	if snowing:
		return clampf(current + delta_seconds / SECONDS_TO_COVER, 0.0, 1.0)
	if warmth < FREEZING_WARMTH:
		return current
	return clampf(current - delta_seconds / SECONDS_TO_THAW, 0.0, 1.0)
