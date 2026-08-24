extends GutTest

## Quest: quests as PROJECTIONS of real simulation state, never new
## authoritative content (docs/emergence/07-implementation-roadmap.md
## Phase 12: "Refactor quests into projections of household, institution,
## settlement, ecology, infrastructure, history, and economy problems.
## Disabling quests must not remove the underlying problem.") -- pure,
## stateless queries over real Market/CraftingRecipeBook state, no Store,
## no persistence.

const Quest = preload("res://src/emergence/quest.gd")
const Market = preload("res://src/emergence/market.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var recipe_book: CraftingRecipeBook


func before_each():
	recipe_book = CraftingRecipeBook.new()


## A household whose occupation-grounded recipe is fully blocked produces
## a real quest naming the specific missing input(s) -- not just "blocked."
func test_a_household_missing_a_recipe_input_produces_a_quest():
	var market := Market.new()  # empty -- stone_pickaxe needs stick + rock
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	assert_eq(quests.size(), 1)
	assert_eq(quests[0]["settlement_id"], "settlement:0_0")
	assert_eq(quests[0]["household_id"], "household:1")
	assert_eq(quests[0]["recipe_id"], "stone_pickaxe")


func test_the_quest_names_the_specific_missing_items_and_amounts():
	var market := Market.new()
	market.add_stock("stick", 2)  # has sticks, still missing rock
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	assert_eq(quests[0]["missing"], [{"item_id": "rock", "need": 3}])


## A household with everything it needs has no shortfall -- no quest.
func test_a_household_with_full_stock_produces_no_quest():
	var market := Market.new()
	market.add_stock("stick", 2)
	market.add_stock("rock", 3)
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	assert_eq(quests, [])


## An occupation with no grounded recipe (see OccupationProduction) has
## nothing to be short of -- not forced into a quest that doesn't exist.
func test_an_occupation_with_no_grounded_recipe_produces_no_quest():
	var market := Market.new()
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "merchant"}, market, recipe_book
	)
	assert_eq(quests, [])


func test_partial_stock_still_reports_only_the_remaining_shortfall():
	var market := Market.new()
	market.add_stock("rock", 1)  # has 1 of 3 needed rock, still 0 sticks
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	var missing: Array = quests[0]["missing"]
	assert_eq(missing.size(), 2)
	assert_has(missing, {"item_id": "stick", "need": 2})
	assert_has(missing, {"item_id": "rock", "need": 2})


func test_each_household_produces_its_own_independent_quest():
	var market := Market.new()
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith", "household:2": "hunter"}, market, recipe_book
	)
	assert_eq(quests.size(), 2)


func test_no_households_produces_no_quests():
	var market := Market.new()
	assert_eq(Quest.production_shortfall_quests_for("settlement:0_0", {}, market, recipe_book), [])
