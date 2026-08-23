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
	# iron_helm/chest/legs/boots + fishing_rod + lasso.
	assert_eq(ids.size(), 15)


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
