extends RefCounted

## The force balance on a rock standing in a current -- see
## docs/concept/rivers.md's "Boulders are hydrology" section.
##
## The water pushes with dynamic-pressure DRAG on the rock's wet frontal
## area; the rock resists with its SUBMERGED weight times bed friction. A
## boulder holds because the second exceeds the first -- and because it
## holds, the water has to go around it, which is what the flow shader's
## potential-flow displacement draws. The same balance is the real basis of
## bedload transport: a rock whose load passes 1 is entrained, and the real
## thresholds (Shields; Costa 1983 for boulders) come out of exactly these
## terms with these textbook constants, which is why the two sanity cases in
## test_boulder_hydraulics.gd -- a metre boulder shrugging off an ordinary
## current, a thirty-centimetre one swept by a flood -- are checks against
## the world rather than against this file.
##
## Every function takes the current in m/s, the rock's diameter in cm (the
## unit StoneSize speaks) and the water depth in m (the unit the hydraulics
## solve speaks), so a caller can feed it straight from
## EarthChunkGenerator.river_hydraulics_at_global and StoneSize.

const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const StoneSize = preload("res://src/world/stone_size.gd")

## Granite, in SI -- the same 2.7 g/cm^3 StoneSize's mass model uses.
const ROCK_DENSITY_KG_M3 := StoneSize.GRANITE_DENSITY_G_PER_CM3 * 1000.0

## Drag coefficient of a sphere at river-scale Reynolds numbers (the
## textbook ~0.47). A real boulder is rougher and blunter, which only
## raises this; 0.47 is the conservative end.
const SPHERE_DRAG_COEFFICIENT := 0.47

## Friction between a loose rock and the bed it sits on: the tangent of
## loose rock's angle of repose (~31 degrees), the standard figure in
## bedload-stability estimates.
const BED_FRICTION_COEFFICIENT := 0.6


## The pressure a moving column of water exerts when brought to rest:
## q = 0.5 * rho * v^2. This is the stagnation pressure on the rock's
## upstream face -- the same quantity the foam term in the shader tracks.
static func dynamic_pressure_pa(velocity_m_s: float) -> float:
	if velocity_m_s <= 0.0:
		return 0.0
	return 0.5 * OpenChannelFlow.WATER_DENSITY_KG_M3 * velocity_m_s * velocity_m_s


## How much of a rock of this diameter stands in water this deep, 0..1. A
## sphere's true wet fraction is a cap integral; the linear ratio is within
## a few percent of it across the range and is what every term here uses,
## consistently, so the balance stays self-consistent.
static func wet_fraction(diameter_cm: float, depth_m: float) -> float:
	if diameter_cm <= 0.0 or depth_m <= 0.0:
		return 0.0
	return clampf(depth_m / (diameter_cm / 100.0), 0.0, 1.0)


## The water's push on the rock, in newtons: F = q * Cd * A over the WET
## frontal area only -- the dry top of a rock standing out of the water is
## not in the current.
static func drag_force_newtons(velocity_m_s: float, diameter_cm: float, depth_m: float) -> float:
	var wet := wet_fraction(diameter_cm, depth_m)
	if wet <= 0.0:
		return 0.0
	var radius_m := diameter_cm / 200.0
	var frontal_area_m2 := PI * radius_m * radius_m * wet
	return dynamic_pressure_pa(velocity_m_s) * SPHERE_DRAG_COEFFICIENT * frontal_area_m2


## The rock's weight in newtons less the buoyancy on its wet part: a fully
## drowned granite rock keeps 1 - 1000/2700 of its dry weight.
static func submerged_weight_newtons(diameter_cm: float, depth_m: float) -> float:
	var dry_weight := StoneSize.mass_kg_for(diameter_cm) * OpenChannelFlow.GRAVITY_M_S2
	var buoyed_fraction := OpenChannelFlow.WATER_DENSITY_KG_M3 / ROCK_DENSITY_KG_M3
	return dry_weight * (1.0 - buoyed_fraction * wet_fraction(diameter_cm, depth_m))


## What holds the rock in place against the current: friction on its
## submerged weight.
static func resisting_force_newtons(diameter_cm: float, depth_m: float) -> float:
	return submerged_weight_newtons(diameter_cm, depth_m) * BED_FRICTION_COEFFICIENT


## Drag over resistance. Under 1 the rock holds and the water bends around
## it; over 1 the current wins and the rock is bedload. 0 in no water.
## (Named current_load, not load: `load` is GDScript's resource loader.)
static func current_load(velocity_m_s: float, diameter_cm: float, depth_m: float) -> float:
	var resist := resisting_force_newtons(diameter_cm, depth_m)
	if resist <= 0.0:
		return 0.0
	return drag_force_newtons(velocity_m_s, diameter_cm, depth_m) / resist


## Whether the rock's resistance beats the water's push.
static func holds(velocity_m_s: float, diameter_cm: float, depth_m: float) -> bool:
	return current_load(velocity_m_s, diameter_cm, depth_m) < 1.0
