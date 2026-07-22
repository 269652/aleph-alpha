extends GutTest

const CookingRecipeBook = preload("res://src/gameplay/cooking_recipe_book.gd")

var book: CookingRecipeBook


func before_each():
	book = CookingRecipeBook.new()


func test_known_combo_returns_matching_dish():
	var dish := book.cook(["fruit", "meat"])
	assert_eq(dish.dish_id, "hearty_stew")


func test_known_combo_in_different_order_returns_same_dish():
	var a := book.cook(["fruit", "meat"])
	var b := book.cook(["meat", "fruit"])
	assert_eq(a.dish_id, b.dish_id)


func test_second_known_combo_returns_matching_dish():
	var dish := book.cook(["nut", "meat"])
	assert_eq(dish.dish_id, "roasted_nut_meat")


func test_unknown_combo_returns_empty_sentinel():
	var dish := book.cook(["boot", "rock"])
	assert_eq(dish.dish_id, "")
	assert_eq(dish.display_name, "")
	assert_eq(dish.buff, "")
	assert_eq(dish.buff_duration, 0.0)


func test_unknown_combo_returns_a_valid_dictionary_not_null():
	var dish := book.cook(["boot", "rock"])
	assert_eq(typeof(dish), TYPE_DICTIONARY)
	assert_true(dish.has("dish_id"))
	assert_true(dish.has("display_name"))
	assert_true(dish.has("buff"))
	assert_true(dish.has("buff_duration"))
	assert_true(dish.has("category"))


func test_cook_does_not_mutate_input_array():
	var original := ["meat", "fruit"]
	book.cook(original)
	assert_eq(original, ["meat", "fruit"])


func test_known_dish_ids_returns_all_defined_dishes():
	var ids := book.known_dish_ids()
	assert_true(ids.has("hearty_stew"))
	assert_true(ids.has("roasted_nut_meat"))
	assert_gte(ids.size(), 3)


func test_every_recipe_has_a_positive_buff_duration():
	var combos := [["fruit", "meat"], ["nut", "meat"], ["fish", "herb"], ["berry", "water"]]
	for combo in combos:
		var dish := book.cook(combo)
		assert_gt(dish.buff_duration, 0.0)


func test_known_combo_has_non_empty_display_name_and_buff():
	var dish := book.cook(["fish", "herb"])
	assert_ne(dish.display_name, "")
	assert_ne(dish.buff, "")


func test_unknown_combo_sentinel_has_empty_category():
	var dish := book.cook(["boot", "rock"])
	assert_true(dish.has("category"))
	assert_eq(dish.category, "")


func test_sustenance_category_dishes():
	assert_eq(book.cook(["fruit", "meat"]).category, "sustenance")
	assert_eq(book.cook(["fish", "herb"]).category, "sustenance")


func test_combat_category_dish():
	assert_eq(book.cook(["nut", "meat"]).category, "combat")


func test_resistance_category_dish():
	assert_eq(book.cook(["berry", "water"]).category, "resistance")
