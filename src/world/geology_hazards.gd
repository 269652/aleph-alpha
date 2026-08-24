extends RefCounted

## Real per-layer underground hazards, independent of collapse
## (TunnelSupport): foul air and flood risk (see docs/concept/geology.md
## "Foul air deepens with distance from open air" / "Flooding compounds
## depth with nearby water"). Pure functions of layer (and, for flooding,
## distance to the nearest surface water) -- no engine state read here,
## same convention as TunnelSupport/MountainOrePlacement.

const Strata = preload("res://src/world/strata.gd")

## Foul-air risk [0,1] per layer, monotonically increasing with depth. Real
## "blackdamp" (CO2 buildup / O2 depletion) is overwhelmingly a natural-
## ventilation problem -- the stack effect that keeps a shaft breathing
## weakens the further a working sits from an opening to the surface -- so
## this rises with how deep/enclosed the layer is, not what rock it cuts.
const _FOUL_AIR_BY_LAYER := {
	Strata.LAYER_TOPSOIL_REGOLITH: 0.05,
	Strata.LAYER_BEDROCK: 0.20,
	Strata.LAYER_DEEP_BEDROCK: 0.45,
	Strata.LAYER_HYDROTHERMAL: 0.70,
}

## Base flood risk [0,1] per layer before the distance falloff below --
## deeper layers are more likely to sit below the local water table at
## all, independent of any specific nearby surface water.
const _FLOOD_BASE_RISK_BY_LAYER := {
	Strata.LAYER_TOPSOIL_REGOLITH: 0.10,
	Strata.LAYER_BEDROCK: 0.25,
	Strata.LAYER_DEEP_BEDROCK: 0.45,
	Strata.LAYER_HYDROTHERMAL: 0.55,
}

## How fast flood risk falls off with distance (metres) from the nearest
## surface water -- real mine flooding disasters are disproportionately
## breaches into a nearby flooded channel/working, not a dry deep mine
## spontaneously flooding, so proximity matters as much as depth. Picked so
## risk is still meaningfully elevated a few tens of metres out but has
## clearly decayed by a few hundred (test_flood_risk_far_from_water_
## approaches_zero pins the long tail).
const FLOOD_DISTANCE_DECAY_M := 60.0


## Foul-air risk for `layer`, in [0, 1]. Zero for any layer not in the
## table (including an unwired/unknown string).
func foul_air_at(layer: String) -> float:
	return float(_FOUL_AIR_BY_LAYER.get(layer, 0.0))


## Flood risk for `layer` given `distance_to_nearest_surface_water` metres,
## in [0, 1] -- the per-layer base risk scaled down by an exponential
## falloff on distance (real hydraulic connectivity fades with distance,
## it doesn't cut off sharply).
func flood_risk_at(layer: String, distance_to_nearest_surface_water: float) -> float:
	var base: float = _FLOOD_BASE_RISK_BY_LAYER.get(layer, 0.0)
	if base <= 0.0:
		return 0.0
	var falloff := exp(-maxf(distance_to_nearest_surface_water, 0.0) / FLOOD_DISTANCE_DECAY_M)
	return clampf(base * falloff, 0.0, 1.0)
