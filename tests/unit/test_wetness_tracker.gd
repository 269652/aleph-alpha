extends GutTest

const WetnessTracker = preload("res://src/gameplay/wetness_tracker.gd")
const EquipmentMaterial = preload("res://src/gameplay/equipment_material.gd")

var tracker: WetnessTracker
var material: EquipmentMaterial


func before_each():
	tracker = WetnessTracker.new()
	material = EquipmentMaterial.new()
	material.absorption_rate = 0.1
	material.dry_rate = 0.05


func test_submerged_increases_wetness_over_time():
	var wetness := tracker.update(0.0, material, true, 2.0)
	assert_almost_eq(wetness, 0.2, 0.001)


func test_submerged_wetness_clamps_at_one():
	material.absorption_rate = 0.5
	var wetness := tracker.update(0.95, material, true, 1.0)
	assert_almost_eq(wetness, 1.0, 0.001)


func test_not_submerged_decreases_wetness_over_time():
	var wetness := tracker.update(0.5, material, false, 2.0)
	assert_almost_eq(wetness, 0.4, 0.001)


func test_not_submerged_wetness_clamps_at_zero():
	material.dry_rate = 0.5
	var wetness := tracker.update(0.05, material, false, 1.0)
	assert_almost_eq(wetness, 0.0, 0.001)
