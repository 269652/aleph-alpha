extends GutTest

var MaterialProperties: GDScript = preload("res://src/gameplay/material_properties.gd")

var mp: RefCounted


func before_each() -> void:
	mp = MaterialProperties.new()


func test_wood_density_exact() -> void:
	assert_almost_eq(mp.property_value("wood", "density"), 0.6, 0.0001)


func test_wood_is_less_dense_than_water() -> void:
	assert_true(mp.property_value("wood", "density") < 1.0, "wood should float")


func test_stone_is_denser_than_water() -> void:
	assert_true(mp.property_value("stone", "density") > 1.0, "stone should sink")


func test_obsidian_toughness_exact() -> void:
	assert_almost_eq(mp.property_value("obsidian", "toughness"), 1.0, 0.0001)


func test_obsidian_sharpness_capacity_exact() -> void:
	assert_almost_eq(mp.property_value("obsidian", "sharpness_capacity"), 10.0, 0.0001)


func test_iron_hardness_exceeds_wood_hardness() -> void:
	assert_true(mp.property_value("iron", "hardness") > mp.property_value("wood", "hardness"))


func test_fiber_toughness_exact() -> void:
	assert_almost_eq(mp.property_value("fiber", "toughness"), 7.0, 0.0001)


func test_unknown_material_defaults_density_to_one() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "density"), 1.0, 0.0001)


func test_unknown_material_defaults_hardness_to_one() -> void:
	assert_almost_eq(mp.property_value("unobtainium", "hardness"), 1.0, 0.0001)


func test_unknown_property_on_known_material_defaults_to_one() -> void:
	assert_almost_eq(mp.property_value("wood", "made_up_property"), 1.0, 0.0001)


func test_wood_is_viable_raft_material() -> void:
	assert_true(mp.is_viable_for_tool("wood", "raft"))


func test_iron_is_not_viable_raft_material() -> void:
	assert_false(mp.is_viable_for_tool("iron", "raft"))


func test_stone_is_not_viable_raft_material() -> void:
	assert_false(mp.is_viable_for_tool("stone", "raft"))


func test_fiber_is_viable_grapple_rope_material() -> void:
	assert_true(mp.is_viable_for_tool("fiber", "grapple_rope"))


func test_obsidian_is_not_viable_grapple_rope_material() -> void:
	assert_false(mp.is_viable_for_tool("obsidian", "grapple_rope"))


func test_unknown_tool_type_is_never_viable() -> void:
	assert_false(mp.is_viable_for_tool("wood", "spaceship"))
