extends RefCounted

## The dependency-chain priority decision from docs/concept/timber_
## construction.md's "Storage, logistics, and the autonomous dependency
## chain" section: given a target recipe and what a settlement has on hand
## right now, decide whether the real priority should be "build the missing
## producer first" or "the existing shortfall/regional-trade path already
## covers this".
##
## Honesty note: the task this was built from named a general NeedResolver
## module as the thing to call here -- no such module exists yet in this
## codebase (see this doc section's own gap note). This is a minimal,
## self-contained equivalent scoped to exactly this one decision, composing
## two already-real mechanisms directly rather than reinventing a general
## resolver: CraftingRecipeBook's real recipe data, and Smelting.can_smelt's
## already-proven "is this recipe gated on a present structure" check (the
## same one Player.craft already uses to heat-gate smelting for the player,
## see scenes/player.gd's _has_heat_source). A real NeedResolver, if/when one
## exists, is the more general tool this narrow function should be rebuilt
## on top of instead of duplicating.

const Smelting = preload("res://src/gameplay/smelting.gd")

enum Priority { READY, BUILD_PRODUCER_FIRST, SHORTFALL }

## Structures that satisfy a smelting recipe's heat-source gate -- mirrors
## Player._has_heat_source's own "campfire or furnace" check exactly (see
## scenes/player.gd), so this settlement-level decision agrees with the
## player-facing one rather than diverging on what counts as a heat source.
const _HEAT_SOURCE_STRUCTURE_IDS := ["campfire", "furnace"]

var _smelting := Smelting.new()


## Decides the priority for building `recipe_id` given `local_stock`
## (item_id -> count) and `present_structure_ids` (structures already known
## to be present nearby, e.g. from EarthChunkManager.has_structure_near
## checks). An unknown recipe id is treated as READY -- there is nothing
## real this function can meaningfully block an unknown recipe on.
func decide(recipe_id: String, local_stock: Dictionary, present_structure_ids: Array, recipe_book) -> int:
	if not recipe_book.recipe_ids().has(recipe_id):
		return Priority.READY
	if _smelting.is_smelting_recipe(recipe_id) and not _has_heat_source(present_structure_ids):
		return Priority.BUILD_PRODUCER_FIRST
	if recipe_book.can_craft(recipe_id, local_stock):
		return Priority.READY
	return Priority.SHORTFALL


func _has_heat_source(present_structure_ids: Array) -> bool:
	for structure_id in _HEAT_SOURCE_STRUCTURE_IDS:
		if present_structure_ids.has(structure_id):
			return true
	return false
