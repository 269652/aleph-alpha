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

const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const Item = preload("res://src/gameplay/item.gd")

## Container id -> which EXISTING curiosity item a caught species becomes
## once moved out of the tool. Reuses the exact split Player._capture_flyer
## already shipped (see AmbientFlyerRenderer.BIRD_SPECIES_POOL) rather than
## inventing new item ids -- a glass bottle is what you need to jar the
## catch, not a new kind of catch.
const _CURIOSITY_ITEM_FOR_BIRD := "caged_songbird"
const _CURIOSITY_ITEM_FOR_INSECT := "jarred_insect"


## Applies `atom_id` to `tool_item`. Returns true/false for a plain effect
## (hold_captive/release_captive); returns the resulting curiosity item id
## for move_captive (a String, "" if the tool had nothing to move), since
## the caller needs to know WHICH item to actually grant.
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
	if AmbientFlyerRenderer.BIRD_SPECIES_POOL.has(species):
		return _CURIOSITY_ITEM_FOR_BIRD
	return _CURIOSITY_ITEM_FOR_INSECT
