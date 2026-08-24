extends RefCounted

## The authoritative append-only log of the world's causal event graph (see
## docs/emergence/00-emergence-architecture.md "Simulation authority" and
## docs/emergence/07-implementation-roadmap.md Phase 1).
##
## Pure and engine-free -- FileAccess lives in EventStorePersistence, not
## here, matching this project's pure-module/engine-glue split
## (ChunkSerializer/EarthChunkManager, PlayerSave/World).

const Event = preload("res://src/emergence/event.gd")

var _events: Dictionary = {}          # id -> Event
var _order: Array[String] = []        # insertion order -- the deterministic read order
var _by_entity: Dictionary = {}       # entity_id -> Array[String] (event ids, in order)
var _next_ordinal := 0


## Assigns a deterministic, sortable id ("evt_<ordinal>_<type>") and indexes
## the event by every actor and witness it names, then returns the id.
##
## Does NOT link causes -- that is link_cause's job (called separately, or by
## a caller that already knows an event's causes at construction time; see
## link_cause for why the reverse edge belongs there and not here).
func append(event: Event) -> String:
	var id := "evt_%d_%s" % [_next_ordinal, event.type]
	_next_ordinal += 1
	event.id = id
	_events[id] = event
	_order.append(id)
	for entity_id in event.actors:
		_index_entity(entity_id, id)
	for entity_id in event.witnesses:
		_index_entity(entity_id, id)
	return id


func _index_entity(entity_id: String, event_id: String) -> void:
	if not _by_entity.has(entity_id):
		_by_entity[entity_id] = []
	_by_entity[entity_id].append(event_id)


## Records that `effect_id` was caused by `cause_id`: adds the cause to the
## effect's own `causes` (if not already present) and links the reverse
## `consequences` edge on the cause -- both directions, from one call. This is
## the whole reason EventStore owns this rather than leaving it to the caller:
## a caller can forget to wire the reverse edge, the store cannot, because it
## is the only thing that ever writes `consequences`.
func link_cause(effect_id: String, cause_id: String) -> void:
	_link(cause_id, effect_id)


func _link(cause_id: String, effect_id: String) -> void:
	var cause: Event = _events.get(cause_id)
	var effect: Event = _events.get(effect_id)
	if cause == null or effect == null:
		return
	if not effect.causes.has(cause_id):
		effect.causes.append(cause_id)
	if not cause.consequences.has(effect_id):
		cause.consequences.append(effect_id)


func get_event(event_id: String) -> Event:
	return _events.get(event_id)


func size() -> int:
	return _order.size()


func all_ids() -> Array[String]:
	return _order.duplicate()


## Every distinct entity id that has appeared as an actor or witness, in
## first-seen order. For SimulationMetrics' entity count -- the entity index
## already exists as `_by_entity`'s keys, this just exposes it in a stable
## order rather than a caller relying on Dictionary key order directly.
func all_entity_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _by_entity.keys():
		out.append(id)
	return out


## Every event this entity was an ACTOR or WITNESS in, in the order they
## happened -- what /history <entity_id> answers.
func events_for_entity(entity_id: String) -> Array[Event]:
	var out: Array[Event] = []
	for event_id in _by_entity.get(entity_id, []):
		out.append(_events[event_id])
	return out


func causes_of(event_id: String) -> Array[Event]:
	var event: Event = get_event(event_id)
	if event == null:
		return []
	var out: Array[Event] = []
	for cause_id in event.causes:
		if _events.has(cause_id):
			out.append(_events[cause_id])
	return out


func consequences_of(event_id: String) -> Array[Event]:
	var event: Event = get_event(event_id)
	if event == null:
		return []
	var out: Array[Event] = []
	for consequence_id in event.consequences:
		if _events.has(consequence_id):
			out.append(_events[consequence_id])
	return out


## The full ancestor trace: this event's causes, their causes, and so on --
## the module's own worked example (Drought -> Crop failure -> Food shortage)
## walked BACKWARD from Food shortage. Nearest cause first.
##
## Bounded by both a depth cap and a visited set, so a malformed graph (a
## cycle) cannot hang a debug command -- `/why` has to stay safe to run
## against whatever the simulation actually produced, not just a well-formed
## graph.
func cause_chain(event_id: String, max_depth: int = 16) -> Array[Event]:
	var out: Array[Event] = []
	var visited := {event_id: true}
	var frontier := [event_id]
	var depth := 0
	while depth < max_depth and not frontier.is_empty():
		var next_frontier: Array = []
		for id in frontier:
			var event: Event = get_event(id)
			if event == null:
				continue
			for cause_id in event.causes:
				if visited.has(cause_id):
					continue
				visited[cause_id] = true
				var cause: Event = get_event(cause_id)
				if cause != null:
					out.append(cause)
					next_frontier.append(cause_id)
		frontier = next_frontier
		depth += 1
	return out


func events_of_type(type: String) -> Array[Event]:
	var out: Array[Event] = []
	for id in _order:
		if _events[id].type == type:
			out.append(_events[id])
	return out


## Inclusive on both ends -- an event exactly at the boundary belongs to the
## window it borders, not the one after it.
func events_in_window(t0: float, t1: float) -> Array[Event]:
	var out: Array[Event] = []
	for id in _order:
		var event: Event = _events[id]
		if event.tick >= t0 and event.tick <= t1:
			out.append(event)
	return out


## For EventStorePersistence -- pure serialization, no FileAccess (see that
## module for the actual I/O).
func to_dicts() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_events[id].to_dict())
	return out


## Rebuilds a store from to_dicts()' output. Re-derives ordinal, entity index
## and consequence links from the events themselves rather than persisting
## them separately -- one source of truth, so a hand-edited or corrupted
## save can't leave the derived index disagreeing with the events it was
## derived from.
static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	var highest_ordinal := -1
	for d in dicts:
		var event = Event.from_dict(d)
		store._events[event.id] = event
		store._order.append(event.id)
		for entity_id in event.actors:
			store._index_entity(entity_id, event.id)
		for entity_id in event.witnesses:
			store._index_entity(entity_id, event.id)
		var ordinal := _ordinal_of(event.id)
		if ordinal > highest_ordinal:
			highest_ordinal = ordinal
	# consequences are already stored on each event's own dict (to_dict
	# serializes them directly), so re-linking would double them up -- only
	# the ordinal counter needs re-deriving here.
	store._next_ordinal = highest_ordinal + 1
	return store


## "evt_<ordinal>_<type>" -> ordinal, so a restored store can resume the id
## sequence without colliding with events that already exist.
static func _ordinal_of(event_id: String) -> int:
	var parts := event_id.split("_", true, 2)
	if parts.size() < 2:
		return -1
	return int(parts[1])
