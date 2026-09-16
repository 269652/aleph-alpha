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
	# + "any animal, the right tool" (docs/concept/taming.md): snare,
	# butterfly_net, trap, reinforced_rope (4 more).
	# + transportation (docs/concept/transportation.md): climbing_rope (1 more).
	# + rivers (docs/concept/rivers.md): stone_dam (1 more).
	# + starting kit (docs/concept/starting_kit.md): iron_sword, iron_axe
	# (2 more) -- both previously had NO recipe at all, reachable only via
	# /give, the shop, or the old hardcoded starting-kit grant.
	# + Storm Lantern (docs/concept/lighting.md): lantern (1 more) -- the
	# weatherproof second light source, upgraded from a torch.
	# + NPC farm production (docs/concept/npc_farm_production.md): farm and
	# wooden_fence (2 more) -- a Farmer moves in and works the farm once a
	# real fence stands nearby, mirroring the Sagewerk.
	# + workforce (docs/concept/workforce.md): small_house, the first
	# blueprint-gated, multi-piece construction-ledger recipe, and cottage,
	# its second tier (2 more), and manor, the third tier reached via
	# carpentry_1/carpentry_2/master_joiner (1 more).
	# + two-story houses (docs/concept/housing.md): townhouse_narrow,
	# merchant_house, guild_hall, riverside_villa, timber_longhouse,
	# artisan_workshop_house, tower_keep, harborside_manor, grand_estate,
	# gambrel_lodge -- ten real second-storey shapes at the same
	# carpentry_level 3.0 ceiling manor already uses (10 more).
	# + the City Hall (docs/concept/civic_construction.md's own "Meeting
	# Hall" spec, docs/concept/npc_role_consensus.md): a settlement's real
	# civic seat (1 more).
	# + milling and baking (docs/concept/milling_and_baking.md): mill and
	# bakery structures, plus the chain's three resolver recipes grow_wheat/
	# mill_flour/bake_bread (5 more).
	# + the village growth ladder (docs/concept/village_growth.md): sawmill,
	# farmhouse, warehouse, blacksmith and brewery -- the buildings a village
	# raises as its population grows, each priced only in the wood/stone/
	# plant_fibre its own spare hands actually gather (5 more).
	assert_eq(ids.size(), 67)


func test_iron_sword_is_craftable_from_ingots_and_a_stick():
	var inputs := book.recipe_inputs("iron_sword")
	assert_eq(inputs, [{"item_id": "iron_ingot", "count": 2}, {"item_id": "stick", "count": 1}])
	assert_eq(book.recipe_output("iron_sword"), {"item_id": "iron_sword", "count": 1})


func test_iron_axe_is_craftable_from_ingots_and_a_stick():
	var inputs := book.recipe_inputs("iron_axe")
	assert_eq(inputs, [{"item_id": "iron_ingot", "count": 2}, {"item_id": "stick", "count": 1}])
	assert_eq(book.recipe_output("iron_axe"), {"item_id": "iron_axe", "count": 1})


func test_neither_new_iron_recipe_requires_a_structure():
	# Matches every other iron-tier recipe's own precedent (iron_helm/chest/
	# legs/boots): shaping an already-smelted ingot needs no further gate.
	assert_eq(book.recipe_requires_structure("iron_sword"), "")
	assert_eq(book.recipe_requires_structure("iron_axe"), "")


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


## The first blueprint-gated house (docs/concept/workforce.md's "Recipe-
## gated construction" section): deliberately ONE full carpentry_1 node
## below the sagewerk's own carpentry_level 2.0, so a player's very first
## blueprint is buildable with a single skill-web allocation. This recipe is
## never routed through Player.craft() (a house is a real multi-piece
## ConstructionProject, not a single craftable item) -- its "output" is
## symbolic of the structure the construction ledger tracks, the same
## framing ConstructionProject.blueprint_id's own doc comment already uses
## for sagewerk/storage, and it is deliberately NOT also an ItemCatalog
## entry, since nothing ever holds a "small_house" in a bag.
func test_small_house_recipe_requires_carpentry_one_level_below_sagewerk():
	assert_true(book.recipe_ids().has("small_house"))
	assert_eq(book.recipe_output("small_house")["item_id"], "small_house")
	var required_skill := book.recipe_required_skill("small_house")
	assert_eq(required_skill["stat_name"], "carpentry_level")
	assert_eq(required_skill["level"], 1.0)


