extends RefCounted

## One immutable node in the world's causal event graph (see
## docs/emergence/00-emergence-architecture.md "Event sourcing" and
## docs/emergence/02-history-memory-rumors.md's Event schema).
##
## Do not event-source every low-level movement -- event-source meaningful
## changes only (00's own instruction). Pure data: EventStore owns assigning
## `id` and maintaining the reverse `consequences` link, since both of those
## are about how an event relates to OTHER events in the store, not about the
## event itself.

## Assigned by EventStore.append; empty until then.
var id := ""

var type: String
var tick: float
## World pixel position, or Vector2.ZERO for a non-spatial event.
var location: Vector2

## Entity references (see EntityRef) -- who did this, who it happened to.
var actors: Array[String] = []
## Event ids this event was caused BY.
var causes: Array[String] = []
## Event ids this event caused -- maintained by EventStore, not the caller
## (see EventStore.append): a caller can name causes, but consequences are
## always the reverse edge of some other event's causes, discovered from the
## graph rather than declared.
var consequences: Array[String] = []
## Entity references present for this event without being its actor.
var witnesses: Array[String] = []
## Free-form provenance references (a ruin, a record, a physical trace).
var evidence: Array[String] = []

## How much this event matters (see docs/emergence/02's importance factors).
## 0.0 by default: an event is unimportant until something says otherwise.
var importance := 0.0
## local / regional / notable / major.
var visibility := "local"
var tags: Array[String] = []


func _init(a_type: String, a_tick: float = 0.0, a_location: Vector2 = Vector2.ZERO) -> void:
	type = a_type
	tick = a_tick
	location = a_location


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"tick": tick,
		"location": location,
		"actors": actors,
		"causes": causes,
		"consequences": consequences,
		"witnesses": witnesses,
		"evidence": evidence,
		"importance": importance,
		"visibility": visibility,
		"tags": tags,
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var event = new(d.get("type", ""), d.get("tick", 0.0), d.get("location", Vector2.ZERO))
	event.id = d.get("id", "")
	event.actors = _typed_strings(d.get("actors", []))
	event.causes = _typed_strings(d.get("causes", []))
	event.consequences = _typed_strings(d.get("consequences", []))
	event.witnesses = _typed_strings(d.get("witnesses", []))
	event.evidence = _typed_strings(d.get("evidence", []))
	event.importance = d.get("importance", 0.0)
	event.visibility = d.get("visibility", "local")
	event.tags = _typed_strings(d.get("tags", []))
	return event


## Array[String] round-trips through FileAccess.store_var as a plain untyped
## Array -- this rebuilds the typed array from_dict needs.
static func _typed_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out
