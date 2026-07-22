extends RefCounted

## Small stat nodes players spend points on. Fixed table, no randomness --
## allocation is a deliberate player choice, not a roll.

## node_id -> {"stat_name": String, "bonus_amount": float, "point_cost": int}
const _NODES := {
	"vitality_1": {"stat_name": "max_health", "bonus_amount": 10.0, "point_cost": 1},
	"vitality_2": {"stat_name": "max_health", "bonus_amount": 20.0, "point_cost": 2},
	"endurance_1": {"stat_name": "stamina_regen", "bonus_amount": 1.5, "point_cost": 1},
	"endurance_2": {"stat_name": "stamina_regen", "bonus_amount": 3.0, "point_cost": 2},
	"strength_1": {"stat_name": "attack_damage", "bonus_amount": 2.0, "point_cost": 1},
	"strength_2": {"stat_name": "attack_damage", "bonus_amount": 4.0, "point_cost": 2},
}

var _nodes: Dictionary = _NODES


func can_allocate(node_id: String, allocated: Dictionary, available_points: int) -> bool:
	if not _nodes.has(node_id):
		return false
	if allocated.get(node_id, false):
		return false
	var point_cost: int = _nodes[node_id]["point_cost"]
	return point_cost <= available_points


func allocate(node_id: String, allocated: Dictionary) -> Dictionary:
	var result: Dictionary = allocated.duplicate()
	if not _nodes.has(node_id):
		return result
	if result.get(node_id, false):
		return result
	result[node_id] = true
	return result


func total_bonus(stat_name: String, allocated: Dictionary) -> float:
	var total: float = 0.0
	for node_id in allocated:
		if not allocated[node_id]:
			continue
		if not _nodes.has(node_id):
			continue
		var node: Dictionary = _nodes[node_id]
		if node["stat_name"] == stat_name:
			total += node["bonus_amount"]
	return total


func node_ids() -> Array:
	return _nodes.keys()


## A node's {stat_name, bonus_amount, point_cost} for the skill-tree UI to
## render. Empty Dictionary for an unknown node.
func node_info(node_id: String) -> Dictionary:
	if not _nodes.has(node_id):
		return {}
	return _nodes[node_id].duplicate()
