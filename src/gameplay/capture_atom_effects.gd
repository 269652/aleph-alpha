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
## already reported which effects apply). This only carries them out.

const Item = preload("res://src/gameplay/item.gd")


## Applies `atom_id` to `tool_item`. Returns true/false for a plain effect
## (hold_captive/release_captive); returns the species that moved for
## move_captive (a String, "" if the tool had nothing to move) -- NOT a
## generic curiosity item id. The species has to survive the move so the
## container it lands on can still be rendered as the specific creature
## it holds (docs/concept/capture_dsl.md's "Rendering a bottled catch");
## the caller (Player) is the one who puts it on a fresh container item,
## the same relocation hold_captive already does the other direction.
func apply_to_target(atom_id: String, params: Dictionary, tool_item: Item, context: Dictionary) -> Variant:
	match atom_id:
		"hold_captive":
			return _apply_hold_captive(tool_item, context)
		"release_captive":
			return _apply_release_captive(tool_item)
		"move_captive":
			return _apply_move_captive(tool_item)
		_:
			return false


func _apply_hold_captive(tool_item: Item, context: Dictionary) -> bool:
	var target: Dictionary = context.get("target", {})
	tool_item.captive_species = String(target.get("species", ""))
	return true


func _apply_release_captive(tool_item: Item) -> bool:
	tool_item.captive_species = ""
	return true


func _apply_move_captive(tool_item: Item) -> String:
	var species := tool_item.captive_species
	if species == "":
		return ""
	tool_item.captive_species = ""
	return species
