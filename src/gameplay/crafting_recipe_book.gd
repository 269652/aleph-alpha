extends RefCounted

## Fixed table of craftable recipes. Deterministic -- no RNG, no station/skill
## gating yet (see docs/concept/crafting.md for the eventual blueprint DSL);
## this is the simple fixed-picklist precursor.

## recipe_id -> {"inputs": [{"item_id": String, "count": int}, ...], "output": {"item_id": String, "count": int}}
const _RECIPES := {
	"torch": {
		"inputs": [{"item_id": "wood", "count": 1}, {"item_id": "hide", "count": 1}],
		"output": {"item_id": "torch", "count": 2},
	},
	"wooden_club": {
		"inputs": [{"item_id": "wood", "count": 3}],
		"output": {"item_id": "wooden_club", "count": 1},
	},
	"campfire": {
		"inputs": [{"item_id": "wood", "count": 8}],
		"output": {"item_id": "campfire", "count": 1},
	},
	"cooked_meat": {
		"inputs": [{"item_id": "meat", "count": 1}],
		"output": {"item_id": "cooked_meat", "count": 1},
	},
	"crude_blade": {
		"inputs": [
			{"item_id": "stick", "count": 1},
			{"item_id": "sharp_shard", "count": 1},
			{"item_id": "plant_fibre", "count": 2},
		],
		"output": {"item_id": "crude_blade", "count": 1},
	},
	# Braided grass rope -- the entry point to taming (see
	# docs/concept/taming.md). Cheap on purpose: plant fibre comes from
	# harvesting mature tall grass, so starting costs a walk through a meadow.
	"lasso": {
		"inputs": [{"item_id": "plant_fibre", "count": 4}],
		"output": {"item_id": "lasso", "count": 1},
	},
	"stone_pickaxe": {
		"inputs": [
			{"item_id": "stick", "count": 2},
			{"item_id": "rock", "count": 3},
		],
		"output": {"item_id": "stone_pickaxe", "count": 1},
	},
	# Smelting & metalworking (see concept/smelting.md). The ingot recipes are
	# smelts (Smelting.is_smelting_recipe) -- Player.craft heat-gates them.
	"furnace": {
		"inputs": [{"item_id": "stone", "count": 8}],
		"output": {"item_id": "furnace", "count": 1},
	},
	"iron_ingot": {
		"inputs": [{"item_id": "iron_ore", "count": 1}, {"item_id": "coal", "count": 1}],
		"output": {"item_id": "iron_ingot", "count": 1},
	},
	"copper_ingot": {
		"inputs": [{"item_id": "copper_ore", "count": 1}, {"item_id": "coal", "count": 1}],
		"output": {"item_id": "copper_ingot", "count": 1},
	},
	"iron_helm": {
		"inputs": [{"item_id": "iron_ingot", "count": 2}],
		"output": {"item_id": "iron_helm", "count": 1},
	},
	"iron_chest": {
		"inputs": [{"item_id": "iron_ingot", "count": 4}],
		"output": {"item_id": "iron_chest", "count": 1},
	},
	"iron_legs": {
		"inputs": [{"item_id": "iron_ingot", "count": 3}],
		"output": {"item_id": "iron_legs", "count": 1},
	},
	"iron_boots": {
		"inputs": [{"item_id": "iron_ingot", "count": 1}],
		"output": {"item_id": "iron_boots", "count": 1},
	},
	"fishing_rod": {
		"inputs": [{"item_id": "stick", "count": 2}, {"item_id": "plant_fibre", "count": 2}],
		"output": {"item_id": "fishing_rod", "count": 1},
	},
}


## Every recipe_id this book knows, for a /help-style listing.
func recipe_ids() -> Array:
	return _RECIPES.keys()


## The input requirements of a recipe as an Array of {item_id, count} -- for
## the crafting UI to render "needs 2 stick, 3 rock". Empty for unknown ids.
func recipe_inputs(recipe_id: String) -> Array:
	if not _RECIPES.has(recipe_id):
		return []
	return _RECIPES[recipe_id]["inputs"].duplicate(true)


## The output of a recipe as {item_id, count}. Empty Dictionary for unknown.
func recipe_output(recipe_id: String) -> Dictionary:
	if not _RECIPES.has(recipe_id):
		return {}
	return _RECIPES[recipe_id]["output"].duplicate(true)


func can_craft(recipe_id: String, inventory_counts: Dictionary) -> bool:
	if not _RECIPES.has(recipe_id):
		return false
	for input in _RECIPES[recipe_id]["inputs"]:
		if inventory_counts.get(input["item_id"], 0) < input["count"]:
			return false
	return true


func craft(recipe_id: String, inventory_counts: Dictionary) -> Dictionary:
	if not can_craft(recipe_id, inventory_counts):
		return {
			"success": false,
			"output_item_id": "",
			"output_count": 0,
			"remaining_counts": inventory_counts.duplicate(),
		}
	var remaining := inventory_counts.duplicate()
	var recipe: Dictionary = _RECIPES[recipe_id]
	for input in recipe["inputs"]:
		remaining[input["item_id"]] -= input["count"]
	return {
		"success": true,
		"output_item_id": recipe["output"]["item_id"],
		"output_count": recipe["output"]["count"],
		"remaining_counts": remaining,
	}
