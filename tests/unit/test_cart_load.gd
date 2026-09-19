extends GutTest

## The Bollerwagen's own load (docs/concept/village_warehouse.md,
## Mechanism 5). Asked directly: "it should be so that the ressources are
## actually loaded inside the wagon which has an inventory; so if the worker
## leaves it somewhere it's actually full of ressources".
##
## Pure: the load is a plain item_id -> count Dictionary passed in and a new
## one handed back, so nothing here needs a cart node, a porter or a world.

const CartLoad = preload("res://src/gameplay/cart_load.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const CraftingRecipeBook = preload("res://src/gameplay/crafting_recipe_book.gd")


func test_an_empty_cart_carries_nothing():
	assert_eq(CartLoad.total({}), 0)
	assert_eq(CartLoad.room_left({}), CartLoad.CAPACITY)


func test_loading_puts_the_goods_in_the_cart():
	var result: Dictionary = CartLoad.load_into({}, "beam", 4)
	assert_eq(int(result["loaded"]), 4)
	assert_eq(int(result["stock"]["beam"]), 4)


func test_a_cart_holds_several_kinds_at_once():
	var stock: Dictionary = CartLoad.load_into({}, "beam", 4)["stock"]
	stock = CartLoad.load_into(stock, "plank", 3)["stock"]
	assert_eq(CartLoad.total(stock), 7)
	assert_eq(int(stock["plank"]), 3)


## What will not fit is LEFT, not destroyed: the caller puts back exactly
## what the cart refused.
func test_what_will_not_fit_is_left_behind():
	var result: Dictionary = CartLoad.load_into({}, "wood", CartLoad.CAPACITY + 10)
	assert_eq(int(result["loaded"]), CartLoad.CAPACITY, "a full cart is a full cart")
	assert_eq(CartLoad.total(result["stock"]), CartLoad.CAPACITY)


func test_a_full_cart_takes_nothing_more():
	var stock: Dictionary = CartLoad.load_into({}, "wood", CartLoad.CAPACITY)["stock"]
	var result: Dictionary = CartLoad.load_into(stock, "stone", 5)
	assert_eq(int(result["loaded"]), 0)
	assert_eq(CartLoad.total(result["stock"]), CartLoad.CAPACITY)


func test_loading_never_mutates_the_load_it_was_shown():
	var stock := {"beam": 2}
	CartLoad.load_into(stock, "beam", 4)
	assert_eq(int(stock["beam"]), 2, "the caller moves the goods, not this")


func test_a_cart_cannot_be_loaded_with_nothing():
	assert_eq(int(CartLoad.load_into({}, "beam", 0)["loaded"]), 0)
	assert_eq(int(CartLoad.load_into({}, "", 4)["loaded"]), 0)


# -- how big a cart is -------------------------------------------------------
# Pinned as RELATIONSHIPS rather than as a number: there is no real
# cartwright's measure to derive one from, and both of these are real
# quantities this game already holds.

## The point of a cart is that the round trip is worth making, so it carries
## strictly more than the porter's own arms do.
func test_a_cart_carries_more_than_a_porter_can():
	assert_gt(CartLoad.CAPACITY, LogisticsMarker.CARRY_CAPACITY)


## And enough to bring home a whole small house's timber in one trip -- a
## cart that could not do that would not be worth pulling.
func test_a_cart_brings_home_a_whole_houses_timber_in_one_trip():
	var wood := 0
	for input in CraftingRecipeBook.new().recipe_inputs("house_small"):
		if String(input["item_id"]) == "wood":
			wood = int(input["count"])
	assert_gt(wood, 0, "precondition: the ladder's cheapest rung really costs wood")
	assert_gte(CartLoad.CAPACITY, wood)
