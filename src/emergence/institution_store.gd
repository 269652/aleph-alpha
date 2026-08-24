extends RefCounted

## Forms, finds, and dissolves institutions (see
## docs/emergence/01-society-and-institutions.md "Invariants": "Institutions
## can fail, merge, split, migrate, or disappear").
##
## Same shape as EventStore/.../MarketStore: a plain RefCounted collection,
## no engine dependency, own to_dicts/from_dicts for
## InstitutionStorePersistence to wrap. Deliberately does NOT depend on
## ContractStore/EventStore itself -- the caller (EarthChunkManager, the
## same coordinator every prior store already uses) decides WHEN a formation
## is warranted (see InstitutionFormation) and records the matching event;
## this store only manages institution state once that decision is made.

const Institution = preload("res://src/emergence/institution.gd")

var _institutions: Dictionary = {}   # id -> Institution
var _order: Array[String] = []       # insertion order
var _by_member: Dictionary = {}      # entity_id -> Array[String] (institution ids)
var _next_ordinal := 0


func form(type: String, members: Array, tick: float) -> Institution:
	var institution := Institution.new(type, members, tick)
	var id := "inst_%d_%s" % [_next_ordinal, type]
	_next_ordinal += 1
	institution.id = id
	_institutions[id] = institution
	_order.append(id)
	for member in institution.members:
		if not _by_member.has(member):
			_by_member[member] = []
		_by_member[member].append(id)
	return institution


func get_institution(institution_id: String) -> Institution:
	return _institutions.get(institution_id)


## Every institution this entity has ever belonged to, active or dissolved
## -- history is kept, the same "a fulfilled/breached contract stays
## queryable" shape ContractStore already uses. A caller that wants only
## live ones can filter on `.status == Institution.ACTIVE` itself.
func institutions_for(entity_id: String) -> Array[Institution]:
	var out: Array[Institution] = []
	for id in _by_member.get(entity_id, []):
		out.append(_institutions[id])
	return out


## An ACTIVE institution covering EXACTLY this member set (any order), or
## null -- the dedup guard formation needs so re-checking the same
## already-formed cluster does not silently duplicate it. A DISSOLVED
## institution does not count as "already exists" -- the same members could
## legitimately re-form after their institution failed.
func active_institution_for(members: Array) -> Institution:
	var key := _member_key(members)
	for id in _order:
		var institution: Institution = _institutions[id]
		if institution.status == Institution.ACTIVE and _member_key(institution.members) == key:
			return institution
	return null


static func _member_key(members: Array) -> String:
	var sorted: Array = members.duplicate()
	sorted.sort()
	return ",".join(sorted)


func dissolve(institution_id: String, _tick: float) -> bool:
	var institution: Institution = _institutions.get(institution_id)
	if institution == null or institution.status != Institution.ACTIVE:
		return false
	institution.status = Institution.DISSOLVED
	return true


## For InstitutionStorePersistence -- pure serialization, no FileAccess (same
## split EventStore/EventStorePersistence already use).
func to_dicts() -> Array:
	var out: Array = []
	for id in _order:
		var institution: Institution = _institutions[id]
		out.append({
			"id": institution.id,
			"type": institution.type,
			"members": institution.members,
			"leader": institution.leader,
			"goals": institution.goals,
			"status": institution.status,
			"created_at": institution.created_at,
		})
	return out


static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	var highest_ordinal := -1
	for d in dicts:
		var institution := Institution.new(
			d.get("type", ""), d.get("members", []), d.get("created_at", 0.0)
		)
		institution.id = d.get("id", "")
		institution.leader = d.get("leader", "")
		for goal in d.get("goals", []):
			institution.goals.append(str(goal))
		institution.status = d.get("status", Institution.ACTIVE)

		store._institutions[institution.id] = institution
		store._order.append(institution.id)
		for member in institution.members:
			if not store._by_member.has(member):
				store._by_member[member] = []
			store._by_member[member].append(institution.id)

		var ordinal := _ordinal_of(institution.id)
		if ordinal > highest_ordinal:
			highest_ordinal = ordinal
	store._next_ordinal = highest_ordinal + 1
	return store


## "inst_<ordinal>_<type>" -> ordinal, same convention EventStore/
## ContractStore's own _ordinal_of already established.
static func _ordinal_of(institution_id: String) -> int:
	var parts := institution_id.split("_", true, 2)
	if parts.size() < 2:
		return -1
	return int(parts[1])
