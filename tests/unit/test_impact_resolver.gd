extends GutTest

var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")

var resolver: RefCounted


func before_each() -> void:
	resolver = ImpactResolver.new()


func test_low_momentum_always_bounces() -> void:
	assert_eq(resolver.resolve_impact(0.5, "edge", "iron"), "bounce")


func test_edge_below_cut_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(2.0, "edge", "wood"), "dent")


func test_edge_at_cut_threshold_cuts_tough_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "edge", "wood"), "cut")


func test_edge_on_brittle_material_shatters_instead_of_cutting() -> void:
	assert_eq(resolver.resolve_impact(3.0, "edge", "obsidian"), "shatter")


func test_blunt_below_crush_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(3.5, "blunt", "wood"), "dent")


func test_blunt_at_crush_threshold_crushes_tough_material() -> void:
	assert_eq(resolver.resolve_impact(4.0, "blunt", "wood"), "crush")


func test_blunt_on_brittle_material_shatters_instead_of_crushing() -> void:
	assert_eq(resolver.resolve_impact(4.0, "blunt", "obsidian"), "shatter")


func test_point_at_pierce_threshold_pierces_soft_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "point", "flesh"), "pierce")


func test_point_cannot_pierce_hard_material() -> void:
	assert_eq(resolver.resolve_impact(3.0, "point", "iron"), "dent")


## The pierce cap is no longer an eyeballed 6.0 on a legibility scale: it is
## MaterialProperties.HARD_HARDNESS, the same number a tooltip uses to decide
## whether to print the word "hard". One line, not two that can drift -- the
## arrangement T_BRITTLE_TOUGHNESS and BRITTLE_TOUGHNESS already have.
##
## The second half is the evidence that this is genuinely the same line the old
## constant drew rather than a convenient replacement: every material in the
## shipped table keeps the verdict it had before the hardness column was
## rescaled to real Vickers.
func test_a_point_cannot_pierce_anything_the_tooltip_calls_hard() -> void:
	var MaterialProperties := preload("res://src/gameplay/material_properties.gd")
	assert_almost_eq(ImpactResolver.PIERCE_HARDNESS_CAP,
		MaterialProperties.HARD_HARDNESS, 0.000001,
		"the word the player reads and the behaviour must be one number")
	var mp: RefCounted = MaterialProperties.new()
	# The verdicts the pre-rescale table produced against the old eyeballed 6.0.
	var expected := {
		"wood": "pierce", "timber": "pierce", "flesh": "pierce", "fiber": "pierce",
		"hide": "pierce", "leather": "pierce", "sinew": "pierce", "bone": "pierce",
		"carbon": "pierce", "tin": "pierce", "copper": "pierce", "zinc": "pierce",
		"silver": "pierce", "gold": "pierce",
		"iron": "dent", "stone": "dent", "obsidian": "dent", "glass": "dent",
	}
	for material in MaterialProperties.MATERIALS:
		assert_true(expected.has(material),
			"%s is a new row and needs its pierce verdict recorded here" % material)
		assert_eq(resolver.resolve_impact(3.0, "point", material), expected[material],
			"%s changed pierce verdict under the hardness rescale" % material)
		assert_eq(mp.descriptors_for(material).has("hard"), expected[material] == "dent",
			"%s: 'hard' in words and 'unpierceable' in behaviour must agree" % material)


func test_point_below_pierce_threshold_dents() -> void:
	assert_eq(resolver.resolve_impact(2.0, "point", "flesh"), "dent")


func test_unknown_geometry_dents() -> void:
	assert_eq(resolver.resolve_impact(5.0, "sideways", "wood"), "dent")


## See docs/concept/material_dsl.md: an injected materials source lets the
## organic track (OrganicMaterialProperties) resolve through the exact same
## outcome table, without a parallel resolver. Every OTHER test in this file
## constructs ImpactResolver.new() with no argument and must keep reading
## against the default mineral table -- this is additive, not a signature
## change for existing callers.
class FakeMaterials:
	extends RefCounted
	func property_value(_material: String, property_name: String) -> float:
		if property_name == "toughness":
			return 100.0  # never brittle
		return 0.0  # e.g. hardness -- always soft


func test_an_injected_materials_source_is_used_instead_of_the_default() -> void:
	var fake_resolver: RefCounted = ImpactResolver.new(FakeMaterials.new())
	# The default table's "obsidian" is brittle (shatters); the fake table
	# says every material has toughness 100 (never brittle) -- if the
	# injected source were ignored, this would still shatter.
	assert_eq(fake_resolver.resolve_impact(4.0, "blunt", "obsidian"), "crush")


func test_omitting_the_materials_source_still_uses_the_real_mineral_table() -> void:
	var default_resolver: RefCounted = ImpactResolver.new()
	assert_eq(default_resolver.resolve_impact(4.0, "blunt", "obsidian"), "shatter")
