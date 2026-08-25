extends GutTest

const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var book: CraftingRecipeBook


func before_each():
	book = CraftingRecipeBook.new()


func test_recipe_ids_returns_all_defined_recipes():
	var ids := book.recipe_ids()
	assert_true(ids.has("torch"))
	assert_true(ids.has("wooden_club"))
	assert_true(ids.has("campfire"))
	assert_true(ids.has("cooked_meat"))
	assert_true(ids.has("crude_blade"))
	assert_true(ids.has("stone_pickaxe"))
	assert_true(ids.has("lasso"))
	# + smelting/forge recipes: furnace, iron_ingot, copper_ingot,
	# iron_helm/chest/legs/boots + fishing_rod + lasso
	# + woodworking: log_to_sticks, log_to_wood, saw, sagewerk.
	# + wayfinding & citizenship: rough_compass, compass, map, spyglass,
	# weather_glass, star_chart, deed, ledger, field_journal, charter (10 more).
	assert_eq(ids.size(), 29)


func test_can_craft_true_when_inventory_has_enough_inputs():
	var inventory := {"wood": 1, "hide": 1}
	assert_true(book.can_craft("torch", inventory))


func test_can_craft_true_with_exact_amounts_needed():
	var inventory := {"wood": 3}
	assert_true(book.can_craft("wooden_club", inventory))


func test_can_craft_false_when_short_on_one_input():
	var inventory := {"wood": 1, "hide": 0}
	assert_false(book.can_craft("torch", inventory))


func test_can_craft_false_when_missing_an_input_entirely():
	var inventory := {"wood": 5}
	assert_false(book.can_craft("torch", inventory))


func test_can_craft_false_for_unknown_recipe_id():
	var inventory := {"wood": 100, "hide": 100}
	assert_false(book.can_craft("not_a_real_recipe", inventory))


func test_craft_succeeds_and_deducts_exact_input_amounts():
	var inventory := {"wood": 1, "hide": 1}
	var result := book.craft("torch", inventory)
	assert_true(result["success"])
	assert_eq(result["output_item_id"], "torch")
	assert_eq(result["output_count"], 2)
	assert_eq(result["remaining_counts"]["wood"], 0)
	assert_eq(result["remaining_counts"]["hide"], 0)


func test_craft_leaves_unrelated_items_untouched():
	var inventory := {"wood": 3, "meat": 5}
	var result := book.craft("wooden_club", inventory)
	assert_true(result["success"])
	assert_eq(result["remaining_counts"]["wood"], 0)
	assert_eq(result["remaining_counts"]["meat"], 5)


func test_craft_fails_and_leaves_inventory_untouched_when_short_on_input():
	var inventory := {"wood": 1, "hide": 0}
	var result := book.craft("torch", inventory)
	assert_false(result["success"])
	assert_eq(result["remaining_counts"], {"wood": 1, "hide": 0})


func test_craft_fails_gracefully_for_unknown_recipe_id():
	var inventory := {"wood": 100}
	var result := book.craft("not_a_real_recipe", inventory)
	assert_false(result["success"])
	assert_eq(result["remaining_counts"], {"wood": 100})


func test_craft_does_not_mutate_callers_original_dictionary():
	var inventory := {"wood": 3}
	book.craft("wooden_club", inventory)
	assert_eq(inventory["wood"], 3)


func test_craft_single_input_recipe_deducts_correctly():
	var inventory := {"meat": 1}
	var result := book.craft("cooked_meat", inventory)
	assert_true(result["success"])
	assert_eq(result["output_item_id"], "cooked_meat")
	assert_eq(result["output_count"], 1)
	assert_eq(result["remaining_counts"]["meat"], 0)


func test_crude_blade_recipe_uses_stick_shard_and_fibre():
	assert_true(book.recipe_ids().has("crude_blade"))
	assert_false(book.can_craft("crude_blade", {"stick": 1, "sharp_shard": 1}))
	var inventory := {"stick": 1, "sharp_shard": 1, "plant_fibre": 2}
	assert_true(book.can_craft("crude_blade", inventory))
	var result: Dictionary = book.craft("crude_blade", inventory)
	assert_true(result["success"])
	assert_eq(result["output_item_id"], "crude_blade")
	assert_eq(result["remaining_counts"].get("stick", 0), 0)
	assert_eq(result["remaining_counts"].get("sharp_shard", 0), 0)
	assert_eq(result["remaining_counts"].get("plant_fibre", 0), 0)


