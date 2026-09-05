extends RefCounted

## The capture DSL's atom-effects dispatcher (docs/concept/capture_dsl.md):
## applies one resolved pipeline step onto the tool Item it's about -- the
## same "one shared method, either receiver" duck-typed shape
## spell_atom_effects.gd already established for magic (there, dispatch
## lands on Player/CreatureMarker; here, it lands on the tool itself, since
## that IS what a capture device's own state is -- see Item.captive_species).
##
## Never generates a roll or decides whether an atom runs at all -- that is
## capture_executor.gd's job (resolve_catch/resolve_release/resolve_transfer
## already reported which effects apply, and CaptureExecutor.validate already
## checked that a confine(in: PART) follows a mesh_holds on that part). This
## only carries them out.

const Item = preload("res://src/gameplay/item.gd")


## Applies `atom_id` to `tool_item`. Returns true/false for a plain effect
## (confine/free); returns the species that moved for move_captive (a
## String, "" if the tool had nothing to move) -- NOT a generic curiosity
## item id. The species has to survive the move so the container it lands
## on can still be rendered as the specific creature it holds
## (docs/concept/capture_dsl.md's "Rendering a bottled catch"); the caller
## (Player) is the one who puts it on a fresh container item, the same
## relocation confine already does the other direction.
##
## The retired hold_captive/release_captive are unknown here, and an unknown
## atom does nothing and reports false.
func apply_to_target(atom_id: String, params: Dictionary, tool_item: Item, context: Dictionary) -> Variant:
	match atom_id:
		"confine":
			return _apply_confine(tool_item, context)
		"free":
			return _apply_free(tool_item)
		"move_captive":
			return _apply_move_captive(tool_item)
		_:
			return false


## confine(in: PART): the subject is now inside the named part -- the bag
## whose mesh mesh_holds just showed holds it. The tool records the species;
## which part did the confining is a fact of the device text, checked
## statically, not a second field on the item.
func _apply_confine(tool_item: Item, context: Dictionary) -> bool:
	var target: Dictionary = context.get("target", {})
	tool_item.captive_species = String(target.get("species", ""))
	return true


## free(from: PART): the subject leaves the named part.
func _apply_free(tool_item: Item) -> bool:
	tool_item.captive_species = ""
	return true


func _apply_move_captive(tool_item: Item) -> String:
	var species := tool_item.captive_species
	if species == "":
		return ""
	tool_item.captive_species = ""
	return species
