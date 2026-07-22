extends RefCounted

## Smelting: raw ore -> metal ingot, gated on a heat source (see
## concept/smelting.md). Pure lookup, mirroring CampfireCooking's shape. The
## ingot recipes themselves (ore + coal -> ingot) live in CraftingRecipeBook;
## this module says which recipes are smelts (so Player.craft can require heat)
## and which ore each ingot comes from. Item ids are registered in
## item_catalog.gd by the orchestrator.

## The fuel every smelt consumes (registered from mining).
const FUEL_ITEM := "coal"

## ore_item_id -> ingot_item_id.
const _SMELTS := {
	"iron_ore": "iron_ingot",
	"copper_ore": "copper_ingot",
}

## The crafting recipe ids that are smelts (their output is an ingot) -- these
## are the ones Player.craft heat-gates.
const _SMELTING_RECIPE_IDS := ["iron_ingot", "copper_ingot"]


## The ingot an ore smelts into, or "" if the item isn't smeltable.
func smelted_output(ore_item_id: String) -> String:
	return _SMELTS.get(ore_item_id, "")


## Whether a crafting recipe id is a smelt (vs. ordinary crafting/forging).
func is_smelting_recipe(recipe_id: String) -> bool:
	return _SMELTING_RECIPE_IDS.has(recipe_id)


## Whether a smelt can proceed: it must be an actual smelting recipe AND a heat
## source must be present. (Fuel/ore availability is checked by CraftingRecipeBook.)
func can_smelt(recipe_id: String, near_heat: bool) -> bool:
	return is_smelting_recipe(recipe_id) and near_heat