func test_recipe_inputs_and_output_expose_details_for_display():
	var inputs = book.recipe_inputs("crude_blade")
	assert_eq(inputs.size(), 3)
	var ids := []
	for i in inputs:
		ids.append(i["item_id"])
	assert_true(ids.has("stick"))
	assert_true(ids.has("sharp_shard"))
	assert_true(ids.has("plant_fibre"))

	var output = book.recipe_output("crude_blade")
	assert_eq(output["item_id"], "crude_blade")
	assert_eq(output["count"], 1)


func test_recipe_inputs_of_unknown_recipe_is_empty():
	assert_eq(book.recipe_inputs("nope").size(), 0)
	assert_true(book.recipe_output("nope").is_empty())


func test_stone_pickaxe_recipe_uses_sticks_and_rocks():
	assert_true(book.recipe_ids().has("stone_pickaxe"))
	assert_false(book.can_craft("stone_pickaxe", {"stick": 1}))
	assert_true(book.can_craft("stone_pickaxe", {"stick": 2, "rock": 3}))


# -- woodworking (see docs/concept/woodworking.md) ---------------------------
#
# A log refines two ways at the bench, no tool/skill gate (see
# ChoppableTree.saw_up for the gated, in-world beam/plank path instead):
# more kindling, or the plain wood every existing wood-consuming recipe
# (torch/wooden_club/campfire/...) still needs, so that supply is never cut
# off just because bare-trunk chopping now yields logs instead of wood.

func test_log_splits_into_sticks():
	assert_true(book.recipe_ids().has("log_to_sticks"))
	assert_true(book.can_craft("log_to_sticks", {"log": 1}))
	assert_eq(book.recipe_output("log_to_sticks")["item_id"], "stick")


func test_log_converts_into_wood():
	assert_true(book.recipe_ids().has("log_to_wood"))
	assert_true(book.can_craft("log_to_wood", {"log": 1}))
	assert_eq(book.recipe_output("log_to_wood")["item_id"], "wood")


func test_saw_is_craftable():
	assert_true(book.recipe_ids().has("saw"))
	assert_eq(book.recipe_output("saw")["item_id"], "saw")


## The Sägewerk worksite (see docs/concept/timber_construction.md) -- a
## placeable structure, same shape as campfire/furnace, that a player builds
## from real gathered logs so an NPC Lumberjack can move in and staff it.
func test_sagewerk_is_craftable_from_logs():
	assert_true(book.recipe_ids().has("sagewerk"))
	assert_eq(book.recipe_output("sagewerk")["item_id"], "sagewerk")
	var inputs = book.recipe_inputs("sagewerk")
	var ids := []
	for i in inputs:
		ids.append(i["item_id"])
	assert_true(ids.has("log"), "a sawmill should be built from real logs, not conjured wood")


func test_smelting_and_forge_recipes_exist():
	assert_true(book.recipe_ids().has("iron_ingot"))
	assert_true(book.recipe_ids().has("furnace"))
	assert_true(book.recipe_ids().has("iron_chest"))
	assert_true(book.can_craft("iron_ingot", {"iron_ore": 1, "coal": 1}))
	assert_false(book.can_craft("iron_ingot", {"iron_ore": 1}))
	var chest_inputs = book.recipe_inputs("iron_chest")
	var ids := []
	for i in chest_inputs:
		ids.append(i["item_id"])
	assert_true(ids.has("iron_ingot"))


## The lasso is the entry point to taming (docs/concept/taming.md) and is
## deliberately cheap: plant fibre comes from harvesting mature tall grass,
## so the cost of starting is a walk through a meadow rather than a tech tree.
func test_a_lasso_is_braided_from_plant_fibre():
	assert_true(book.recipe_ids().has("lasso"), "the lasso must be craftable")
	assert_eq(book.recipe_output("lasso")["item_id"], "lasso")
	var inputs := book.recipe_inputs("lasso")
	assert_eq(inputs.size(), 1, "fibre and nothing else")
	assert_eq(inputs[0]["item_id"], "plant_fibre")
	assert_eq(inputs[0]["count"], 4)


