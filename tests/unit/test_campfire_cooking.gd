extends GutTest

const CampfireCooking = preload("res://src/gameplay/campfire_cooking.gd")

var cooking: CampfireCooking


func before_each():
	cooking = CampfireCooking.new()


func test_meat_cooks_to_cooked_meat():
	assert_eq(cooking.cooked_output("meat"), "cooked_meat")


func test_fish_cooks_to_cooked_fish():
	assert_eq(cooking.cooked_output("fish"), "cooked_fish")


func test_fruit_stays_raw_returns_empty():
	assert_eq(cooking.cooked_output("fruit"), "")


func test_unknown_item_returns_empty():
	assert_eq(cooking.cooked_output("rock"), "")


func test_can_cook_true_near_fire_for_cookable():
	assert_true(cooking.can_cook("meat", true))


func test_cannot_cook_when_not_near_fire():
	assert_false(cooking.can_cook("meat", false))


func test_cannot_cook_uncookable_even_near_fire():
	assert_false(cooking.can_cook("fruit", true))


func test_cannot_cook_unknown_even_near_fire():
	assert_false(cooking.can_cook("rock", true))


func test_fish_can_cook_near_fire():
	assert_true(cooking.can_cook("fish", true))