## Pinned to agree with HouseBlueprint's own real "hut_tiny" piece list (the
## smallest catalog shape -- see house_blueprint.gd's own BLUEPRINT_IDS),
## costed through the exact same BuildingPiece.cost_of every other piece in
## the game already prices through -- the same "two real numbers must agree,
## tested" discipline test_log_to_balken_and_log_to_planke_agree_with_
## sagewerk_production_costs already established for the Sägewerk's own
## shaping recipes. hut_tiny has zero windows, so its total cost does not
## depend on which seed places its one door -- every wall cell costs the
## same regardless of which one becomes the door.
func test_small_house_recipe_inputs_agree_with_the_hut_tiny_blueprints_real_cost():
	const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
	const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
	var house_blueprint := HouseBlueprint.new()
	var total_wood := 0
	for pieces in [house_blueprint.build("hut_tiny", 0), house_blueprint.build_roofs("hut_tiny", 0)]:
		for cell in pieces:
			var cost: Dictionary = BuildingPiece.cost_of(pieces[cell])
			total_wood += int(cost.get("wood", 0))
	assert_gt(total_wood, 0, "precondition: hut_tiny really does cost real wood")

	var inputs := book.recipe_inputs("small_house")
	assert_eq(inputs.size(), 1, "hut_tiny is an all-wood shape -- one input, no invented second material")
	assert_eq(inputs[0]["item_id"], "wood")
	assert_eq(inputs[0]["count"], total_wood)


## The second tier (docs/concept/workforce.md's "Blueprint tiers" section):
## the SAME ceiling the sagewerk recipe itself uses (carpentry_level 2.0),
## not an invented harder number -- "as sophisticated as this project's own
## existing hardest-to-reach structure."
func test_cottage_recipe_requires_the_same_carpentry_ceiling_as_sagewerk():
	assert_true(book.recipe_ids().has("cottage"))
	assert_eq(book.recipe_output("cottage")["item_id"], "cottage")
	var required_skill := book.recipe_required_skill("cottage")
	assert_eq(required_skill["stat_name"], "carpentry_level")
	assert_eq(required_skill["level"], book.recipe_required_skill("sagewerk")["level"])


## Pinned to agree with HouseBlueprint's own real "cottage_bright" piece
## list, the same discipline test_small_house_recipe_inputs_agree_with_the_
## hut_tiny_blueprints_real_cost already applies one tier down.
## cottage_bright has 3 real windows, but its total cost still does not
## depend on which seed places them: every wall/window/door/floor/roof
## piece of the same category costs the same regardless of which specific
## cell it lands on.
func test_cottage_recipe_inputs_agree_with_the_cottage_bright_blueprints_real_cost():
	const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
	const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
	var house_blueprint := HouseBlueprint.new()
	var total_wood := 0
	for pieces in [house_blueprint.build("cottage_bright", 0), house_blueprint.build_roofs("cottage_bright", 0)]:
		for cell in pieces:
			var cost: Dictionary = BuildingPiece.cost_of(pieces[cell])
			total_wood += int(cost.get("wood", 0))
	assert_gt(total_wood, 0, "precondition: cottage_bright really does cost real wood")
	assert_gt(
		total_wood, book.recipe_inputs("small_house")[0]["count"],
		"a cottage should cost more than the smaller hut_tiny house"
	)

	var inputs := book.recipe_inputs("cottage")
	assert_eq(inputs.size(), 1, "cottage_bright is an all-wood shape -- one input, no invented second material")
	assert_eq(inputs[0]["item_id"], "wood")
	assert_eq(inputs[0]["count"], total_wood)


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


