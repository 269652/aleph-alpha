extends RefCounted

## An NPC's memory of an event -- a LOSSY PROJECTION of authoritative history
## (see docs/emergence/02-history-memory-rumors.md "Memory" and "Fact versus
## belief").
##
## References the real event by id, so it can always be checked against
## ground truth, but carries its OWN remembered fields, confidence and
## source. The authoritative Event this points at never changes; a
## MemoryRecord is a separate thing that can simply be wrong -- which is the
## whole reason the two are different types rather than one shared struct.

const Event = preload("res://src/emergence/event.gd")

## The module's own enumerated source types (docs/emergence/02): how directly
## this holder came to know about the event.
const FIRSTHAND := "firsthand"
const WITNESSED := "witnessed"
const TRUSTED_TESTIMONY := "trusted_testimony"
const STRANGER_TESTIMONY := "stranger_testimony"
const INFERENCE := "inference"
const WRITTEN_RECORD := "written_record"
const RUMOR := "rumor"
const SOURCE_TYPES := [
	FIRSTHAND, WITNESSED, TRUSTED_TESTIMONY, STRANGER_TESTIMONY,
	INFERENCE, WRITTEN_RECORD, RUMOR,
]

## The authoritative event this memory is ABOUT -- never mutated to match a
## drifted memory; check against EventStore.get_event(event_id) for ground
## truth.
var event_id: String

## Who holds this memory (an EntityRef).
var holder: String

## This holder's OWN recollection -- starts as an exact copy of the real
## event's fields and can drift under transmission (see Rumor.transmit).
var remembered_type: String
var remembered_location: Vector2
var remembered_actors: Array[String] = []
var remembered_outcome: String = ""

## How sure the holder is [0,1].
var confidence := 1.0
## How much this holder cares [0,1]. Defaults to 0 -- most events are not
## emotionally significant to most witnesses.
var emotional_salience := 0.0
## How directly this holder came to know it (see SOURCE_TYPES above).
var source_type: String
## How far this holder's remembered fields have actually drifted from the
## real event [0,1] -- distinct from confidence, which is how sure the
## holder FEELS, not how right they actually are (see docs/emergence/02:
## a rumor can be told with total confidence and still be wrong).
var distortion := 0.0
## When this holder came to hold this memory -- not the event's own tick
## (see Rumor.transmit, where the two diverge: the event happened once, but
## each retelling is heard at a different, later tick).
var recorded_at: float


## A fresh, undistorted memory formed by witnessing `event` firsthand (an
## actor) or from the sidelines (a witness). Returns null for an entity with
## no part in the event at all -- there is nothing to remember firsthand if
## you were not there.
static func from_event(event: Event, entity_id: String, tick: float) -> RefCounted:
	var source: String
	if event.actors.has(entity_id):
		source = FIRSTHAND
	elif event.witnesses.has(entity_id):
		source = WITNESSED
	else:
		return null

	var memory = new()
	memory.event_id = event.id
	memory.holder = entity_id
	memory.remembered_type = event.type
	memory.remembered_location = event.location
	memory.remembered_actors = event.actors.duplicate()
	memory.source_type = source
	memory.confidence = 1.0
	memory.distortion = 0.0
	memory.recorded_at = tick
	return memory


func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"holder": holder,
		"remembered_type": remembered_type,
		"remembered_location": remembered_location,
		"remembered_actors": remembered_actors,
		"remembered_outcome": remembered_outcome,
		"confidence": confidence,
		"emotional_salience": emotional_salience,
		"source_type": source_type,
		"distortion": distortion,
		"recorded_at": recorded_at,
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var memory = new()
	memory.event_id = d.get("event_id", "")
	memory.holder = d.get("holder", "")
	memory.remembered_type = d.get("remembered_type", "")
	memory.remembered_location = d.get("remembered_location", Vector2.ZERO)
	memory.remembered_actors = _typed_strings(d.get("remembered_actors", []))
	memory.remembered_outcome = d.get("remembered_outcome", "")
	memory.confidence = d.get("confidence", 0.0)
	memory.emotional_salience = d.get("emotional_salience", 0.0)
	memory.source_type = d.get("source_type", "")
	memory.distortion = d.get("distortion", 0.0)
	memory.recorded_at = d.get("recorded_at", 0.0)
	return memory


## Array[String] round-trips through FileAccess.store_var as a plain untyped
## Array -- same reason Event._typed_strings exists.
static func _typed_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out
