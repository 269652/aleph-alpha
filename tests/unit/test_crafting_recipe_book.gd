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
	# + production chains (see docs/concept/production_chains.md): the
	# Sägewerk's own log_to_balken/log_to_planke shaping recipes (2 more),
	# pinned to agree with SagewerkProduction's real cost constants.
	# + storage (see docs/concept/timber_construction.md's "Storage,
	# logistics, and the autonomous dependency chain" section, 1 more).
	assert_eq(ids.size(), 32)


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


## Storage (see docs/concept/timber_construction.md's "Storage, logistics,
## and the autonomous dependency chain" section): a small lumber shed, costed
## in wood (the frame) and plank (the walls/shelving) -- both real,
## already-craftable woodworking materials, no new item type needed. No
## skill gate, matching the doc section's own explicit note that only the
## Sägewerk-equivalent production step is skill-gated, not Storage itself.
func test_storage_recipe_uses_wood_and_plank():
	assert_true(book.recipe_ids().has("storage"), "storage must be craftable")
	assert_eq(book.recipe_output("storage")["item_id"], "storage")
	assert_false(book.can_craft("storage", {"wood": 12, "plank": 1}))
	assert_true(book.can_craft("storage", {"wood": 12, "plank": 4}))


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


# -- production chains (see docs/concept/production_chains.md): the two -----
# -- new OPTIONAL recipe fields, "required_skill" and "requires_structure" --
# -- (purely additive -- every recipe above that doesn't declare them must ---
# -- keep working exactly as it does today), plus a reverse output->recipe --
# -- lookup for NeedResolver's recursive walk. -------------------------------

## Regression: a recipe with neither new field (torch has always been a
## plain 2-input recipe) reports empty/absent for both -- the additive
## fields must never silently invent a gate nothing declared.
func test_recipes_without_the_new_fields_report_no_gate_and_still_craft():
	assert_eq(book.recipe_required_skill("torch"), {})
	assert_eq(book.recipe_requires_structure("torch"), "")
	# The exact same regression assertions the original torch tests already
	# make -- proving the additive fields changed nothing about existing
	# can_craft/craft behavior.
	assert_true(book.can_craft("torch", {"wood": 1, "hide": 1}))
	var result := book.craft("torch", {"wood": 1, "hide": 1})
	assert_true(result["success"])


func test_recipe_required_skill_of_unknown_recipe_is_empty():
	assert_eq(book.recipe_required_skill("not_a_real_recipe"), {})


func test_recipe_requires_structure_of_unknown_recipe_is_empty_string():
	assert_eq(book.recipe_requires_structure("not_a_real_recipe"), "")


## The Sägewerk itself needs a real carpenter's eye to raise (see
## docs/concept/timber_construction.md's own "generalized, not hardcoded"
## section) -- required_skill's first real consumer. Pinned to the SAME
## real threshold Player._chop_step's CARPENTRY_LEVEL_FOR_SAWING already
## uses for the same real skill (carpentry_level), not a second invented
## number for it.
func test_sagewerk_requires_carpentry_skill_matching_the_existing_sawing_threshold():
	const PlayerScene = preload("res://scenes/player.tscn")
	var player: Player = PlayerScene.instantiate()
	var requirement: Dictionary = book.recipe_required_skill("sagewerk")
	assert_eq(requirement["stat_name"], "carpentry_level")
	assert_eq(requirement["level"], player.CARPENTRY_LEVEL_FOR_SAWING)
	player.free()


## Smelting recipes are heat-gated (a campfire OR a furnace both count --
## see Player._has_heat_source) -- requires_structure names the abstract
## "heat_source" category smelting.md itself already uses as its own
## vocabulary ("a heat source present: a campfire, or the sturdier crafted
## furnace"), not one specific structure id, so Player.craft's generalized
## check can still accept either the same way it always has.
func test_smelting_recipes_require_a_heat_source():
	assert_eq(book.recipe_requires_structure("iron_ingot"), "heat_source")
	assert_eq(book.recipe_requires_structure("copper_ingot"), "heat_source")


func test_recipe_for_output_finds_the_recipe_that_produces_an_item():
	assert_eq(book.recipe_for_output("torch"), "torch")
	assert_eq(book.recipe_for_output("stick"), "log_to_sticks")


## The bottom case NeedResolver's recursive walk relies on: an item nothing
## in this book produces (e.g. a raw, gathered item like "log") -- "go get
## it from the world," not a broken lookup.
func test_recipe_for_output_is_empty_for_an_item_no_recipe_produces():
	assert_eq(book.recipe_for_output("log"), "")
	assert_eq(book.recipe_for_output("not_a_real_item"), "")


## Sägewerk production (SagewerkProduction, log -> Balken/Planke) is a
## real, separately-tested pure module (see docs/concept/timber_
## construction.md's "Sägewerk production" status entry) that the
## Lumberjack-staffed mill runs continuously -- deliberately NOT rerouted
## through CraftingRecipeBook this pass (see production_chains.md's own
## "narrowing" note). These two recipe entries exist ONLY so NeedResolver
## can reason about beam/plank's real dependency chain; they must agree
## with SagewerkProduction's own real cost constants so the two data
## sources never silently disagree.
func test_log_to_balken_and_log_to_planke_agree_with_sagewerk_production_costs():
	const SagewerkProduction = preload("res://src/world/sagewerk_production.gd")

	assert_true(book.recipe_ids().has("log_to_balken"))
	assert_true(book.recipe_ids().has("log_to_planke"))
	assert_eq(book.recipe_output("log_to_balken")["item_id"], "beam")
	assert_eq(book.recipe_output("log_to_planke")["item_id"], "plank")

	var balken_inputs := book.recipe_inputs("log_to_balken")
	assert_eq(balken_inputs.size(), 1)
	assert_eq(balken_inputs[0]["item_id"], "log")
	assert_eq(balken_inputs[0]["count"], int(SagewerkProduction.LOG_COST_PER_BEAM))

	var planke_inputs := book.recipe_inputs("log_to_planke")
	assert_eq(planke_inputs.size(), 1)
	assert_eq(planke_inputs[0]["item_id"], "log")
	assert_eq(planke_inputs[0]["count"], int(SagewerkProduction.LOG_COST_PER_PLANK))

	assert_eq(book.recipe_requires_structure("log_to_balken"), "sagewerk")
	assert_eq(book.recipe_requires_structure("log_to_planke"), "sagewerk")