## The Farm (docs/concept/npc_farm_production.md): a tilled, fenced plot --
## cheaper than Storage's own enclosed lumber shed since there is no roof or
## walls to raise, just wood for fence posts and plant fibre lashing them.
## No skill gate, matching Storage's own reachability.
func test_farm_recipe_uses_wood_and_plant_fibre():
	assert_true(book.recipe_ids().has("farm"), "farm must be craftable")
	assert_eq(book.recipe_output("farm")["item_id"], "farm")
	assert_false(book.can_craft("farm", {"wood": 6, "plant_fibre": 3}))
	assert_true(book.can_craft("farm", {"wood": 6, "plant_fibre": 4}))


## The wooden fence (docs/concept/npc_farm_production.md): cheap -- just
## fence rails and posts, wood only, no skill gate.
func test_wooden_fence_recipe_uses_wood_only():
	assert_true(book.recipe_ids().has("wooden_fence"), "wooden_fence must be craftable")
	assert_eq(book.recipe_output("wooden_fence")["item_id"], "wooden_fence")
	assert_false(book.can_craft("wooden_fence", {"wood": 2}))
	assert_true(book.can_craft("wooden_fence", {"wood": 3}))


## The City Hall (docs/concept/civic_construction.md's own "Meeting Hall"
## spec): a real civic commons, meaningfully bigger than Storage's own
## enclosed shed (12 wood + 4 plank) -- a stone footing for a building
## meant to stand as a settlement's permanent seat, plus substantial
## timber framing for a hall large enough to actually gather in. No skill
## gate, matching Storage/Farm's own reachability.
func test_city_hall_recipe_uses_wood_and_stone():
	assert_true(book.recipe_ids().has("city_hall"), "city_hall must be craftable")
	assert_eq(book.recipe_output("city_hall")["item_id"], "city_hall")
	assert_false(book.can_craft("city_hall", {"wood": 20, "stone": 9}))
	assert_true(book.can_craft("city_hall", {"wood": 20, "stone": 10}))


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


## Storm Lantern (docs/concept/lighting.md): built from a torch plus real
## iron working, not raw wood/hide again -- an upgrade path, not a second
## way to make the same base item.
func test_lantern_is_craftable_from_iron_ingots_and_a_torch():
	var ids := _input_item_ids("lantern")
	assert_true(ids.has("iron_ingot"), "lantern should require iron_ingot")
	assert_true(ids.has("torch"), "lantern should require a torch")
	assert_eq(book.recipe_output("lantern")["item_id"], "lantern")
	assert_true(book.can_craft("lantern", {"iron_ingot": 2, "torch": 1}))


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


# -- "any animal, the right tool" gear (see docs/concept/taming.md's ---------
# -- "Any animal, the right tool" section) -----------------------------------
#
## Four new capture tools -- one per capture class that had no tool of its
## own yet (Roped already had the lasso). Every input item id already
## exists in item_catalog.gd's _ITEMS -- no new raw material invented here.

func test_snare_recipe_uses_plant_fibre_and_a_stick():
	assert_true(book.recipe_ids().has("snare"), "the snare must be craftable")
	assert_eq(book.recipe_output("snare")["item_id"], "snare")
	assert_false(book.can_craft("snare", {"plant_fibre": 3, "stick": 1}))
	assert_true(book.can_craft("snare", {"plant_fibre": 4, "stick": 1}))
	var result: Dictionary = book.craft("snare", {"plant_fibre": 4, "stick": 1})
	assert_true(result["success"])
	assert_eq(result["remaining_counts"]["plant_fibre"], 0)
	assert_eq(result["remaining_counts"]["stick"], 0)


func test_butterfly_net_recipe_uses_a_stick_and_plant_fibre():
	assert_true(book.recipe_ids().has("butterfly_net"), "the butterfly net must be craftable")
	assert_eq(book.recipe_output("butterfly_net")["item_id"], "butterfly_net")
	assert_false(book.can_craft("butterfly_net", {"stick": 1, "plant_fibre": 2}))
	assert_true(book.can_craft("butterfly_net", {"stick": 1, "plant_fibre": 3}))