# -- wayfinding & citizenship instruments (see docs/concept/wayfinding.md, --
# -- docs/concept/player_citizenship.md) -- every recipe below uses ONLY -----
# -- existing raw-material item ids (stick, plant_fibre, hide, iron_ingot, ---
# -- copper_ingot, coal, plank) already present in item_catalog.gd's -------
# -- _ITEMS -- no new raw material id is invented for this pass. -------------

func _input_item_ids(recipe_id: String) -> Array:
	var ids := []
	for i in book.recipe_inputs(recipe_id):
		ids.append(i["item_id"])
	return ids


func test_wayfinding_and_citizenship_recipes_exist_and_are_craftable():
	var recipe_ids_and_output := {
		"rough_compass": "rough_compass",
		"compass": "compass",
		"map": "map",
		"spyglass": "spyglass",
		"weather_glass": "weather_glass",
		"star_chart": "star_chart",
		"deed": "deed",
		"ledger": "ledger",
		"field_journal": "field_journal",
		"charter": "charter",
	}
	for recipe_id in recipe_ids_and_output:
		assert_true(book.recipe_ids().has(recipe_id), "missing recipe %s" % recipe_id)
		assert_eq(book.recipe_output(recipe_id)["item_id"], recipe_ids_and_output[recipe_id])


## rough_compass is the cheap, low-material precursor -- crafted from stick +
## plant_fibre, not a metal ingot (see compass below for the upgrade).
func test_rough_compass_uses_only_cheap_raw_materials():
	var ids := _input_item_ids("rough_compass")
	assert_true(ids.has("stick"))
	assert_true(ids.has("plant_fibre"))
	assert_false(ids.has("iron_ingot"))
	assert_true(book.can_craft("rough_compass", {"stick": 1, "plant_fibre": 2}))


## compass is the fine-reading upgrade over rough_compass -- it requires a
## real metal ingot (iron_ingot already exists in _ITEMS) as the
## material-quality step up from rough_compass's cheap wood/fibre build.
func test_compass_requires_a_real_metal_ingot():
	var ids := _input_item_ids("compass")
	assert_true(ids.has("iron_ingot"), "compass should require a metal ingot")
	assert_true(book.can_craft("compass", {"iron_ingot": 1, "stick": 1}))


func test_map_is_craftable_from_hide_and_plant_fibre():
	assert_true(book.can_craft("map", {"hide": 1, "plant_fibre": 1}))


func test_spyglass_is_craftable_from_copper_ingot_and_stick():
	assert_true(book.can_craft("spyglass", {"copper_ingot": 2, "stick": 1}))


func test_weather_glass_is_craftable_from_copper_ingot_and_coal():
	assert_true(book.can_craft("weather_glass", {"copper_ingot": 1, "coal": 1}))


func test_star_chart_is_craftable_from_plank_and_hide():
	assert_true(book.can_craft("star_chart", {"plank": 1, "hide": 1}))


func test_deed_is_craftable_from_hide_and_plant_fibre():
	assert_true(book.can_craft("deed", {"hide": 2, "plant_fibre": 1}))


func test_ledger_is_craftable_from_plank_and_plant_fibre():
	assert_true(book.can_craft("ledger", {"plank": 1, "plant_fibre": 2}))


func test_field_journal_is_craftable_from_hide_and_stick():
	assert_true(book.can_craft("field_journal", {"hide": 1, "stick": 1}))


## Charter is the "founds/joins a real Institution" item -- deliberately the
## most materially demanding of the four citizenship items (plank + hide +
## plant_fibre, a real 3-input recipe unlike deed/ledger/field_journal's
## 2-input ones), matching that founding an institution is a bigger step
## than claiming property or proposing one contract.
func test_charter_is_craftable_from_plank_hide_and_plant_fibre():
	assert_true(book.can_craft("charter", {"plank": 1, "hide": 1, "plant_fibre": 1}))


## Every input item id across all 10 new recipes must already exist in
## item_catalog.gd -- no new raw material id invented for this pass.
func test_wayfinding_and_citizenship_recipes_use_only_existing_raw_materials():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	var new_recipe_ids := [
		"rough_compass", "compass", "map", "spyglass", "weather_glass",
		"star_chart", "deed", "ledger", "field_journal", "charter",
	]
	for recipe_id in new_recipe_ids:
		for item_id in _input_item_ids(recipe_id):
			assert_true(catalog.has(item_id), "%s recipe uses unknown material %s" % [recipe_id, item_id])
