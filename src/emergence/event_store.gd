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
## type -> Array[String] (event ids, in order) -- same shape as _by_entity,
## same reason: events_of_type used to scan the WHOLE store (see that
## function's own doc comment), so it got slower with every event of every
## kind ever recorded, not just the type being asked for. A session that
## keeps running -- more trades, more crushes, more market ticks -- made
## every later settlement-step query pay for all of it.
var _by_type: Dictionary = {}
## "entity_id|type" -> Array[String] (event ids, in order) -- the
## INTERSECTION of the two indexes above, and the one round 14 stopped
## short of. `_by_type` fixed the callers that ask "everything of this
## kind"; the ones that ask "what did THIS entity do, of THIS kind" were
## still reading the whole of `_by_entity` and filtering by type in
## GDScript, which costs that entity's entire lifetime history however few
## events actually match (see events_for_entity_of_type).
var _by_entity_type: Dictionary = {}
var _next_ordinal := 0
## How many events every read has handed out since the last take -- see
## events_read(). Pure bookkeeping on a read path that was already
## allocating an Array per call; one integer add against an append is
## nothing next to what it makes visible.
var _events_read := 0


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
		_index_entity(entity_id, id, event.type)
	for entity_id in event.witnesses:
		_index_entity(entity_id, id, event.type)
	_index_type(event.type, id)
	return id


## An entity that is both ACTOR and WITNESS of the same event is indexed
## twice, in both indexes -- deliberately unchanged from what
## events_for_entity has always returned, so narrowing by type can never
## silently change a count a caller already depended on.
func _index_entity(entity_id: String, event_id: String, type: String) -> void:
	if not _by_entity.has(entity_id):
		_by_entity[entity_id] = []
	_by_entity[entity_id].append(event_id)
	var key := _entity_type_key(entity_id, type)
	if not _by_entity_type.has(key):
		_by_entity_type[key] = []
	_by_entity_type[key].append(event_id)


## Neither an EntityRef ("kind:value") nor an event type ever contains a
## pipe, so this can't collide -- the same one-string-key shape MemoryStore
## already uses for (holder, event_id).
static func _entity_type_key(entity_id: String, type: String) -> String:
	return "%s|%s" % [entity_id, type]


func _index_type(type: String, event_id: String) -> void:
	if not _by_type.has(type):
		_by_type[type] = []
	_by_type[type].append(event_id)


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


## How many events this store's reads have handed out since the last
## take_events_read() -- the store's own cost, in the store's own units.
##
## Why an odometer and not just a timer: "the performance gets worse the
## longer you play" has now cost this project fifteen FPS-regression rounds
## (docs/concept/soil_fauna.md), and every one of them turned out to be
## work proportional to everything that had ever happened. PerfReport could
## always show a SECTION climbing; it could never show WHY, because a
## growing history and a growing population look identical from a
## millisecond count. This distinguishes them outright: history walked per
## frame is flat in a healthy session and climbs in a sick one, whatever
## the frame rate is doing. Read as the s_/p_ fields' missing third axis
## (PerfReport's "ev_read").
func events_read() -> int:
	return _events_read


## The count since the last take, then resets -- the shape PerfReport's own
## take_sections/take_counts already use, so a report window reads as
## "history walked per frame" rather than as a number that only ever grows.
func take_events_read() -> int:
	var total := _events_read
	_events_read = 0
	return total


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
	_events_read += out.size()
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


## Every event this entity was an actor or witness in AND that is of this
## type, in the order they happened -- events_for_entity narrowed by type,
## reading the (entity, type) index instead of walking the entity index and
## filtering.
##
## Why this exists (reported live: "at a fresh start FPS is 60-100 but when
## running the game for a while it cripples to 5-10 fps"): a settlement is
## an actor or witness in essentially everything that happens to it, and its
## history only ever grows -- production successes are deliberately never
## collapsed (see EarthChunkManager._settlement_production_outcome), and
## contract outcomes are "the highest-volume real settlement activity in
## this file". `events_for_entity(settlement_id)` then materialises ALL of
## it, so the three callers that run every settlement step for every
## settlement -- _production_counts_for_settlement, _villagers_in_settlement
## and _households_in_settlement -- each paid the whole lifetime history to
## find a handful of matches. Per-step cost grew with how long the session
## had been running; cumulative cost grew quadratically. Exactly FPS
## regression round 14's shape, one index over.
func events_for_entity_of_type(entity_id: String, type: String) -> Array[Event]:
	var out: Array[Event] = []
	for event_id in _by_entity_type.get(_entity_type_key(entity_id, type), []):
		out.append(_events[event_id])
	_events_read += out.size()
	return out


## The same narrowing over SEVERAL types at once, merged back into the
## store's own insertion order rather than grouped by type -- what
## _households_in_settlement's SETTLING_EVENT_TYPES needs, since it dedupes
## by household as it walks and so depends on who really settled first.
##
## Sorted by ordinal rather than by tick: two events can share a tick (a
## whole settlement step runs at one world age), and insertion order is what
## events_for_entity itself returns. Cost is in the MATCHES (k log k), never
## in the entity's history.
func events_for_entity_of_types(entity_id: String, types: Array) -> Array[Event]:
	if types.size() == 1:
		return events_for_entity_of_type(entity_id, types[0])
	var ids: Array[String] = []
	for type in types:
		ids.append_array(_by_entity_type.get(_entity_type_key(entity_id, str(type)), []))
	ids.sort_custom(func(a: String, b: String) -> bool: return _ordinal_of(a) < _ordinal_of(b))
	var out: Array[Event] = []
	for event_id in ids:
		out.append(_events[event_id])
	_events_read += out.size()
	return out


## This entity's most recent event, or null if it has none -- what the
## record_path_worn_if_new / record_trail_formed_if_new family and their
## reclaim mirrors actually want, instead of building the entity's whole
## history to read `.back()` off it. The entity index is already in
## insertion order, so this is one lookup.
func latest_event_for_entity(entity_id: String):
	var ids: Array = _by_entity.get(entity_id, [])
	if ids.is_empty():
		return null
	_events_read += 1
	return _events[ids[ids.size() - 1]]


func events_of_type(type: String) -> Array[Event]:
	var out: Array[Event] = []
	for id in _by_type.get(type, []):
		out.append(_events[id])
	_events_read += out.size()
	return out


## Inclusive on both ends -- an event exactly at the boundary belongs to the
## window it borders, not the one after it.
func events_in_window(t0: float, t1: float) -> Array[Event]:
	var out: Array[Event] = []
	_events_read += _order.size()  # this one really does scan everything
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
			store._index_entity(entity_id, event.id, event.type)
		for entity_id in event.witnesses:
			store._index_entity(entity_id, event.id, event.type)
		store._index_type(event.type, event.id)
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