func test_trap_recipe_uses_sticks_and_rocks():
	assert_true(book.recipe_ids().has("trap"), "the trap must be craftable")
	assert_eq(book.recipe_output("trap")["item_id"], "trap")
	assert_false(book.can_craft("trap", {"stick": 2, "rock": 2}))
	assert_true(book.can_craft("trap", {"stick": 2, "rock": 3}))


## Reinforced rope is a real upgrade of the lasso, not a from-scratch build --
## it consumes a finished lasso plus real iron for the "magically reinforced
## steel ropes" the user named.
func test_reinforced_rope_recipe_upgrades_a_lasso_with_iron_ingots():
	assert_true(book.recipe_ids().has("reinforced_rope"), "reinforced rope must be craftable")
	assert_eq(book.recipe_output("reinforced_rope")["item_id"], "reinforced_rope")
	assert_false(book.can_craft("reinforced_rope", {"lasso": 1, "iron_ingot": 3}))
	assert_true(book.can_craft("reinforced_rope", {"lasso": 1, "iron_ingot": 4}))
	var result: Dictionary = book.craft("reinforced_rope", {"lasso": 1, "iron_ingot": 4})
	assert_true(result["success"])
	assert_eq(result["remaining_counts"]["lasso"], 0)
	assert_eq(result["remaining_counts"]["iron_ingot"], 0)


## Every input item id across all four new capture-gear recipes must already
## exist in item_catalog.gd -- no new raw material id invented for this pass
## (jarred_insect/caged_songbird are deliberately NOT craftable, so they are
## excluded here).
func test_capture_gear_recipes_use_only_existing_items():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	for recipe_id in ["snare", "butterfly_net", "trap", "reinforced_rope"]:
		for item_id in _input_item_ids(recipe_id):
			assert_true(catalog.has(item_id), "%s recipe uses unknown material %s" % [recipe_id, item_id])


# -- climbing rope (docs/concept/transportation.md's "Traversal tools" -----
# -- section: "a proper climbing rope needs high tensile strength", gated ---
# -- by material sourcing further out on the danger gradient rather than a --
# -- unique found-treasure item) ---------------------------------------------
#
## hide is the real MaterialProperties.MATERIALS material chosen (see
## test_material_properties.gd's test pinning it as a viable grapple_rope
## material by toughness) -- it is also already a real item_id in
## item_catalog.gd, sourced only by hunting+butchering an animal
## (butchering.gd), not gathered ambiently the way plant_fibre is. plant_fibre
## binds/braids the hide strips into an actual rope.

func test_climbing_rope_recipe_exists_and_is_craftable_from_hide_and_plant_fibre():
	assert_true(book.recipe_ids().has("climbing_rope"), "the climbing rope must be craftable")
	assert_eq(book.recipe_output("climbing_rope")["item_id"], "climbing_rope")
	assert_false(book.can_craft("climbing_rope", {"hide": 2, "plant_fibre": 3}))
	assert_true(book.can_craft("climbing_rope", {"hide": 3, "plant_fibre": 3}))
	var result: Dictionary = book.craft("climbing_rope", {"hide": 3, "plant_fibre": 3})
	assert_true(result["success"])
	assert_eq(result["output_item_id"], "climbing_rope")
	assert_eq(result["remaining_counts"]["hide"], 0)
	assert_eq(result["remaining_counts"]["plant_fibre"], 0)


## The chosen material must already be a real item the catalog knows about --
## no new raw material id invented for this recipe.
func test_climbing_rope_recipe_uses_only_existing_items():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	for item_id in _input_item_ids("climbing_rope"):
		assert_true(catalog.has(item_id), "climbing_rope recipe uses unknown material %s" % item_id)


# -- milling and baking (docs/concept/milling_and_baking.md) ------------------
#
## The bread chain as resolver data: three recipes that exist so NeedResolver
## can walk bread -> bakery -> flour -> mill -> wheat -> farm with zero
## chain-specific code (the SAME role log_to_balken/log_to_planke already
## play for the Sägewerk), each pinned to the real production constants so
## the two data sources can never drift.

