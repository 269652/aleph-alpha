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
## Only to pin the FORMATION values against the ladder Rumor already defines
## (see the "belief strength at formation" section) -- nothing here changes
## or re-tests transmission itself, which test_rumor.gd owns.
const Rumor = preload("res://src/emergence/rumor.gd")


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


# -- belief strength at formation ---------------------------------------------
#
# from_event used to hand BOTH an actor and a witness confidence 1.0, so every
# directly-formed belief in the world was exactly equally strong and every
# memory-backed dialogue topic scored an identical 1.0 (dialogue_topic.gd's
# belief_strength is confidence x (1 - distortion)). These tests pin the
# spread that replaces that flat value.


## An ACTOR is more certain than a WITNESS -- it happened to them; the witness
## only saw it happen to someone else. The distinction was already drawn (it
## picks the source type just above); it just did not reach confidence.
func test_a_witness_is_less_certain_than_the_actor_it_happened_to():
	var event := _event()
	var actor := MemoryRecord.from_event(event, "npc:1", 12.0)
	var witness := MemoryRecord.from_event(event, "npc:2", 12.0)
	assert_lt(witness.confidence, actor.confidence)


## ...but watching it happen still beats being TOLD by the person it happened
## to. This is the ordering constraint the witness value has to satisfy, and
## it is a real one: if a retold firsthand account outscored an eyewitness,
## hearsay would rank above having been there.
func test_a_witness_is_more_certain_than_someone_told_by_the_actor():
	var event := _event()
	var actor := MemoryRecord.from_event(event, "npc:1", 12.0)
	var witness := MemoryRecord.from_event(event, "npc:2", 12.0)
	var told = Rumor.transmit(actor, "npc:3", 13.0)
	assert_gt(witness.confidence, told.confidence)


## The witness value itself, pinned rather than eyeballed: it is placed half
## of one retelling below an actor, on the same multiplicative ladder Rumor
## uses -- so squaring it lands back exactly on Rumor's per-hop decay.
##
## This test proves that identity and the two orderings above; it does NOT
## prove that "half a hop" is the right size of gap, which is a stated
## modelling choice (see WITNESS_CONFIDENCE's docstring).
func test_the_witness_gap_is_half_a_retelling_on_rumors_own_ladder():
	var witness := MemoryRecord.from_event(_event(), "npc:2", 12.0)
	assert_almost_eq(
		witness.confidence * witness.confidence, Rumor.CONFIDENCE_DECAY_PER_HOP, 0.0001
	)


## Event.importance is already on every event and really is written by src/
## (0.2 to 0.7, on five emitters). A witness of a consequential event holds it
## more firmly than a witness of a trivial one.
func test_a_witness_of_a_more_important_event_is_more_certain():
	var trivial := _event()
	var weighty := _event()
	weighty.importance = 0.4
	assert_gt(
		MemoryRecord.from_event(weighty, "npc:2", 12.0).confidence,
		MemoryRecord.from_event(trivial, "npc:2", 12.0).confidence
	)


## Importance LIFTS a witness toward certainty by that fraction of the gap --
## it never discounts. The direction matters: most Event emitters in src/
## never set importance at all, and dialogue_topic.belief_strength already
## refuses to MULTIPLY it into salience for exactly that reason. A lift
## leaves every importance-less event sitting on the base value.
func test_importance_closes_that_fraction_of_a_witnesss_gap_to_certainty():
	var base: float = MemoryRecord.from_event(_event(), "npc:2", 12.0).confidence
	var weighty := _event()
	weighty.importance = 0.4
	var lifted: float = MemoryRecord.from_event(weighty, "npc:2", 12.0).confidence
	assert_almost_eq(lifted, base + (1.0 - base) * 0.4, 0.0001)


## An actor is already at the ceiling -- it happened to them, there is no
## further certainty importance could buy.
func test_importance_does_not_move_an_actor_off_full_certainty():
	var weighty := _event()
	weighty.importance = 0.7
	assert_eq(MemoryRecord.from_event(weighty, "npc:1", 12.0).confidence, 1.0)


## Confidence stays inside [0,1] whatever importance says. DialogueTopic ranks
## memory topics on this number against topics normalised to that range, so an
## out-of-range importance must not push a memory off the shared scale.
func test_confidence_stays_within_zero_to_one_for_an_out_of_range_importance():
	var event := _event()
	event.importance = 5.0
	assert_eq(MemoryRecord.from_event(event, "npc:2", 12.0).confidence, 1.0)


## Distortion stays 0.0 for actor AND witness, deliberately. This field is how
## far the remembered fields have ACTUALLY drifted, and from_event copies them
## exactly from the event for both. Only confidence -- how sure the holder
## FEELS -- carries a witness's lesser certainty.
func test_a_freshly_formed_memory_has_not_drifted_for_actor_or_witness():
	var event := _event()
	assert_eq(MemoryRecord.from_event(event, "npc:1", 12.0).distortion, 0.0)
	assert_eq(MemoryRecord.from_event(event, "npc:2", 12.0).distortion, 0.0)


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
