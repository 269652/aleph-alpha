extends RefCounted

## Elevation's cooling effect on temperature, in temperature units per unit of elevation.
const ELEVATION_LAPSE_RATE := 0.5

## Returns a normalized temperature in [0.0, 1.0] for a given latitude and elevation.
## latitude_normalized: 0.0 at the equator, 1.0 at the poles.
## elevation: 0.0 at sea level, 1.0 at the highest peaks.
func temperature_at(latitude_normalized: float, elevation: float) -> float:
	var base_temperature := 1.0 - latitude_normalized
	return clampf(base_temperature - elevation * ELEVATION_LAPSE_RATE, 0.0, 1.0)