func test_the_bread_chain_recipes_are_gated_on_their_real_structures():
	const MillProduction = preload("res://src/world/mill_production.gd")
	const BakeryProduction = preload("res://src/world/bakery_production.gd")

	assert_eq(book.recipe_output("grow_wheat")["item_id"], "wheat")
	assert_eq(book.recipe_requires_structure("grow_wheat"), "farm")
	assert_eq(book.recipe_inputs("grow_wheat"), [], "a plot needs time and water, no consumed input -- FarmPlot's own model")

	assert_eq(book.recipe_output("mill_flour")["item_id"], "flour")
	assert_eq(book.recipe_requires_structure("mill_flour"), "mill")
	var mill_inputs := book.recipe_inputs("mill_flour")
	assert_eq(mill_inputs.size(), 1)
	assert_eq(mill_inputs[0]["item_id"], "wheat")
	assert_eq(mill_inputs[0]["count"], int(MillProduction.WHEAT_PER_FLOUR))

	assert_eq(book.recipe_output("bake_bread")["item_id"], "bread")
	assert_eq(book.recipe_requires_structure("bake_bread"), "bakery")
	var bake_inputs := book.recipe_inputs("bake_bread")
	assert_eq(bake_inputs.size(), 1)
	assert_eq(bake_inputs[0]["item_id"], "flour")
	assert_eq(bake_inputs[0]["count"], int(BakeryProduction.FLOUR_PER_BREAD))

	assert_eq(book.recipe_for_output("bread"), "bake_bread")
	assert_eq(book.recipe_for_output("flour"), "mill_flour")
	assert_eq(book.recipe_for_output("wheat"), "grow_wheat")


## "automated": the one new general recipe field -- a recipe a structure's
## own production performs and a player can never craft by hand. grow_wheat
## has no input (FarmPlot consumes none), so without it anyone standing near
## a Farm could craft free wheat forever -- exactly the exploit
## npc_farm_production.md refused to paper over. mill_flour/bake_bread are
## NOT automated: a real input carried to a real building is a fair hand
## craft.
func test_grow_wheat_is_automated_and_the_rest_of_the_chain_is_not():
	assert_true(book.recipe_is_automated("grow_wheat"))
	assert_false(book.recipe_is_automated("mill_flour"))
	assert_false(book.recipe_is_automated("bake_bread"))


func test_recipe_is_automated_defaults_false_for_ordinary_and_unknown_recipes():
	assert_false(book.recipe_is_automated("iron_sword"))
	assert_false(book.recipe_is_automated("log_to_balken"))
	assert_false(book.recipe_is_automated("no_such_recipe"))


func test_an_automated_recipe_can_never_be_crafted_by_hand():
	assert_false(book.can_craft("grow_wheat", {}), "no input to lack, and still never hand-craftable")
	var result: Dictionary = book.craft("grow_wheat", {})
	assert_false(result["success"])


## The two buildings themselves: skill-UNGATED on purpose (the concept doc's
## "Why no skill gate, stated plainly" -- a settlement cannot autonomously
## raise anything skill-gated today), costed by what they are made of: a
## post mill is mostly timber on a stone base, a bakehouse is a masonry oven
## under a timber roof.
func test_mill_and_bakery_are_material_gated_placeables_costed_by_their_own_construction():
	assert_eq(book.recipe_output("mill")["item_id"], "mill")
	assert_eq(book.recipe_required_skill("mill"), {})
	assert_eq(book.recipe_requires_structure("mill"), "")
	var mill_cost := _cost_by_item(book.recipe_inputs("mill"))
	assert_gt(mill_cost.get("wood", 0), mill_cost.get("stone", 0), "a mill is mostly timber")
	assert_gt(mill_cost.get("stone", 0), 0, "...on a stone base carrying the millstones")

	assert_eq(book.recipe_output("bakery")["item_id"], "bakery")
	assert_eq(book.recipe_required_skill("bakery"), {})
	assert_eq(book.recipe_requires_structure("bakery"), "")
	var bakery_cost := _cost_by_item(book.recipe_inputs("bakery"))
	assert_gt(bakery_cost.get("stone", 0), bakery_cost.get("wood", 0), "a bakehouse is a masonry oven")
	assert_gt(bakery_cost.get("wood", 0), 0, "...under a timber roof")


