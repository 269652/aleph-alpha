extends GutTest

## MemoryRecord (see docs/emergence/02-history-memory-rumors.md "Memory" and
## "Fact versus belief").
##
## An NPC's memory is a LOSSY PROJECTION of an authoritative event -- it
## references the event by id (so it can always be checked against ground
## truth) but carries its own, possibly-wrong, remembered fields, plus
## confidence and source type. The authoritative Event never gets
## overwritten by a belief about it; a MemoryRecord is a separate thing that
## can simply be wrong.

const Event = preload("res://src/emergence/event.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")


func _event() -> Event:
	var event := Event.new("crop_failure", 12.0, Vector2(5.0, 6.0))
	event.id = "evt_3_crop_failure"
	event.actors = ["npc:1"]
	event.witnesses = ["npc:2"]
	event.tags = ["famine"]
	return event


# -- forming a firsthand/witnessed memory -------------------------------------

## An ACTOR's own memory of an event is FIRSTHAND -- they did it, they know
## exactly what happened. Starts fully confident, no distortion.
func test_an_actor_forms_a_firsthand_memory():
	var memory := MemoryRecord.from_event(_event(), "npc:1", 12.0)
	assert_eq(memory.event_id, "evt_3_crop_failure")
	assert_eq(memory.holder, "npc:1")
	assert_eq(memory.source_type, MemoryRecord.FIRSTHAND)
	assert_eq(memory.confidence, 1.0)
	assert_eq(memory.distortion, 0.0)


## A WITNESS's memory is WITNESSED, not firsthand -- they saw it happen to
## someone else, a real but distinct source type.
func test_a_witness_forms_a_witnessed_memory():
	var memory := MemoryRecord.from_event(_event(), "npc:2", 12.0)
	assert_eq(memory.source_type, MemoryRecord.WITNESSED)


## An entity with no part in the event has nothing to remember firsthand.
func test_an_uninvolved_entity_forms_no_memory():
	assert_null(MemoryRecord.from_event(_event(), "npc:999", 12.0))


## The remembered fields start as an exact copy of the real event -- a fresh
## firsthand memory has not drifted from the truth yet.
func test_a_fresh_memory_remembers_the_event_accurately():
	var memory := MemoryRecord.from_event(_event(), "npc:1", 12.0)
	assert_eq(memory.remembered_type, "crop_failure")
	assert_eq(memory.remembered_location, Vector2(5.0, 6.0))
	assert_eq(memory.remembered_actors, ["npc:1"])


## recorded_at is WHEN the holder came to hold this memory, not the event's
## own tick -- for a fresh memory those happen to be the same tick, but they
## are conceptually different fields (see test_rumor.gd, where they diverge).
func test_records_when_the_memory_was_formed():
	var memory := MemoryRecord.from_event(_event(), "npc:1", 12.0)
	assert_eq(memory.recorded_at, 12.0)


func test_emotional_salience_defaults_to_zero():
	var memory := MemoryRecord.from_event(_event(), "npc:1", 12.0)
	assert_eq(memory.emotional_salience, 0.0)


# -- source types are the module's own enumerated set -------------------------

func test_every_documented_source_type_exists():
	var expected := [
		"firsthand", "witnessed", "trusted_testimony", "stranger_testimony",
		"inference", "written_record", "rumor",
	]
	for source in expected:
		assert_true(
			MemoryRecord.SOURCE_TYPES.has(source), "missing documented source type: %s" % source
		)


# -- persistence round trip ---------------------------------------------------

## Round-trips every field, since MemoryStorePersistence's whole job depends
## on this being lossless (see test_memory_store_persistence.gd).
func test_to_dict_and_from_dict_round_trip_every_field():
	var memory := MemoryRecord.from_event(_event(), "npc:1", 12.0)
	memory.emotional_salience = 0.4
	memory.confidence = 0.75
	memory.distortion = 0.3
	memory.remembered_outcome = "famine"

	var restored := MemoryRecord.from_dict(memory.to_dict())

	assert_eq(restored.event_id, memory.event_id)
	assert_eq(restored.holder, memory.holder)
	assert_eq(restored.remembered_type, memory.remembered_type)
	assert_eq(restored.remembered_location, memory.remembered_location)
	assert_eq(restored.remembered_actors, memory.remembered_actors)
	assert_eq(restored.remembered_outcome, memory.remembered_outcome)
	assert_eq(restored.confidence, memory.confidence)
	assert_eq(restored.emotional_salience, memory.emotional_salience)
	assert_eq(restored.source_type, memory.source_type)
	assert_eq(restored.distortion, memory.distortion)
	assert_eq(restored.recorded_at, memory.recorded_at)
