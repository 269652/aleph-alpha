extends RefCounted

## How much a cell's latitude dampens peak sunlight intensity, at the poles.
const POLAR_DAMPENING := 0.5

## Returns normalized sunlight intensity in [0.0, 1.0].
## time_of_day: 0.0 = midnight, 0.5 = noon, wraps at 1.0.
## latitude_normalized: 0.0 at the equator, 1.0 at the poles.
func intensity_at(time_of_day: float, latitude_normalized: float) -> float:
	var sun_angle := cos((time_of_day - 0.5) * TAU)
	var daylight := maxf(sun_angle, 0.0)
	var latitude_factor := 1.0 - latitude_normalized * POLAR_DAMPENING
	return daylight * latitude_factor
