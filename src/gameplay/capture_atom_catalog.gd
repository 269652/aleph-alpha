extends RefCounted

## The capture DSL's primitive-effect catalog (docs/concept/capture_dsl.md,
## atom catalog v2, 2026-09-05): the small set of atoms a capture device's
## pipeline is composed from. Pure lookup, no state -- same shape as
## spell_atom_catalog.gd -- but deliberately smaller: unlike magic's catalog
## (which reserves room for atoms with no dispatcher yet), every atom here
## already has a real dispatcher (capture_atom_effects.gd or the executor
## itself) and a real caller. Nothing is catalogued ahead of having
## somewhere to run.
##
## hold_captive / release_captive were retired 2026-09-05 in favour of the
## two atoms that say WHERE the subject goes -- confine(in: PART) and
## free(from: PART) -- because the net is a device with real parts now, and
## a confinement that does not name the part doing the confining cannot be
## checked against that part's mesh.

## atom_id -> {category, can_fail, required}, in a fixed order (known_ids()
## reports it), the two failing atoms first.
##
## - category: "check" (a physics gate that can fail WITH a reason),
##   "roll" (a chance that can fail without one -- a miss is a miss), or
##   "effect" (a state change that always applies once reached).
## - can_fail: whether this atom can stop the pipeline before later steps
##   run. This is capture's own constraint layer (docs/concept/
##   capture_dsl.md's "a pipeline can fail partway, on purpose") -- the one
##   significant divergence from magic's pipeline, where every atom always
##   happens.
## - required: the parameters the atom cannot run without; CaptureExecutor.
##   validate refuses a text that omits one, by name.
const _ATOMS := {
	"mesh_holds": {"category": "check", "can_fail": true, "required": ["mesh"]},
	"catch_roll": {"category": "roll", "can_fail": true, "required": ["base"]},
	"confine": {"category": "effect", "can_fail": false, "required": ["in"]},
	"free": {"category": "effect", "can_fail": false, "required": ["from"]},
	"move_captive": {"category": "effect", "can_fail": false, "required": []},
}

## Kept explicitly so known_ids() never depends on dictionary order.
const _IDS: Array[String] = ["mesh_holds", "catch_roll", "confine", "free", "move_captive"]

## Which parameter of each part-naming atom names the part.
const PART_PARAM := {"mesh_holds": "mesh", "confine": "in", "free": "from"}


func has(atom_id: String) -> bool:
	return _ATOMS.has(atom_id)


## The full spec for an atom, as a defensive copy so callers can't mutate the
## shared table. Assumes a known id (callers gate on has() first).
func spec(atom_id: String) -> Dictionary:
	return _ATOMS[atom_id].duplicate(true)


func category(atom_id: String) -> String:
	return _ATOMS[atom_id]["category"]


func can_fail(atom_id: String) -> bool:
	return _ATOMS[atom_id]["can_fail"]


## The parameters `atom_id` cannot run without. [] for an unknown atom.
func required_params(atom_id: String) -> Array:
	return Array(_ATOMS.get(atom_id, {}).get("required", [])).duplicate()


## The parameter that names a part, or "" for an atom that names none.
func part_param(atom_id: String) -> String:
	return String(PART_PARAM.get(atom_id, ""))


## Every atom id, in a fixed order, e.g. for a future device-authoring
## palette or a /help listing.
func known_ids() -> Array:
	return _IDS.duplicate()


## All atom ids in one category, in catalog order.
func ids_in_category(a_category: String) -> Array:
	var result: Array = []
	for atom_id in _IDS:
		if _ATOMS[atom_id]["category"] == a_category:
			result.append(atom_id)
	return result
