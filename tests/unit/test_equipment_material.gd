extends GutTest

# Named EquipmentMaterial, not Material: Godot already has a native Material
# class (shader/surface materials), and reusing that name causes the same
# kind of collision we hit earlier with GUT's "Logger" class.
const EquipmentMaterial = preload("res://src/gameplay/equipment_material.gd")

var material: EquipmentMaterial


func before_each():
	material = EquipmentMaterial.new()
	material.weight = 2.0
	material.water_weight = 3.0


func test_effective_weight_at_zero_wetness_is_just_the_dry_weight():
	assert_almost_eq(material.effective_weight(0.0), 2.0, 0.001)


func test_effective_weight_at_full_wetness_includes_all_water_weight():
	assert_almost_eq(material.effective_weight(1.0), 5.0, 0.001)


func test_effective_weight_scales_linearly_with_wetness():
	assert_almost_eq(material.effective_weight(0.5), 3.5, 0.001)
