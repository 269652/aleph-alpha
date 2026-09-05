extends RefCounted

## The energy-domain catalog of docs/concept/standard_model.md ("The formal
## model / 1. Quantities"). Pure lookup, no state -- the same shape as
## capture_atom_catalog.gd.
##
## Every domain is a bond-graph (effort, flow) pair whose product is POWER:
## torque x angular velocity, force x velocity, voltage x current, pressure x
## volumetric flow -- all watts. That single fact is what lets one solver
## (device_network.gd) cross from a river to a wire without a special case per
## crossing: a transformer or gyrator between two domains is lossless because
## `e x f` means the same thing on both sides.
##
## Thermal is the one honest exception, and it says so: temperature x heat
## flow is NOT a power (the heat flow already is one, in watts). That is the
## standard "pseudo-bond graph" convention, and is_power_domain is how the
## solver keeps thermal out of its energy accounting rather than pretending.
##
## The catalog is CLOSED. Adding a sixth domain is a deliberate decision that
## test_the_catalog_is_exactly_the_five_named_domains_in_a_fixed_order notices.

const DOMAIN_ROTATION := "rotation"
const DOMAIN_TRANSLATION := "translation"
const DOMAIN_ELECTRICAL := "electrical"
const DOMAIN_HYDRAULIC := "hydraulic"
const DOMAIN_THERMAL := "thermal"

## Fixed order, kept explicitly rather than read out of the dictionary's keys.
const DOMAINS: Array[String] = [
	DOMAIN_ROTATION, DOMAIN_TRANSLATION, DOMAIN_ELECTRICAL, DOMAIN_HYDRAULIC,
	DOMAIN_THERMAL,
]

## domain_id -> {effort_name, effort_unit, flow_name, flow_unit, is_power}
##   is_power: whether effort x flow is a power. False only for the thermal
##   pseudo-bond, whose FLOW is the power.
const _SPECS := {
	DOMAIN_ROTATION: {
		"effort_name": "torque", "effort_unit": "N*m",
		"flow_name": "angular_velocity", "flow_unit": "rad/s",
		"is_power": true,
	},
	DOMAIN_TRANSLATION: {
		"effort_name": "force", "effort_unit": "N",
		"flow_name": "velocity", "flow_unit": "m/s",
		"is_power": true,
	},
	DOMAIN_ELECTRICAL: {
		"effort_name": "voltage", "effort_unit": "V",
		"flow_name": "current", "flow_unit": "A",
		"is_power": true,
	},
	DOMAIN_HYDRAULIC: {
		"effort_name": "pressure", "effort_unit": "Pa",
		"flow_name": "volumetric_flow", "flow_unit": "m^3/s",
		"is_power": true,
	},
	DOMAIN_THERMAL: {
		"effort_name": "temperature", "effort_unit": "K",
		"flow_name": "heat_flow", "flow_unit": "W",
		"is_power": false,
	},
}


func has(domain_id: String) -> bool:
	return _SPECS.has(domain_id)


## Every domain id, in the catalog's fixed order.
func known_ids() -> Array:
	return DOMAINS.duplicate()


## The full spec, as a defensive copy so callers can't mutate the shared
## table. Empty for an unknown domain.
func spec(domain_id: String) -> Dictionary:
	return _SPECS.get(domain_id, {}).duplicate()


func effort_name(domain_id: String) -> String:
	return String(_SPECS.get(domain_id, {}).get("effort_name", ""))


func effort_unit(domain_id: String) -> String:
	return String(_SPECS.get(domain_id, {}).get("effort_unit", ""))


func flow_name(domain_id: String) -> String:
	return String(_SPECS.get(domain_id, {}).get("flow_name", ""))


func flow_unit(domain_id: String) -> String:
	return String(_SPECS.get(domain_id, {}).get("flow_unit", ""))


## Whether effort x flow is a power in this domain. False for thermal (a
## pseudo-bond) and for anything not catalogued.
func is_power_domain(domain_id: String) -> bool:
	return bool(_SPECS.get(domain_id, {}).get("is_power", false))


## The power carried by a bond in `domain_id`, in watts: effort x flow in a
## true power domain, the flow alone in the thermal pseudo-bond, and nothing
## for a domain the catalog does not know (the compiler rejects those before
## anything is solved; if one ever slipped through, "nothing" is the honest
## answer rather than a crash or an invented number).
func power(domain_id: String, effort: float, flow: float) -> float:
	if not _SPECS.has(domain_id):
		return 0.0
	if is_power_domain(domain_id):
		return effort * flow
	return flow
