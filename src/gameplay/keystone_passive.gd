extends RefCounted

## Powerful passives gated behind a minimum number of allocated skill_tree.gd
## nodes (Soft Cross-Archetype Pathing Gate) -- fixed table, no randomness.

## keystone_id -> {"stat_name": String, "bonus_amount": float, "required_node_count": int}
const _KEYSTONES := {
	"berserkers_fury": {"stat_name": "attack_damage", "bonus_amount": 15.0, "required_node_count": 5},
	"iron_skin": {"stat_name": "max_health", "bonus_amount": 60.0, "required_node_count": 3},
	"swift_current": {"stat_name": "stamina_regen", "bonus_amount": 9.0, "required_node_count": 4},
}

var _keystones: Dictionary = _KEYSTONES


func can_unlock(keystone_id: String, allocated_node_count: int) -> bool:
	if not _keystones.has(keystone_id):
		return false
	var required: int = _keystones[keystone_id]["required_node_count"]
	return allocated_node_count >= required


func keystone_ids() -> Array:
	return _keystones.keys()


## A keystone's full {stat_name, bonus_amount, required_node_count} for the UI.
## Empty Dictionary for an unknown keystone.
func keystone_info(keystone_id: String) -> Dictionary:
	if not _keystones.has(keystone_id):
		return {}
	return _keystones[keystone_id].duplicate()


func bonus_for(keystone_id: String) -> Dictionary:
	if not _keystones.has(keystone_id):
		return {"stat_name": "", "bonus_amount": 0.0}
	var keystone: Dictionary = _keystones[keystone_id]
	return {"stat_name": keystone["stat_name"], "bonus_amount": keystone["bonus_amount"]}
