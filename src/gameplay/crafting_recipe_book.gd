extends RefCounted

## Fixed table of craftable recipes. Deterministic -- no RNG. Station/skill
## gating is now real but OPTIONAL per recipe (see docs/concept/
## production_chains.md): a recipe MAY declare "required_skill" (a
## SkillTree stat_name + level threshold) and/or "requires_structure" (a
## structure id that must be built/nearby) -- Player.craft reads both
## generically (recipe_required_skill/recipe_requires_structure below), so
## every future recipe gets the same real gating for free just by declaring
## the field, no new hardcoded branch per recipe. Neither field is a fixed
## picklist replacement -- see docs/concept/crafting.md for the eventual
## blueprint DSL this remains a simple precursor to.

## recipe_id -> {
##   "inputs": [{"item_id": String, "count": int}, ...],
##   "output": {"item_id": String, "count": int},
##   "required_skill": {"stat_name": String, "level": float},  # OPTIONAL
##   "requires_structure": String,                             # OPTIONAL
## }
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
	# smelts (Smelting.is_smelting_recipe) -- Player.craft heat-gates them via
	# requires_structure's "heat_source" category (see docs/concept/
	# production_chains.md): smelting.md's own vocabulary is "a heat source
	# present -- a campfire, or the sturdier crafted furnace" -- EITHER
	# counts (Player._has_heat_source), so this names the abstract category,
	# not one specific structure id.
	"furnace": {
		"inputs": [{"item_id": "stone", "count": 8}],
		"output": {"item_id": "furnace", "count": 1},
	},
	"iron_ingot": {
		"inputs": [{"item_id": "iron_ore", "count": 1}, {"item_id": "coal", "count": 1}],
		"output": {"item_id": "iron_ingot", "count": 1},
		"requires_structure": "heat_source",
	},
	"copper_ingot": {
		"inputs": [{"item_id": "copper_ore", "count": 1}, {"item_id": "coal", "count": 1}],
		"output": {"item_id": "copper_ingot", "count": 1},
		"requires_structure": "heat_source",
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
	# Woodworking (see docs/concept/woodworking.md): a bucked log refines
	# further at the bench -- no tool/skill gate, that's reserved for the
	# in-world saw+Carpentry beam/plank path (ChoppableTree.saw_up). Keeps
	# every existing wood-consuming recipe above reachable now that a bare
	# trunk yields logs instead of wood directly.
	"log_to_sticks": {
		"inputs": [{"item_id": "log", "count": 1}],
		"output": {"item_id": "stick", "count": 3},
	},
	"log_to_wood": {
		"inputs": [{"item_id": "log", "count": 1}],
		"output": {"item_id": "wood", "count": 2},
	},
	"saw": {
		"inputs": [{"item_id": "wood", "count": 2}, {"item_id": "rock", "count": 2}],
		"output": {"item_id": "saw", "count": 1},
	},
	# Sägewerk (sawmill worksite -- see docs/concept/timber_construction.md):
	# built from real gathered logs, not conjured wood, so raising the
	# sawmill itself already draws on the same felling pipeline it later
	# feeds. Once placed, an NPC Lumberjack moves in and staffs it.
	# required_skill (docs/concept/production_chains.md): a real carpenter's
	# eye to raise a sawmill, not just materials -- pinned to the SAME
	# carpentry_level threshold Player._chop_step's own
	# CARPENTRY_LEVEL_FOR_SAWING already gates the in-world saw+Carpentry
	# beam/plank shortcut on, not a second invented number for the same
	# real skill (see docs/concept/timber_construction.md's own
	# "generalized, not hardcoded" section).
	"sagewerk": {
		"inputs": [{"item_id": "log", "count": 8}, {"item_id": "wood", "count": 4}],
		"output": {"item_id": "sagewerk", "count": 1},
		"required_skill": {"stat_name": "carpentry_level", "level": 2.0},
	},
	# The Sägewerk's own log -> Balken/Planke shaping, mirrored here ONLY so
	# NeedResolver (docs/concept/production_chains.md) can reason about
	# beam/plank's real dependency chain -- the Sägewerk's actual, already-
	# tested production (SagewerkProduction.advance, staffed by its
	# Lumberjack) stays bespoke and untouched; a player does not craft these
	# by hand at a bench. Input counts are pinned to agree with
	# SagewerkProduction.LOG_COST_PER_BEAM/LOG_COST_PER_PLANK so the two
	# never silently disagree (test_crafting_recipe_book.gd asserts this).
	"log_to_balken": {
		"inputs": [{"item_id": "log", "count": 3}],
		"output": {"item_id": "beam", "count": 1},
		"requires_structure": "sagewerk",
	},
	"log_to_planke": {
		"inputs": [{"item_id": "log", "count": 1}],
		"output": {"item_id": "plank", "count": 1},
		"requires_structure": "sagewerk",
	},
	# Wayfinding & citizenship instruments (see docs/concept/wayfinding.md,
	# docs/concept/player_citizenship.md). Every input below is an existing
	# raw-material item id already in item_catalog.gd's _ITEMS -- no new
	# material id is invented here.
	#
	# rough_compass is the cheap wood/fibre precursor; compass is the fine-
	# reading upgrade that requires a real metal ingot as the
	# material-quality step up (see docs/concept/wayfinding.md's rough vs.
	# fine bearing distinction, and Compass.rough_reading/fine_reading).
	"rough_compass": {
		"inputs": [{"item_id": "stick", "count": 1}, {"item_id": "plant_fibre", "count": 2}],
		"output": {"item_id": "rough_compass", "count": 1},
	},
	"compass": {
		"inputs": [{"item_id": "iron_ingot", "count": 1}, {"item_id": "stick", "count": 1}],
		"output": {"item_id": "compass", "count": 1},
	},
	"map": {
		"inputs": [{"item_id": "hide", "count": 1}, {"item_id": "plant_fibre", "count": 1}],
		"output": {"item_id": "map", "count": 1},
	},
	"spyglass": {
		"inputs": [{"item_id": "copper_ingot", "count": 2}, {"item_id": "stick", "count": 1}],
		"output": {"item_id": "spyglass", "count": 1},
	},
	"weather_glass": {
		"inputs": [{"item_id": "copper_ingot", "count": 1}, {"item_id": "coal", "count": 1}],
		"output": {"item_id": "weather_glass", "count": 1},
	},
	"star_chart": {
		"inputs": [{"item_id": "plank", "count": 1}, {"item_id": "hide", "count": 1}],
		"output": {"item_id": "star_chart", "count": 1},
	},
	"deed": {
		"inputs": [{"item_id": "hide", "count": 2}, {"item_id": "plant_fibre", "count": 1}],
		"output": {"item_id": "deed", "count": 1},
	},
	"ledger": {
		"inputs": [{"item_id": "plank", "count": 1}, {"item_id": "plant_fibre", "count": 2}],
		"output": {"item_id": "ledger", "count": 1},
	},
	"field_journal": {
		"inputs": [{"item_id": "hide", "count": 1}, {"item_id": "stick", "count": 1}],
		"output": {"item_id": "field_journal", "count": 1},
	},
	"charter": {
		"inputs": [
			{"item_id": "plank", "count": 1},
			{"item_id": "hide", "count": 1},
			{"item_id": "plant_fibre", "count": 1},
		],
		"output": {"item_id": "charter", "count": 1},
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


## A recipe's OPTIONAL skill gate as {stat_name, level} -- empty Dictionary
## for a recipe with no gate (the common case) or an unknown recipe_id. See
## docs/concept/production_chains.md: Player.craft reads this generically
## via SkillTree.total_bonus(stat_name, allocated_nodes), the exact pattern
## CARPENTRY_LEVEL_FOR_SAWING already uses.
func recipe_required_skill(recipe_id: String) -> Dictionary:
	if not _RECIPES.has(recipe_id):
		return {}
	var recipe: Dictionary = _RECIPES[recipe_id]
	return recipe.get("required_skill", {}).duplicate(true)


## A recipe's OPTIONAL structure gate -- the structure id that must be
## built/nearby (see EarthChunkManager.has_structure_near), or "" for a
## recipe with no gate (the common case) or an unknown recipe_id. See
## docs/concept/production_chains.md. "heat_source" is the one abstract
## category value (campfire OR furnace, see Player._has_heat_source) --
## every other value names one real, specific structure id.
func recipe_requires_structure(recipe_id: String) -> String:
	if not _RECIPES.has(recipe_id):
		return ""
	var recipe: Dictionary = _RECIPES[recipe_id]
	return recipe.get("requires_structure", "")


## Reverse lookup: the recipe_id whose output produces `item_id`, or "" if
## nothing in this book produces it -- NeedResolver's own bottom case ("go
## get it from the world" for a raw/gathered item like log/stone/hide,
## rather than a broken lookup). First match wins; no two recipes here
## currently share an output item_id.
func recipe_for_output(item_id: String) -> String:
	for recipe_id in _RECIPES:
		var recipe: Dictionary = _RECIPES[recipe_id]
		if recipe["output"]["item_id"] == item_id:
			return recipe_id
	return ""


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
