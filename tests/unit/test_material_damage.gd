extends GutTest

var MaterialDamage: GDScript = preload("res://src/gameplay/material_damage.gd")

var md: RefCounted


func before_each() -> void:
	md = MaterialDamage.new()


func test_axe_vs_wood_is_far_more_efficient_than_sword_vs_wood() -> void:
	var axe_wood: float = md.damage_multiplier("axe", "wood")
	var sword_wood: float = md.damage_multiplier("sword", "wood")
	assert_gt(axe_wood, sword_wood * 2.0, "axe should be far better than sword against wood")


func test_axe_vs_wood_exact_multiplier() -> void:
	assert_almost_eq(md.damage_multiplier("axe", "wood"), 3.0, 0.0001)


func test_sword_vs_wood_exact_multiplier() -> void:
	assert_almost_eq(md.damage_multiplier("sword", "wood"), 0.5, 0.0001)


func test_sword_vs_flesh_at_least_as_good_as_axe_vs_flesh() -> void:
	assert_true(
		md.damage_multiplier("sword", "flesh") >= md.damage_multiplier("axe", "flesh"),
		"sword must be at least as good as axe against flesh"
	)


func test_sword_vs_flesh_exact_multiplier() -> void:
	assert_almost_eq(md.damage_multiplier("sword", "flesh"), 1.0, 0.0001)


func test_axe_vs_flesh_exact_multiplier() -> void:
	assert_almost_eq(md.damage_multiplier("axe", "flesh"), 0.8, 0.0001)


func test_unarmed_vs_wood_is_weak() -> void:
	assert_almost_eq(md.damage_multiplier("unarmed", "wood"), 0.25, 0.0001)


func test_unknown_pair_defaults_to_one() -> void:
	assert_almost_eq(md.damage_multiplier("wand", "obsidian"), 1.0, 0.0001)


func test_unknown_material_for_known_weapon_defaults_to_one() -> void:
	assert_almost_eq(md.damage_multiplier("axe", "crystal"), 1.0, 0.0001)


func test_effective_damage_applies_multiplier() -> void:
	assert_almost_eq(md.effective_damage(10.0, "axe", "wood"), 30.0, 0.0001)


func test_effective_damage_default_pair() -> void:
	assert_almost_eq(md.effective_damage(7.0, "sword", "unknown"), 7.0, 0.0001)


func test_effective_damage_never_negative() -> void:
	assert_almost_eq(md.effective_damage(-5.0, "axe", "wood"), 0.0, 0.0001)
