extends RefCounted

## The per-entity store of MemoryRecords (see
## docs/emergence/02-history-memory-rumors.md "Memory").
##
## Layered on top of EventStore rather than folded into it (see
## docs/emergence/00's authoritative loop: "emit events -> update
## memories/beliefs" is a distinct step from emitting) -- so EventStore stays
## usable for entities that do not have memories at all, and this stays
## usable without needing to know anything about how events got recorded.

const Event = preload("res://src/emergence/event.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const Rumor = preload("res://src/emergence/rumor.gd")

## (holder, event_id) -> MemoryRecord. One memory per holder per event -- a
## later witnessing or retelling of the same event REPLACES the holder's
## existing memory of it (the most recent telling wins) rather than piling
## up duplicates.
var _memories: Dictionary = {}
## holder -> Array[String] of "holder|event_id" keys, in the order first
## formed -- so memories_for reads in a stable, deterministic order.
var _by_holder: Dictionary = {}


static func _key(holder: String, event_id: String) -> String:
	return "%s|%s" % [holder, event_id]


func _store(memory: MemoryRecord) -> void:
	var key := _key(memory.holder, memory.event_id)
	if not _memories.has(key):
		if not _by_holder.has(memory.holder):
			_by_holder[memory.holder] = []
		_by_holder[memory.holder].append(key)
	_memories[key] = memory


## Forms a fresh, firsthand/witnessed memory of `event` for every one of its
## actors AND witnesses, in one call -- a settlement founding is remembered
## by the settlement and by every villager present, not just whoever the
## caller happened to name. Returns whatever was actually formed (skipping
## an entity that already remembers this exact event, so re-witnessing the
## same event is a safe no-op rather than a duplicate).
func witness_event(event: Event, tick: float) -> Array[MemoryRecord]:
	var formed: Array[MemoryRecord] = []
	var entities: Array[String] = []
	for entity_id in event.actors:
		entities.append(entity_id)
	for entity_id in event.witnesses:
		entities.append(entity_id)

	for entity_id in entities:
		if _memories.has(_key(entity_id, event.id)):
			continue
		var memory = MemoryRecord.from_event(event, entity_id, tick)
		if memory == null:
			continue
		_store(memory)
		formed.append(memory)
	return formed


## Every memory this entity holds, in the order first formed.
func memories_for(entity_id: String) -> Array[MemoryRecord]:
	var out: Array[MemoryRecord] = []
	for key in _by_holder.get(entity_id, []):
		out.append(_memories[key])
	return out


## `from_holder` tells `to_holder` about `event_id`, heard at `tick`. Returns
## the memory `to_holder` now holds, or null if `from_holder` had no such
## memory to tell -- nothing to transmit if the teller never actually knew.
func transmit(from_holder: String, to_holder: String, event_id: String, tick: float) -> MemoryRecord:
	var source_key := _key(from_holder, event_id)
	if not _memories.has(source_key):
		return null
	var source_memory: MemoryRecord = _memories[source_key]
	var told := Rumor.transmit(source_memory, to_holder, tick)
	_store(told)
	return told


## For MemoryStorePersistence -- pure serialization, no FileAccess (see that
## module for the actual I/O; same split EventStore/EventStorePersistence
## already use).
func to_dicts() -> Array:
	var out: Array = []
	for holder in _by_holder:
		for key in _by_holder[holder]:
			out.append(_memories[key].to_dict())
	return out


## Rebuilds a bank from to_dicts()' output, going through _store so the
## dedupe index is correctly re-derived rather than persisted separately (one
## source of truth, same reasoning as EventStore.from_dicts).
static func from_dicts(dicts: Array) -> RefCounted:
	var bank = new()
	for d in dicts:
		bank._store(MemoryRecord.from_dict(d))
	return bank
