extends GutTest

## MemoryStore: the per-entity store of MemoryRecords (see
## docs/emergence/02-history-memory-rumors.md "Memory").
##
## Layered on top of EventStore the same way EventStore itself is a separate,
## composable piece -- witnessing an event is a distinct step from recording
## it (see docs/emergence/00's authoritative loop: "emit events -> update
## memories/beliefs"), not folded into EventStore.append, so EventStore stays
## usable for entities that do not have memories at all (a settlement does
## not "remember" the way an NPC does).

const Event = preload("res://src/emergence/event.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")

var bank: MemoryStore


func before_each():
	bank = MemoryStore.new()


func _event() -> Event:
	var event := Event.new("settlement_founded", 1.0)
	event.id = "evt_0_settlement_founded"
	event.actors = ["settlement:0_0"]
	event.witnesses = ["npc:1", "npc:2"]
	return event


# -- witnessing ----------------------------------------------------------------

## Witnessing an event forms a memory for EVERY actor and witness in one
## call -- a settlement founding is remembered by the settlement AND by
## every villager present, not just whoever the caller happened to name.
func test_witnessing_an_event_forms_a_memory_for_every_actor_and_witness():
	var formed := bank.witness_event(_event(), 1.0)
	assert_eq(formed.size(), 3)
	var holders: Array = []
	for memory in formed:
		holders.append(memory.holder)
	assert_true(holders.has("settlement:0_0"))
	assert_true(holders.has("npc:1"))
	assert_true(holders.has("npc:2"))


func test_memories_for_returns_what_was_witnessed():
	bank.witness_event(_event(), 1.0)
	var memories := bank.memories_for("npc:1")
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].event_id, "evt_0_settlement_founded")
	assert_eq(memories[0].source_type, MemoryRecord.WITNESSED)


func test_an_uninvolved_entity_has_no_memories():
	bank.witness_event(_event(), 1.0)
	assert_eq(bank.memories_for("npc:999"), [])


## Witnessing the SAME event twice must not duplicate the memory -- an NPC
## does not remember one founding twice just because something re-recorded
## the same event.
func test_witnessing_the_same_event_twice_does_not_duplicate_the_memory():
	bank.witness_event(_event(), 1.0)
	bank.witness_event(_event(), 1.0)
	assert_eq(bank.memories_for("npc:1").size(), 1)


# -- transmission ----------------------------------------------------------

## The whole Phase 2 exit criterion: NPC A can tell NPC B about an event, and
## B receives a lower-confidence representation (see docs/roadmap.md).
func test_one_entity_can_tell_another_about_an_event():
	bank.witness_event(_event(), 1.0)
	var told := bank.transmit("npc:1", "npc:3", "evt_0_settlement_founded", 5.0)
	assert_not_null(told)
	assert_eq(told.holder, "npc:3")
	assert_lt(told.confidence, 1.0)

	var received := bank.memories_for("npc:3")
	assert_eq(received.size(), 1)
	assert_eq(received[0].event_id, "evt_0_settlement_founded")


## Nothing to tell if the teller never actually knew about it.
func test_transmit_from_someone_with_no_such_memory_does_nothing():
	var told := bank.transmit("npc:1", "npc:3", "evt_0_nothing_recorded", 5.0)
	assert_null(told)
	assert_eq(bank.memories_for("npc:3"), [])


## Hearing the SAME event from the SAME source twice does not duplicate it
## either -- one retelling of one event from one source is one memory,
## refreshed rather than piled up.
func test_hearing_the_same_thing_twice_does_not_duplicate_the_memory():
	bank.witness_event(_event(), 1.0)
	bank.transmit("npc:1", "npc:3", "evt_0_settlement_founded", 5.0)
	bank.transmit("npc:1", "npc:3", "evt_0_settlement_founded", 6.0)
	assert_eq(bank.memories_for("npc:3").size(), 1)


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_bank():
	bank.witness_event(_event(), 1.0)
	bank.transmit("npc:1", "npc:3", "evt_0_settlement_founded", 5.0)

	var restored := MemoryStore.from_dicts(bank.to_dicts())

	assert_eq(restored.memories_for("npc:1").size(), 1)
	assert_eq(restored.memories_for("npc:3").size(), 1)
	assert_eq(restored.memories_for("npc:3")[0].confidence, bank.memories_for("npc:3")[0].confidence)


## A restored bank must still dedupe correctly -- re-witnessing an event it
## already holds a memory of (from before the save) must not duplicate it.
func test_a_restored_bank_still_dedupes_correctly():
	bank.witness_event(_event(), 1.0)
	var restored := MemoryStore.from_dicts(bank.to_dicts())
	restored.witness_event(_event(), 1.0)
	assert_eq(restored.memories_for("npc:1").size(), 1)
