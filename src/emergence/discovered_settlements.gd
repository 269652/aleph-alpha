extends RefCounted

## Which settlements the player has actually discovered (see
## docs/concept/player_trade.md's "Settlement discovery" -- design
## pillar 1: a settlement is a real trading partner the moment it's
## discovered, not before, and stays one permanently once it is). Pure
## data only -- deciding WHEN a settlement counts as discovered (real
## proximity to its landmark, or ExploredTiles coverage once that's wired
## to player movement) is a thin glue call site's job, not this store's;
## same "pure store, glue decides WHEN" split ContractStore/HouseholdStore
## already use for their own real-world trigger points.

var _discovered: Dictionary = {}   # settlement_id -> world_age_discovered (float)


## Idempotent: a settlement's discovery moment is real history, so a
## later call with the same id does NOT overwrite the original world age
## -- "once explored, always explored", the same persistence model
## ExploredTiles already uses for the map.
func mark_discovered(settlement_id: String, world_age: float) -> void:
	if not _discovered.has(settlement_id):
		_discovered[settlement_id] = world_age


func is_discovered(settlement_id: String) -> bool:
	return _discovered.has(settlement_id)


## -1.0 for a settlement never discovered -- never a real world age, so a
## caller can't mistake "not discovered" for "discovered at age 0".
func discovered_at(settlement_id: String) -> float:
	return _discovered.get(settlement_id, -1.0)


func discovered_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _discovered:
		ids.append(id)
	return ids


func to_dict() -> Dictionary:
	return {"discovered": _discovered}


static func from_dict(d: Dictionary) -> RefCounted:
	var store = new()
	var restored: Dictionary = d.get("discovered", {})
	for settlement_id in restored:
		store._discovered[str(settlement_id)] = float(restored[settlement_id])
	return store
