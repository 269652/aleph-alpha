extends RefCounted

## Depth, in real meters (see BiomeClassifier.depth_meters_at), up to which a
## character can still stand and wade rather than needing to swim. Meters, not
## a normalized fraction: a fraction of the full ocean-depth range would make
## realistic shallow coastal water (a few meters) round down to a barely
## perceptible sliver of "wading slowdown" -- exactly the bug this once was.
const WADE_DEPTH_METERS := 1.5
## Fraction of walking speed lost at the deepest wadeable depth.
const WADE_SPEED_LOSS := 0.5
## Swimming speed relative to normal walking speed, for an unweighted swimmer.
const BASE_SWIM_SPEED := 0.6


## Resolves a character's movement mode and speed multiplier from water depth
## (in real meters) and carried weight. total_weight is the character's
## current total weight including soaked equipment (see
## EquipmentMaterial.effective_weight); max_swimmable_weight is the heaviest a
## character can carry and still swim. Returns a Dictionary:
## {mode: "walking"|"wading"|"swimming"|"drowning", speed_multiplier: float}.
func resolve(water_depth_meters: float, total_weight: float, max_swimmable_weight: float) -> Dictionary:
	if water_depth_meters <= 0.0:
		return {"mode": "walking", "speed_multiplier": 1.0}

	if water_depth_meters <= WADE_DEPTH_METERS:
		var depth_fraction := water_depth_meters / WADE_DEPTH_METERS
		return {"mode": "wading", "speed_multiplier": 1.0 - depth_fraction * WADE_SPEED_LOSS}

	if total_weight > max_swimmable_weight:
		return {"mode": "drowning", "speed_multiplier": 0.0}

	var weight_fraction := total_weight / max_swimmable_weight
	return {"mode": "swimming", "speed_multiplier": BASE_SWIM_SPEED * (1.0 - weight_fraction)}
