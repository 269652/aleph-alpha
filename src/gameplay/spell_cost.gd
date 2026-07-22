extends RefCounted

## The magic DSL cost model (docs/concept/magic.md, "Constraint layer 1").
##
## Cost is *derived* from the atoms and parameters a spell is built from -- it
## is never authored, so the DSL literally cannot express "large effect for
## free". Character stats feed only the efficiency term, which discounts what
## the caster *pays*; they never touch the derived base (the power price), so a
## strong caster casts the same spell more cheaply but not more powerfully.
##
## Pure, no state beyond its atom catalog. Operates on the same list-of-atoms
## shape the parser will emit: [ {atom: "fire_damage", params: {magnitude: 8}} ].
## Every constant below is constrained by a property test in
## tests/unit/test_spell_cost.gd rather than eyeballed.

const SpellAtomCatalog = preload("res://src/gameplay/spell_atom_catalog.gd")

## Magnitude cost exponent. > 1.0 makes magnitude superlinear, so doubling an
## atom's magnitude more-than-doubles its cost -- diminishing power-per-mana
## that keeps min-maxed single-atom spam from being strictly optimal.
const MAG_EXP := 1.6

## Multiplier applied to each *repeated* copy of the same atom in one spell
## (the k-th copy, 0-indexed, costs SPAM_PENALTY^k extra). Distinct atoms pay
## no penalty, so varied compositions are cheaper than single-atom spam.
const SPAM_PENALTY := 1.35

## Reference radius: a burst of this radius doubles an atom's cost.
const RADIUS_REF := 4.0

## Governing-stat value that doubles casting efficiency (halves the paid cost).
## Tuned to the mage archetype's +50 max_mana bonus (class_archetype.gd).
const STAT_REF := 50.0

## Cast-time shaping: CT_REF is the derived base at which cast time doubles;
## HASTE_REF is the haste-stat value that halves it; BASE_CAST is the floor.
const CT_REF := 20.0
const HASTE_REF := 40.0
const BASE_CAST := 0.5

## Delivery-method cost multipliers: you pay for reach and safety. Self-cast is
## cheapest, area is priciest. Unknown methods are treated as touch (1.0).
const _DELIVERY_MULT := {
	"self": 0.8,
	"touch": 1.0,
	"projectile": 1.15,
	"area": 1.4,
}

var _catalog := SpellAtomCatalog.new()


## Cost of one atom instance: base, scaled by magnitude (superlinear),
## duration (linear vs the atom's reference), and burst radius. An unknown
## atom contributes nothing here -- the validator is what rejects it; the cost
## model just prices what it recognizes.
func atom_cost(atom_id: String, params: Dictionary) -> float:
	if not _catalog.has(atom_id):
		return 0.0
	var result := _catalog.base_cost(atom_id)
	if _catalog.scales_with_magnitude(atom_id):
		var reference := _catalog.mag_ref(atom_id)
		var magnitude := float(params.get("magnitude", reference))
		result *= pow(magnitude / reference, MAG_EXP)
	if _catalog.scales_with_duration(atom_id):
		var dur_reference := _catalog.dur_ref(atom_id)
		var duration := float(params.get("duration", dur_reference))
		result *= duration / dur_reference
	var radius := float(params.get("radius", 0.0))
	if radius > 0.0:
		result *= 1.0 + radius / RADIUS_REF
	return result


## Sum of every atom's cost, with the repeated-atom spam penalty applied per
## additional copy of the same atom id.
func composition_cost(atoms: Array) -> float:
	var counts := {}
	var total := 0.0
	for entry in atoms:
		var atom_id := String(entry.get("atom", ""))
		var params: Dictionary = entry.get("params", {})
		var repeats: int = counts.get(atom_id, 0)
		total += atom_cost(atom_id, params) * pow(SPAM_PENALTY, repeats)
		counts[atom_id] = repeats + 1
	return total


func delivery_multiplier(delivery: String) -> float:
	return _DELIVERY_MULT.get(delivery, 1.0)


## The derived power price: composition cost scaled by delivery method. Takes
## no stats -- this is the term stats can never change.
func derived_base(atoms: Array, delivery: String) -> float:
	return composition_cost(atoms) * delivery_multiplier(delivery)


## Casting efficiency from the governing stat. Always >= 1.0, rising with the
## stat, so it can only ever discount the paid cost.
func efficiency(governing_stat: float) -> float:
	return 1.0 + maxf(0.0, governing_stat) / STAT_REF


## What the caster actually spends: the derived base divided by efficiency.
## At zero governing stat this equals derived_base; it falls (but stays
## positive) as the stat rises.
func paid_mana(atoms: Array, delivery: String, governing_stat: float) -> float:
	return derived_base(atoms, delivery) / efficiency(governing_stat)


## Seconds to cast: grows with the derived base, shrinks with the haste stat,
## floored by BASE_CAST.
func cast_time(atoms: Array, delivery: String, haste_stat: float) -> float:
	var base := derived_base(atoms, delivery)
	return BASE_CAST * (1.0 + base / CT_REF) / (1.0 + maxf(0.0, haste_stat) / HASTE_REF)


## Convenience aggregate for callers/UI: every cost dimension in one call.
func breakdown(atoms: Array, delivery: String, governing_stat: float, haste_stat: float) -> Dictionary:
	return {
		"base": derived_base(atoms, delivery),
		"mana": paid_mana(atoms, delivery, governing_stat),
		"cast_time": cast_time(atoms, delivery, haste_stat),
		"efficiency": efficiency(governing_stat),
		"materials": material_cost(atoms),
	}


## A third power axis alongside mana (this file) and physics
## (docs/concept/magic.md, 2026-07-15 brainstorm: "spells can consume
## material components ... so casting draws on the same economy crafting
## does"). Materials are declared per-atom under a "materials" params key
## (material_id -> quantity), the same way magnitude/duration/radius already
## are -- never authored as a single total, just summed from what's declared.
## Returns material_id -> total quantity consumed across the whole
## composition; an atom with no "materials" entry contributes nothing.
func material_cost(atoms: Array) -> Dictionary:
	var totals := {}
	for entry in atoms:
		var params: Dictionary = entry.get("params", {})
		var materials: Dictionary = params.get("materials", {})
		for material_id in materials:
			var quantity := float(materials[material_id])
			totals[material_id] = totals.get(material_id, 0.0) + quantity
	return totals


## Caster self-danger (docs/concept/magic.md, 2026-07-15 brainstorm: "physical
## honesty cuts both ways" -- a spell is a force the sim resolves, and it does
## not spare the one who cast it). "self" delivery is centered on the caster
## by design and always affects them, regardless of radius or distance; any
## other delivery method only blows back if the caster's own standoff
## distance falls within the effect's radius (a zero-radius effect can never
## reach a caster who isn't standing at distance zero).
func does_affect_caster(delivery: String, radius: float, caster_distance_from_effect: float) -> bool:
	if delivery == "self":
		return true
	return caster_distance_from_effect <= radius