func _cost_by_item(inputs: Array) -> Dictionary:
	var cost := {}
	for input in inputs:
		cost[input["item_id"]] = input["count"]
	return cost


## "Bench recipe" -- the ONE predicate deciding what a player may craft by
## hand from this book (docs/concept/production_chains.md "What the crafting
## menu lists"). The book is deliberately wider than the bench: it also
## carries the house-blueprint ledger recipes (output symbolic of a
## structure, never an ItemCatalog item) and "automated" resolver data.
## Both the crafting menu (CraftingWindow.bench_recipe_ids) and the dev
## console's /craft gate on THIS, so the two surfaces can never drift --
## before it, the console routed any id in recipe_ids() straight into
## Player.craft, which for a house recipe passed the skill gate, consumed
## the wood, and hand back nothing.
func test_is_bench_recipe_refuses_house_blueprints_whose_output_is_no_item():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	for recipe_id in ["small_house", "cottage", "manor", "grand_estate"]:
		assert_true(book.recipe_ids().has(recipe_id), "%s must still be a real recipe" % recipe_id)
		assert_false(catalog.has(recipe_id), "%s is a structure, never an item" % recipe_id)
		assert_false(book.is_bench_recipe(recipe_id, catalog), "%s must not count as a bench recipe" % recipe_id)


func test_is_bench_recipe_refuses_automated_recipes_and_unknown_ids():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	assert_true(catalog.has("wheat"), "precondition: grow_wheat's output IS an item, only the automated flag can refuse it")
	assert_false(book.is_bench_recipe("grow_wheat", catalog))
	assert_false(book.is_bench_recipe("no_such_recipe", catalog))


## Structures whose output IS a placeable item, and the structure-gated
## hand crafts of the bread chain, are real bench recipes -- the filter
## must exclude exactly the two ledger/resolver classes and nothing else.
func test_is_bench_recipe_accepts_hand_crafts_including_placeable_structures():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	for recipe_id in ["torch", "sagewerk", "mill", "campfire", "mill_flour", "bake_bread"]:
		assert_true(book.is_bench_recipe(recipe_id, catalog), "%s is a real bench craft" % recipe_id)


## bench_recipe_ids is recipe_ids filtered by the predicate -- derived here
## independently from the two tested facts it composes.
func test_bench_recipe_ids_is_recipe_ids_filtered_by_the_predicate():
	const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
	var catalog := ItemCatalog.new()
	var expected: Array = []
	for recipe_id in book.recipe_ids():
		if book.recipe_is_automated(recipe_id):
			continue
		if not catalog.has(book.recipe_output(recipe_id)["item_id"]):
			continue
		expected.append(recipe_id)
	var actual: Array = book.bench_recipe_ids(catalog)
	expected.sort()
	actual.sort()
	assert_gt(expected.size(), 0, "the bench set must not be empty or this proves nothing")
	assert_lt(expected.size(), book.recipe_ids().size(), "the book is wider than the bench on purpose")
	assert_eq(actual, expected)


## The catalog handed in is what decides whether an output is an item --
## the predicate reads it, rather than keeping its own list of house ids
## that would go stale the next time a ledger-only recipe is added.
class OnlyTorchCatalog:
	func has(item_id: String) -> bool:
		return item_id == "torch"


func test_the_catalog_decides_which_outputs_count_as_items():
	assert_eq(book.bench_recipe_ids(OnlyTorchCatalog.new()), ["torch"])
	assert_false(book.is_bench_recipe("sagewerk", OnlyTorchCatalog.new()))
