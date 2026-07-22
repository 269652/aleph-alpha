extends RefCounted

const EquipmentMaterial = preload("res://src/gameplay/equipment_material.gd")


## Returns the new wetness fraction [0.0, 1.0] for an item after delta_seconds:
## rising toward 1.0 (at material.absorption_rate) while submerged, falling
## toward 0.0 (at material.dry_rate) while not.
func update(
	current_wetness: float, material: EquipmentMaterial, submerged: bool, delta_seconds: float
) -> float:
	var rate := material.absorption_rate if submerged else -material.dry_rate
	return clampf(current_wetness + rate * delta_seconds, 0.0, 1.0)
