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
const NpcIdentity = preload("res://src/world/npc_identity.gd")

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


## An occupation OccupationProduction has no recipe for has nothing to be
## short of -- skipped, not forced into a quest that doesn't exist.
##
## No REAL occupation can reach that branch any more, which is why this is
## pinned with a string NpcIdentity does not have. It used to be pinned
## with "merchant", back when only hunter and blacksmith were mapped; all
## eight of NpcIdentity.OCCUPATIONS are mapped now, and that is deliberate
## (see occupation_production.gd: an occupation with no recipe can never
## fall short of an input, so its households can never ask a player for
## anything). The guard itself still has to hold, because
## production_shortfall_quests_for takes occupations as plain strings from
## its caller: a renamed or malformed one must drop out quietly rather than
## crash or invent a recipe. The assert_false keeps the premise honest --
## if this name ever becomes a real occupation, this fails here instead of
## quietly testing nothing.
func test_an_occupation_that_does_not_exist_produces_no_quest():
	assert_false(NpcIdentity.OCCUPATIONS.has("not_a_real_occupation"))
	var market := Market.new()
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "not_a_real_occupation"}, market, recipe_book
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


# -- deeper_need_for (docs/concept/production_chains.md): a purely -----------
# -- additive capability -- does NOT change production_shortfall_quests_ ----
# -- for's own signature, behavior, or its one real call site --------------
# -- (EarthChunkManager.production_shortfall_quests_for_settlement). A -----
# -- caller with one specific missing item from an existing shortfall ------
# -- quest's own "missing" list can ask here for the deeper resolution: ----
# -- what does actually producing more of it need (a missing structure, ----
# -- a missing skill, or deeper missing sub-materials) -- via -------------
# -- NeedResolver's real recursive walk, not a second one-off resolver. ----

## A shortfall quest names "rock" as missing for stone_pickaxe -- rock has
## no recipe (it's mined), so the deeper resolution is exactly the same
## raw-material need, nothing more.
func test_deeper_need_for_a_raw_item_matches_the_shortfall_itself():
	var deeper: Array = Quest.deeper_need_for("rock", {}, {}, {}, recipe_book)
	assert_eq(deeper, [{"kind": "material", "item_id": "rock", "need": 1}])


## A missing item that itself needs a structure resolves to that real
## structure need, not just "still missing."
func test_deeper_need_for_an_item_needing_a_structure():
	var stock := {"iron_ore": 1, "coal": 1}
	var deeper: Array = Quest.deeper_need_for("iron_ingot", stock, {}, {}, recipe_book)
	assert_eq(deeper, [{"kind": "structure", "item_id": "iron_ingot", "structure_id": "heat_source"}])


## Does not mutate or otherwise affect production_shortfall_quests_for's
## own existing behavior -- both can be called against the same recipe_book
## in the same test with no interference.
func test_deeper_need_for_does_not_disturb_production_shortfall_quests_for():
	var market := Market.new()
	var quests := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	assert_eq(quests.size(), 1)
	var deeper: Array = Quest.deeper_need_for("hide", {}, {}, {}, recipe_book)
	assert_eq(deeper, [{"kind": "material", "item_id": "hide", "need": 1}])
	# Re-run the original call again -- still the same real result.
	var quests_again := Quest.production_shortfall_quests_for(
		"settlement:0_0", {"household:1": "blacksmith"}, market, recipe_book
	)
	assert_eq(quests_again, quests)


func test_no_households_produces_no_quests():
	var market := Market.new()
	assert_eq(Quest.production_shortfall_quests_for("settlement:0_0", {}, market, recipe_book), [])
