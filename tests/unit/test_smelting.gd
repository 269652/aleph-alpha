extends GutTest

const Smelting = preload("res://src/gameplay/smelting.gd")

var smelting: Smelting


func before_each():
	smelting = Smelting.new()


func test_ore_smelts_to_its_ingot():
	assert_eq(smelting.smelted_output("iron_ore"), "iron_ingot")
	assert_eq(smelting.smelted_output("copper_ore"), "copper_ingot")


func test_a_non_ore_has_no_ingot():
	assert_eq(smelting.smelted_output("wood"), "")
	assert_eq(smelting.smelted_output("coal"), "", "coal is the fuel, not smeltable")


func test_smelting_recipes_are_recognised():
	assert_true(smelting.is_smelting_recipe("iron_ingot"))
	assert_true(smelting.is_smelting_recipe("copper_ingot"))
	assert_false(smelting.is_smelting_recipe("iron_helm"), "forging gear isn't a smelt")
	assert_false(smelting.is_smelting_recipe("torch"))


func test_the_fuel_is_coal():
	assert_eq(Smelting.FUEL_ITEM, "coal")


func test_can_smelt_requires_a_heat_source():
	assert_false(smelting.can_smelt("iron_ingot", false))
	assert_true(smelting.can_smelt("iron_ingot", true))


func test_can_smelt_only_for_actual_smelting_recipes():
	assert_false(smelting.can_smelt("torch", true), "non-smelting recipes aren't gated here")
