extends RefCounted

## A thrown item's flight time and impact behavior: damage falls off linearly
## with distance down to a floor, and knockback scales with momentum.

const MIN_DAMAGE_FRACTION: float = 0.2


## distance / throw_speed. A non-positive throw_speed can't produce a flight
## (nothing to divide by), so it returns INF rather than dividing by zero.
func travel_time(distance: float, throw_speed: float) -> float:
	if throw_speed <= 0.0:
		return INF
	return distance / throw_speed


## base_damage at distance 0, linearly falling off to MIN_DAMAGE_FRACTION of
## base_damage at distance == effective_range, then holding at that floor for
## any distance beyond effective_range (clamped both ends).
func damage_at_distance(base_damage: float, distance: float, effective_range: float) -> float:
	var min_damage := base_damage * MIN_DAMAGE_FRACTION
	if effective_range <= 0.0:
		return min_damage
	var fraction := clampf(distance / effective_range, 0.0, 1.0)
	return lerpf(base_damage, min_damage, fraction)


## Knockback force scaled by momentum (mass * throw_speed): heavier and
## faster throws both increase the shove.
func impact_knockback(mass: float, throw_speed: float) -> float:
	return mass * throw_speed
