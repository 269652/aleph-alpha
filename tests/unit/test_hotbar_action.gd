extends GutTest

const HotbarAction = preload("res://src/gameplay/hotbar_action.gd")

var action := HotbarAction.new()


func test_weapons_and_tools_are_equipped():
	assert_eq(action.action_for("weapon"), HotbarAction.EQUIP)
	assert_eq(action.action_for("tool"), HotbarAction.EQUIP)


func test_food_and_potions_are_used():
	assert_eq(action.action_for("food"), HotbarAction.USE)
	assert_eq(action.action_for("potion"), HotbarAction.USE)


func test_materials_do_nothing():
	assert_eq(action.action_for("material"), HotbarAction.NONE)


func test_unknown_kinds_do_nothing():
	assert_eq(action.action_for("not_a_real_kind"), HotbarAction.NONE)
	assert_eq(action.action_for(""), HotbarAction.NONE)


func test_armor_is_equipped():
	assert_eq(action.action_for("armor"), HotbarAction.EQUIP)
