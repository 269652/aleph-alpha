extends GutTest

## The brewery's own product. docs/concept/village_growth.md carried this
## as a named gap -- "the ladder's rungs are buildings, not yet
## production": a village raised the dearest rung on its ladder and got a
## building that made nothing. docs/concept/village_estates.md's burgher
## basket is what finally needs it, so the brewery brews.
##
## Deliberately the SAME shape the mill and bakery already have
## (grow_wheat -> mill_flour -> bake_bread): a real structure-gated recipe
## turning a real grain into a real good, not a new production system.

const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

const BEER_ITEM_ID := "beer"
const BREW_RECIPE_ID := "brew_beer"


func test_beer_is_a_real_item_the_catalog_knows():
	assert_true(ItemCatalog.new().has(BEER_ITEM_ID))


## A drink is drunk. Its kind is what VillageMarket's own food filter reads,
## and beer genuinely WAS a staple calorie source in this period -- small
## beer was safer than the well.
func test_beer_is_food():
	assert_eq(ItemCatalog.new().kind_of(BEER_ITEM_ID), "food")


func test_the_brewery_has_a_recipe_that_actually_makes_beer():
	var book := CraftingRecipeBook.new()
	assert_true(book.recipe_ids().has(BREW_RECIPE_ID))
	assert_eq(book.recipe_output(BREW_RECIPE_ID)["item_id"], BEER_ITEM_ID)


## The gate is the building the growth ladder already raises, so the
## dearest rung on that ladder is finally the thing that unlocks the
## burgher's basket rather than an ornament.
func test_brewing_requires_the_brewery_the_ladder_already_builds():
	assert_eq(CraftingRecipeBook.new().recipe_requires_structure(BREW_RECIPE_ID), "brewery")


## Grain in, beer out -- the same wheat the real farm chain already grows
## (grow_wheat), so brewing is the third consumer of one existing crop
## rather than a new resource nobody produces.
func test_beer_is_brewed_from_the_wheat_the_farm_chain_already_grows():
	var book := CraftingRecipeBook.new()
	var input_ids: Array = []
	for input in book.recipe_inputs(BREW_RECIPE_ID):
		input_ids.append(input["item_id"])
	assert_eq(input_ids, ["wheat"])


## A brew takes more grain than a loaf takes flour: beer is the luxury at
## the top of the estate ladder and has to cost like one. Pinned as the
## relation against the bread chain, not as either number.
func test_a_brew_costs_more_grain_than_a_loaf_costs_flour():
	var book := CraftingRecipeBook.new()
	var brew_grain: int = book.recipe_inputs(BREW_RECIPE_ID)[0]["count"]
	var loaf_flour: int = book.recipe_inputs("bake_bread")[0]["count"]
	assert_true(brew_grain > loaf_flour, "a brew is no dearer than a loaf")


## It really crafts: a bench holding the grain and standing in a brewery
## gets beer out, which is the whole point of the recipe existing.
func test_a_brewery_holding_grain_really_produces_beer():
	var book := CraftingRecipeBook.new()
	var grain: int = book.recipe_inputs(BREW_RECIPE_ID)[0]["count"]
	var stock := {"wheat": grain}
	var result: Dictionary = book.craft(BREW_RECIPE_ID, stock)
	assert_true(result.get("success", false), "the brewery refused grain it had")
	assert_eq(int(result["remaining_counts"].get("wheat", 0)), 0, "the grain was not actually consumed")
	assert_eq(result.get("output_item_id", ""), BEER_ITEM_ID)
	assert_eq(int(result.get("output_count", 0)), 1)
