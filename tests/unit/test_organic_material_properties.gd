extends GutTest

## See docs/concept/material_dsl.md -- the organic material track
## materials.md always declared but never populated. Mirrors
## test_material_properties.gd's own conventions exactly.

var OrganicMaterialProperties: GDScript = preload("res://src/gameplay/organic_material_properties.gd")
var ImpactResolver: GDScript = preload("res://src/gameplay/impact_resolver.gd")

var op: RefCounted


func before_each() -> void:
	op = OrganicMaterialProperties.new()


func test_fruit_flesh_is_softer_than_muscle_tissue_or_at_least_as_soft() -> void:
	var MaterialProperties := preload("res://src/gameplay/material_properties.gd")
	var mp: RefCounted = MaterialProperties.new()
	assert_true(
		op.property_value("fruit_flesh", "hardness") <= mp.property_value("flesh", "hardness"),
		"fruit pulp has no more structure than muscle tissue"
	)


func test_fruit_flesh_is_not_brittle() -> void:
	assert_true(
		op.property_value("fruit_flesh", "toughness") >= ImpactResolver.T_BRITTLE_TOUGHNESS,
		"biting fruit should crush it, not shatter it"
	)


func test_unknown_organic_material_defaults_hardness_to_the_soft_floor() -> void:
	assert_almost_eq(op.property_value("nonexistent", "hardness"), 0.0, 0.0001)


func test_unknown_organic_material_property_falls_back_to_default() -> void:
	assert_almost_eq(op.property_value("fruit_flesh", "nonexistent_property"),
		op.property_value("nonexistent", "nonexistent_property"), 0.0001)
