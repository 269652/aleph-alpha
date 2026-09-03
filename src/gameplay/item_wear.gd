extends RefCounted

## Accumulated combat wear on a weapon/tool, and when it fails from
## fatigue -- see docs/concept/item_durability.md. Pure logic.
##
## Complements, not duplicates, ImpactResolver's existing shatter mechanic:
## shatter is a single-hit brittle fracture (toughness <
## MaterialProperties.BRITTLE_TOUGHNESS) at high momentum -- this is the
## OTHER failure mode materials.md's "Physical honesty over time" section
## names: a tough-enough material doesn't shatter, it wears down gradually
## and fails from accumulated fatigue instead. An item only ever fails one
## of the two ways, never both, because both are gated on opposite sides of
## the same BRITTLE_TOUGHNESS cutoff -- see the concept doc.

const MaterialProperties = preload("res://src/gameplay/material_properties.gd")

## Wear one qualifying use event costs -- a connecting attack (once per
## creature actually struck) or a block that absorbs a real hit. A flat
## "8-bit" unit, not a continuous momentum integral: see the concept doc for
## why a per-event count, not a momentum-integral, is the right resolution
## for this.
const WEAR_PER_USE: float = 1.0

## Uses survived per point of toughness before failing from accumulated
## fatigue. A deliberate, named game-balance constant -- see
## docs/concept/item_durability.md's "Where the constant comes from" for the
## full reasoning: toughness is already this game's "energy absorbed before
## fracture" scalar, so uses-before-failure scaling linearly with it is the
## physically consistent choice, but the multiplier itself is an honest
## design anchor (a primitive knapped blade should feel fragile within a
## single hard fight, not a measurement dressed up as one.
const USES_PER_TOUGHNESS_POINT: float = 8.0

## Fraction of max_wear at which an item starts reading "worn" rather than
## "pristine" -- visible wear shows over the back half of a tool's service
## life, not just at the very end.
const WORN_THRESHOLD_FRACTION: float = 0.6

var _materials: RefCounted = MaterialProperties.new()


## Total wear `material` can absorb before it fails from fatigue. INF for a
## material with no modeled toughness at all -- mirrors
## MaterialProperties.NO_THERMAL_FAILURE's "nothing this game models will
## ever hurt it" convention: an item whose material has not been measured
## cannot be told to break by a number the game does not have.
func max_wear(material: String) -> float:
	if not MaterialProperties.MATERIALS.has(material):
		return INF
	return _materials.property_value(material, "toughness") * USES_PER_TOUGHNESS_POINT


func is_broken(current_wear: float, material: String) -> bool:
	return current_wear >= max_wear(material)


## "pristine", "worn" or "broken" -- the three states an item's condition
## reads as (see docs/concept/item_illustrations.md's composite sheet spec).
func condition_for(current_wear: float, material: String) -> String:
	var cap := max_wear(material)
	if is_inf(cap):
		return "pristine"
	if current_wear >= cap:
		return "broken"
	if current_wear >= cap * WORN_THRESHOLD_FRACTION:
		return "worn"
	return "pristine"
