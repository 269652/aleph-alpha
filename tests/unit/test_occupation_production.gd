extends GutTest

## OccupationProduction: which CraftingRecipeBook recipe a settlement
## attempts on behalf of a household whose founder holds a given occupation
## (see src/emergence/occupation_production.gd's own doc comment for what
## grounds each individual pairing).
##
## Two halves: one pin per pairing above, and the STRUCTURAL tests below,
## which read the REAL NpcIdentity.OCCUPATIONS list and a REAL
## CraftingRecipeBook rather than a copy of either. Adding an occupation,
## renaming a recipe, or putting a skill/structure gate on one of these
## recipes therefore fails here, instead of silently handing some villagers
## back a production shortfall they can never have -- and so, downstream
## (Quest.production_shortfall_quests_for), nothing to ever ask a player for.

const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")

var recipe_book: CraftingRecipeBook


func before_each():
	recipe_book = CraftingRecipeBook.new()


# -- one pin per grounded pairing ------------------------------------------

func test_farmer_maps_to_lasso():
	assert_eq(OccupationProduction.recipe_for("farmer"), "lasso")


func test_blacksmith_maps_to_stone_pickaxe():
	assert_eq(OccupationProduction.recipe_for("blacksmith"), "stone_pickaxe")


func test_merchant_maps_to_map():
	assert_eq(OccupationProduction.recipe_for("merchant"), "map")


func test_guard_maps_to_wooden_club():
	assert_eq(OccupationProduction.recipe_for("guard"), "wooden_club")


func test_fisher_maps_to_fishing_rod():
	assert_eq(OccupationProduction.recipe_for("fisher"), "fishing_rod")


func test_herbalist_maps_to_butterfly_net():
	assert_eq(OccupationProduction.recipe_for("herbalist"), "butterfly_net")


func test_hunter_maps_to_cooked_meat():
	assert_eq(OccupationProduction.recipe_for("hunter"), "cooked_meat")


func test_nurse_maps_to_campfire():
	assert_eq(OccupationProduction.recipe_for("nurse"), "campfire")


func test_unknown_occupation_returns_empty_string():
	assert_eq(OccupationProduction.recipe_for("not_a_real_occupation"), "")


# -- structural: read the real occupation list and the real recipe book ----

## EVERY real villager produces something. Read straight from NpcIdentity's
## own list, so a ninth occupation added there fails here until it is given
## a grounded recipe of its own, rather than shipping a whole class of
## villagers who can never fall short of anything.
func test_every_real_occupation_has_a_recipe():
	for occupation: String in NpcIdentity.OCCUPATIONS:
		assert_ne(OccupationProduction.recipe_for(occupation), "", occupation)


## ...and every id in the map is a recipe the real book actually has, so a
## renamed recipe can never leave an occupation pointing at nothing (which
## CraftingRecipeBook.craft answers with a silent "success": false, not an
## error anyone would notice).
func test_every_mapped_recipe_exists_in_the_real_recipe_book():
	for occupation: String in NpcIdentity.OCCUPATIONS:
		var recipe_id := OccupationProduction.recipe_for(occupation)
		assert_true(recipe_book.recipe_ids().has(recipe_id), "%s -> %s" % [occupation, recipe_id])
		assert_false(recipe_book.recipe_output(recipe_id).is_empty(), recipe_id)


## Nothing here may point at a skill- or structure-gated recipe. Market.
## produce -- Phase 5's own production path, and the only one this map is
## ever read through -- calls CraftingRecipeBook.craft directly, which
## checks INPUTS only: unlike Player.craft it never reads
## recipe_required_skill/recipe_requires_structure, so a gated recipe here
## would be a settlement silently walking through a gate a player has to
## earn.
func test_no_mapped_recipe_bypasses_a_skill_or_structure_gate():
	for occupation: String in NpcIdentity.OCCUPATIONS:
		var recipe_id := OccupationProduction.recipe_for(occupation)
		assert_eq(recipe_book.recipe_required_skill(recipe_id), {}, occupation)
		assert_eq(recipe_book.recipe_requires_structure(recipe_id), "", occupation)


## Every input a mapped recipe can fall short OF must itself be reachable
## without clearing a gate: either raw (nothing in the book produces it, so
## it is gathered from the world) or made by an ungated recipe. The whole
## player-facing point of this map is the shortfall it produces
## (Quest.production_shortfall_quests_for names the missing item), and
## "bring me a plank" is only actionable if a plank is not itself behind a
## Sagewerk the settlement's own market can never build.
func test_every_mapped_recipe_input_is_fetchable_without_clearing_a_gate():
	for occupation: String in NpcIdentity.OCCUPATIONS:
		var recipe_id := OccupationProduction.recipe_for(occupation)
		for input in recipe_book.recipe_inputs(recipe_id):
			var item_id: String = input["item_id"]
			var source := recipe_book.recipe_for_output(item_id)
			if source == "":
				continue  # raw: gathered from the world, no gate to clear
			assert_eq(recipe_book.recipe_required_skill(source), {}, "%s <- %s" % [item_id, source])
			assert_eq(recipe_book.recipe_requires_structure(source), "", "%s <- %s" % [item_id, source])


## Eight occupations, eight DIFFERENT recipes. Production diversity is a
## real settlement number -- EarthChunkManager feeds
## production_counts.size() into SettlementTier.tier_for, whose
## CITY_PRODUCTION_DIVERSITY is 2 -- so two occupations sharing one recipe
## would quietly cost a settlement a tier its villagers had genuinely
## worked for.
func test_each_occupation_maps_to_a_distinct_recipe():
	var seen: Array[String] = []
	for occupation: String in NpcIdentity.OCCUPATIONS:
		var recipe_id := OccupationProduction.recipe_for(occupation)
		assert_false(seen.has(recipe_id), "%s reuses %s" % [occupation, recipe_id])
		seen.append(recipe_id)


## ...and no entry names an occupation NpcIdentity no longer has: renaming
## one there must fail loudly here rather than leave a dead entry beside a
## live occupation that now produces nothing.
func test_the_map_has_no_entry_for_an_occupation_that_does_not_exist():
	for occupation in OccupationProduction._RECIPE_BY_OCCUPATION:
		assert_true(NpcIdentity.OCCUPATIONS.has(occupation), occupation)
