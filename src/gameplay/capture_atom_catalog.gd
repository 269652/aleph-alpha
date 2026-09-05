extends RefCounted

## The capture DSL's primitive-effect catalog (docs/concept/capture_dsl.md):
## the small set of atoms a capture device's pipeline is composed from. Pure
## lookup, no state -- same shape as spell_atom_catalog.gd -- but
## deliberately smaller: unlike magic's catalog (which reserves room for
## atoms with no dispatcher yet), every atom here already has a real
## dispatcher (capture_atom_effects.gd) and a real caller. Nothing is
## catalogued ahead of having somewhere to run.

## atom_id -> {category, can_fail}
##
## - category: "roll" (can fail and short-circuit the rest of the pipeline)
##   or "effect" (a state change that always applies once reached).
## - can_fail: whether this atom can stop the pipeline before later steps
##   run. This is capture's own constraint layer (docs/concept/
##   capture_dsl.md's "a pipeline can fail partway, on purpose") -- the one
##   significant divergence from magic's pipeline, where every atom always
##   happens.
const _ATOMS := {
	"catch_roll": {"category": "roll", "can_fail": true},
	"hold_captive": {"category": "effect", "can_fail": false},
	"release_captive": {"category": "effect", "can_fail": false},
	"move_captive": {"category": "effect", "can_fail": false},
}


func has(atom_id: String) -> bool:
	return _ATOMS.has(atom_id)


## The full spec for an atom, as a defensive copy so callers can't mutate the
## shared table. Assumes a known id (callers gate on has() first).
func spec(atom_id: String) -> Dictionary:
	return _ATOMS[atom_id].duplicate()


func category(atom_id: String) -> String:
	return _ATOMS[atom_id]["category"]


func can_fail(atom_id: String) -> bool:
	return _ATOMS[atom_id]["can_fail"]


## Every atom id, e.g. for a future device-authoring palette or a /help listing.
func known_ids() -> Array:
	return _ATOMS.keys()


## All atom ids in one category.
func ids_in_category(a_category: String) -> Array:
	var result: Array = []
	for atom_id in _ATOMS:
		if _ATOMS[atom_id]["category"] == a_category:
			result.append(atom_id)
	return result
