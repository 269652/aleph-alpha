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


# -- timber (docs/concept/timber_construction.md): a real MATERIALS entry for
# -- BuildingPiece.MATERIAL_TIMBER, previously absent and silently falling
# -- back to DEFAULT_PROPERTIES' decay_rate=1.0 (stone-like) -- almost
# -- certainly wrong for a worked-but-still-organic material. See
# -- material_properties.gd's own "timber" entry doc comment for the full
# -- real-world grounding.

func test_timber_decay_rate_is_pinned() -> void:
	assert_almost_eq(mp.property_value("timber", "decay_rate"), 4.0, 0.0001)


func test_timber_decays_slower_than_raw_wood_but_faster_than_stone() -> void:
	var timber_rate: float = mp.property_value("timber", "decay_rate")
	assert_lt(
		timber_rate, mp.property_value("wood", "decay_rate"),
		"seasoned, squared timber should resist decay better than raw green wood"
	)
	assert_gt(
		timber_rate, mp.property_value("stone", "decay_rate"),
		"timber is still organic -- nowhere near stone's near-permanence"
	)


func test_timber_shares_every_other_property_with_wood() -> void:
	for property_name in [
		"density", "hardness", "toughness", "elasticity",
		"sharpness_capacity", "flammability", "conductivity",
	]:
		assert_almost_eq(
			mp.property_value("timber", property_name), mp.property_value("wood", property_name), 0.0001,
			"timber is the same wood, just worked/seasoned -- only decay_rate should differ"
		)


# -- plain-language descriptors (docs/concept/materials.md, "Learning an ------
# -- emergent system") ------------------------------------------------------
#
# That section specifies descriptors + discovery as the player-facing default,
# NOT a raw scalar spreadsheet, so the 8-scalar property vector reaches an item
# tooltip as words ("Iron - hard, keen") rather than numbers. Every threshold
# below is a named constant with its own calibration test, and the two lines
# the game has ALREADY calibrated elsewhere are reused rather than re-guessed.

func test_iron_and_stone_read_as_hard_but_wood_does_not() -> void:
	assert_true(mp.descriptors_for("iron").has("hard"), "iron (hardness 8) should read as hard")
	assert_true(mp.descriptors_for("stone").has("hard"), "stone (hardness 7) should read as hard")
	assert_false(mp.descriptors_for("wood").has("hard"), "wood (hardness 3) should not read as hard")


func test_obsidian_and_iron_read_as_keen_but_stone_does_not() -> void:
	assert_true(mp.descriptors_for("obsidian").has("keen"), "obsidian (sharpness 10) takes a keen edge")
	assert_true(mp.descriptors_for("iron").has("keen"), "iron (sharpness 8) takes a keen edge")
	assert_false(mp.descriptors_for("stone").has("keen"), "stone (sharpness 4) does not take a keen edge")


## The "brittle" word must mean exactly what the impact model already means by
## it -- one cutoff, not two that can silently drift apart.
func test_the_brittle_descriptor_uses_the_same_toughness_cutoff_the_impact_model_does() -> void:
	var ImpactResolver := preload("res://src/gameplay/impact_resolver.gd")
	assert_eq(MaterialProperties.BRITTLE_TOUGHNESS, ImpactResolver.T_BRITTLE_TOUGHNESS,
		"the brittle descriptor and the impact model must share one toughness cutoff")
	assert_true(mp.descriptors_for("obsidian").has("brittle"), "obsidian (toughness 1) is brittle")
	assert_false(mp.descriptors_for("iron").has("brittle"), "iron (toughness 7) is not brittle")


## "buoyant" is the raft-viability line the game already calibrated, reused --
## see is_viable_for_tool / WATER_DENSITY.
func test_wood_and_fiber_read_as_buoyant_at_the_water_density_line() -> void:
	assert_true(mp.descriptors_for("wood").has("buoyant"), "wood floats")
	assert_true(mp.descriptors_for("fiber").has("buoyant"), "fiber floats")
	assert_false(mp.descriptors_for("iron").has("buoyant"), "iron does not float")
	assert_eq(MaterialProperties.WATER_DENSITY, 1.0,
		"the buoyant descriptor rides on the existing water-density cutoff")


## A material with nothing notable says nothing -- an empty list, not a row of
## hedged words.
func test_flesh_has_no_notable_descriptors() -> void:
	assert_eq(mp.descriptors_for("flesh"), [] as Array[String])


func test_an_unknown_material_has_no_descriptors() -> void:
	assert_eq(mp.descriptors_for("not_a_material"), [] as Array[String])
