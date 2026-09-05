extends RefCounted

## The derivations of docs/concept/standard_model.md ("6. Derived, not
## authored"): the functions that read an element's parameters off a part's
## real material and geometry, or off a real fluid, so that two parts of the
## same material and shape can never disagree about their physics. Pure
## static functions, no engine, no state -- the same role capture_physics.gd
## plays for the capture DSL.
##
## Every constant here is a published figure, named and sourced, per this
## project's no-eyeballed-numbers rule. Nothing is tuned.

const MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")
const ItemPart: GDScript = preload("res://src/gameplay/item_part.gd")
const OpenChannelFlow: GDScript = preload("res://src/world/open_channel_flow.gd")

## 100 %IACS in siemens per metre -- the International Annealed Copper
## Standard's own definition (5.80e7 S/m at 20 C). MaterialProperties'
## conductivity column is published %IACS put through a linear map; this is
## the one number that turns that map back into real units, so a wire's
## resistance can be computed in ohms rather than on a 0-10 scale.
const IACS_SIEMENS_PER_M: float = 5.80e7

## Drag coefficient of a flat plate held normal to a stream -- the
## NASA/Hoerner figure for a square plate (1.28; a long rectangular plate
## runs to ~2.0, a disc to 1.17). A paddle is a plate.
const FLAT_PLATE_DRAG_COEFFICIENT: float = 1.28

## Sea-level air at 15 C, the ISA standard atmosphere figure.
const AIR_DENSITY_KG_M3: float = 1.225

## The fluids a paddle source may name. Water reuses the shipped hydraulics
## constant rather than restating it, so the two cannot drift.
const FLUID_DENSITIES: Dictionary = {
	"water": OpenChannelFlow.WATER_DENSITY_KG_M3,
	"air": AIR_DENSITY_KG_M3,
}


# -- conductivity ------------------------------------------------------------

## A material's electrical conductivity in S/m, recovered from the shipped
## 0-10 scalar by running MaterialProperties.conductivity_from_iacs backwards
## (scale -> %IACS) and then applying the IACS definition (%IACS -> S/m).
## Nothing is chosen: both steps are the published map and its inverse.
## 0.0 for a material the table does not model -- "not measured" is not
## "conducts a little".
static func conductivity_s_per_m(material: String) -> float:
	if not MaterialProperties.MATERIALS.has(material):
		return 0.0
	var scale: float = MaterialProperties.new().property_value(material, "conductivity")
	var iacs_percent: float = scale * MaterialProperties.IACS_SILVER_PERCENT \
		/ MaterialProperties.CONDUCTIVITY_MAX
	return IACS_SIEMENS_PER_M * iacs_percent / 100.0


# -- a wire's resistance --------------------------------------------------

## Pouillet's law, R = L / (sigma A), for a cylindrical conductor of this
## material, length and diameter. INF for anything that cannot carry a
## circuit at all -- an unmodeled material, or a wire with no length or
## section -- rather than a guess.
static func wire_resistance_ohms(material: String, length_cm: float, diameter_cm: float) -> float:
	var radius_m := diameter_cm * 0.5 / 100.0
	return _resistance_ohms(conductivity_s_per_m(material), length_cm / 100.0, PI * radius_m * radius_m)


## Whether a part is something a resistance can honestly be derived FROM: a
## haft -- a cylinder, which is what a wire is. A blade or a slab has a
## section too, but "a wire" is a conductor run, and deriving a confident
## number for a thing that is not one is the class of mistake this model
## refuses everywhere else.
static func can_derive_resistance(part: RefCounted) -> bool:
	return part != null and part.is_valid() and part.geometry == ItemPart.GEOMETRY_HAFT


## The resistance of a wire PART, from its own material, span and section.
## Reads ItemPart's shipped geometry (span_cm, cross_section_cm2) rather than
## restating the cylinder formula, so a part and a bare (material, length,
## diameter) triple can never disagree. INF where can_derive_resistance is
## false.
static func wire_resistance_of_part(part: RefCounted) -> float:
	if not can_derive_resistance(part):
		return INF
	return _resistance_ohms(
		conductivity_s_per_m(part.material),
		part.span_cm() / 100.0,
		part.cross_section_cm2() / 10000.0
	)


static func _resistance_ohms(sigma_s_per_m: float, length_m: float, area_m2: float) -> float:
	if sigma_s_per_m <= 0.0 or length_m <= 0.0 or area_m2 <= 0.0:
		return INF
	return length_m / (sigma_s_per_m * area_m2)


# -- a wheel's ratio -------------------------------------------------------

## A wheel's transformer ratio between the water (or air) pushing its rim and
## the shaft it turns is its RADIUS: tau = F r and omega = v / r are the two
## lines of the transformer law with r the radius -- electromagnetism.md's
## "leverage in reverse". Half the part's span, in metres. (A face's span is
## its larger in-plane dimension -- right for a disc, generous for a paddle
## that only reaches the water at its rim; orientation is
## emergent_crafting.md's own open row.)
static func wheel_radius_m(part: RefCounted) -> float:
	if part == null or not part.is_valid():
		return 0.0
	return part.span_cm() / 200.0


# -- the paddle source: momentum flux as a Thevenin pair -------------------

static func fluid_density(fluid: String) -> float:
	return float(FLUID_DENSITIES.get(fluid, 0.0))


## The Thevenin pair (stall effort, internal resistance) for a paddle of
## `area_m2` held in a stream of `velocity` m/s: the force on a flat plate
## normal to a stream is the drag law F = 1/2 rho C_d A v^2 when the plate is
## stalled, falling to nothing when the plate moves as fast as the water.
## The internal resistance is the secant from stall to free-running,
## F_stall / v -- an honest linearisation of a quadratic, stated in the
## concept doc's known-simplifications list rather than hidden. A still
## stream pushes nothing at all.
##
## Water's density makes this a water wheel's source; air's makes it a
## windmill's. Same function, same mechanism, one fluid constant apart.
static func paddle_source(fluid_density_kg_m3: float, area_m2: float, velocity_m_s: float) -> Dictionary:
	if fluid_density_kg_m3 <= 0.0 or area_m2 <= 0.0 or velocity_m_s <= 0.0:
		return {"effort": 0.0, "resistance": 0.0}
	var stall_force := 0.5 * fluid_density_kg_m3 * FLAT_PLATE_DRAG_COEFFICIENT \
		* area_m2 * velocity_m_s * velocity_m_s
	return {"effort": stall_force, "resistance": stall_force / velocity_m_s}


# -- Faraday -------------------------------------------------------------------

## The gyrator ratio of a coil of `turns` turns and `area_m2` area turning in
## a field of `magnet_tesla`: the peak EMF of a rotating coil is B A N omega,
## so k = B A N in V*s/rad -- and the SAME k is the torque per ampere the
## coil pushes back with, which is why a generator and a motor are one
## machine. (The peak of a sinusoid; the model is DC throughout, as
## electromagnetism.md already decided.)
static func faraday_ratio(magnet_tesla: float, turns: float, area_m2: float) -> float:
	return magnet_tesla * turns * area_m2
