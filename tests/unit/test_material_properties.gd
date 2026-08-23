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


# -- real mass, for the shared momentum model (docs/concept/materials.md's --
# -- momentum = mass * velocity, see impact_resolver.gd/throwable.gd) -------
#
# mass_kg_for(material, volume_cm3) = density (already real g/cm^3, since
# it's expressed relative to water == 1.0 g/cm^3) x volume, generalizing
# StoneSize.mass_kg_for's "density x volume" shape to an arbitrary item
# rather than a sphere specifically -- so a sword/axe/club can get a real
## mass from the SAME shared density table stone already uses.

func test_mass_kg_for_matches_density_times_volume() -> void:
	# iron's density (7.8) x a 100cm^3 volume = 780g = 0.78kg.
	assert_almost_eq(mp.mass_kg_for("iron", 100.0), 0.78, 0.0001)


func test_mass_kg_for_scales_with_volume() -> void:
	assert_almost_eq(mp.mass_kg_for("iron", 200.0), mp.mass_kg_for("iron", 100.0) * 2.0, 0.0001)


func test_mass_kg_for_a_denser_material_masses_more_at_the_same_volume() -> void:
	assert_gt(mp.mass_kg_for("iron", 100.0), mp.mass_kg_for("wood", 100.0))


func test_mass_kg_for_zero_volume_is_zero_mass() -> void:
	assert_almost_eq(mp.mass_kg_for("iron", 0.0), 0.0, 0.0001)
