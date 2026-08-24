extends GutTest

## Market (see docs/emergence/03-contracts-property-economy.md "Markets":
## "local buyer/seller matching systems. Prices respond to supply, demand,
## stockpiles... Do not use one global price").
##
## Production itself is NOT reinvented here -- CraftingRecipeBook already
## has real, tested recipes (`recipe_inputs`/`can_craft`/`craft`) grounded in
## this project's real item ids (wood, rock, stick, ...). A market is what
## was actually missing: a place those recipes draw from and sell into,
## whose STOCK derives a real price rather than one flat constant.

const Market = preload("res://src/emergence/market.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")

var market: Market
var recipes: CraftingRecipeBook


func before_each():
	market = Market.new()
	recipes = CraftingRecipeBook.new()


# -- stock --------------------------------------------------------------------

func test_a_fresh_market_has_no_stock():
	assert_eq(market.stock_of("wood"), 0)


func test_add_stock_increases_what_is_on_hand():
	market.add_stock("wood", 5)
	assert_eq(market.stock_of("wood"), 5)
	market.add_stock("wood", 3)
	assert_eq(market.stock_of("wood"), 8)


# -- price derives from stock, not a flat constant ----------------------------

## At the reference stock level, price is the neutral 1.0 -- neither scarce
## nor oversupplied.
func test_price_at_the_reference_stock_level_is_neutral():
	market.add_stock("wood", Market.REFERENCE_STOCK)
	assert_almost_eq(market.price_for("wood"), 1.0, 0.001)


## Below reference, scarcer means pricier -- monotonically, not just "some
## number that happens to be different."
func test_price_rises_as_stock_falls_below_reference():
	market.add_stock("wood", Market.REFERENCE_STOCK)
	var full_price := market.price_for("wood")
	market.stock["wood"] = Market.REFERENCE_STOCK / 4
	var scarce_price := market.price_for("wood")
	assert_gt(scarce_price, full_price)


func test_price_falls_as_stock_rises_above_reference():
	market.add_stock("wood", Market.REFERENCE_STOCK)
	var normal_price := market.price_for("wood")
	market.add_stock("wood", Market.REFERENCE_STOCK * 4)
	var glutted_price := market.price_for("wood")
	assert_lt(glutted_price, normal_price)


## Zero stock does not divide by zero -- it is the MOST expensive/scarce
## state, not an error.
func test_zero_stock_gives_a_finite_high_price_not_a_crash():
	var price := market.price_for("wood")
	assert_true(is_finite(price))
	assert_gt(price, 1.0)


# -- production draws from stock, and can fail on a real shortage ------------

## The whole exit criterion: a resource shortage can cause downstream
## production failure. stone_pickaxe needs 3 rock; with none in stock,
## production genuinely fails -- not a scripted event, the same can_craft
## check the player's own crafting already uses, just checked against
## market stock instead of a player's inventory.
func test_production_fails_when_an_input_is_out_of_stock():
	var result := market.produce(recipes, "stone_pickaxe")
	assert_false(result.success)
	assert_eq(market.stock_of("stone_pickaxe"), 0)


func test_production_succeeds_and_consumes_inputs_when_stock_allows_it():
	market.add_stock("stick", 2)
	market.add_stock("rock", 3)
	var result := market.produce(recipes, "stone_pickaxe")
	assert_true(result.success)
	assert_eq(market.stock_of("stick"), 0)
	assert_eq(market.stock_of("rock"), 0)


func test_production_adds_the_output_to_stock():
	market.add_stock("stick", 2)
	market.add_stock("rock", 3)
	market.produce(recipes, "stone_pickaxe")
	assert_eq(market.stock_of("stone_pickaxe"), 1)


## A shortage causes BOTH symptoms from the SAME real number -- price and
## produceability are two views of one stock, not independently modelled
## (no separate currency/budget system needed to connect them).
func test_a_shortage_raises_price_and_blocks_production_together():
	market.add_stock("rock", 1)  # short of the 3 stone_pickaxe needs
	var price_while_short := market.price_for("rock")
	var result := market.produce(recipes, "stone_pickaxe")

	assert_false(result.success, "production should fail while rock is short")
	market.add_stock("rock", Market.REFERENCE_STOCK - 1)  # restock to reference
	assert_lt(market.price_for("rock"), price_while_short, "restocking should lower the price")


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dict_and_from_dict_round_trip_a_whole_market():
	market.add_stock("wood", 5)
	market.add_stock("rock", 2)

	var restored := Market.from_dict(market.to_dict())

	assert_eq(restored.stock_of("wood"), 5)
	assert_eq(restored.stock_of("rock"), 2)
