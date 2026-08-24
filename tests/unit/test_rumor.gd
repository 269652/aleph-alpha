extends GutTest

## Rumor: how a MemoryRecord transmits from one holder to another (see
## docs/emergence/02-history-memory-rumors.md "Rumor propagation").
##
## Deliberately simple for a first slice: transmission decays confidence and
## degrades source type by a fixed, tested amount per hop, with no real
## trust/relationship weighting yet -- npc_identity.gd has no relationships to
## weight by (see docs/roadmap.md's Emergence Phase 3, not built). This is the
## honest MVP the module's own "avoid premature complexity" principle calls
## for: a real, working, testable mechanism now; trust-weighted transmission
## once relationships exist to weight it with.

const Event = preload("res://src/emergence/event.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const Rumor = preload("res://src/emergence/rumor.gd")


func _firsthand_memory() -> MemoryRecord:
	var event := Event.new("crop_failure", 1.0, Vector2(5.0, 6.0))
	event.id = "evt_0_crop_failure"
	event.actors = ["npc:1"]
	return MemoryRecord.from_event(event, "npc:1", 1.0)


# -- confidence decays each hop -----------------------------------------------

func test_transmission_reduces_confidence():
	var original := _firsthand_memory()
	var told := Rumor.transmit(original, "npc:2", 5.0)
	assert_lt(told.confidence, original.confidence)


## Pinned exactly against the tested decay constant -- a tuned value, not an
## eyeballed number (per CLAUDE.md).
func test_confidence_decays_by_the_tested_constant():
	var original := _firsthand_memory()
	var told := Rumor.transmit(original, "npc:2", 5.0)
	assert_almost_eq(told.confidence, original.confidence * Rumor.CONFIDENCE_DECAY_PER_HOP, 0.0001)


func test_confidence_keeps_decaying_across_repeated_hops():
	var memory := _firsthand_memory()
	var previous := memory.confidence
	for hop in 4:
		memory = Rumor.transmit(memory, "npc:%d" % (hop + 2), float(hop + 2))
		assert_lt(memory.confidence, previous)
		previous = memory.confidence


# -- source type degrades toward RUMOR, monotonically -------------------------

func test_a_firsthand_account_becomes_trusted_testimony_on_first_retelling():
	var told := Rumor.transmit(_firsthand_memory(), "npc:2", 5.0)
	assert_eq(told.source_type, MemoryRecord.TRUSTED_TESTIMONY)


func test_a_witnessed_account_also_becomes_trusted_testimony_on_first_retelling():
	var event := Event.new("crop_failure", 1.0)
	event.id = "evt_0_crop_failure"
	event.witnesses = ["npc:1"]
	var memory := MemoryRecord.from_event(event, "npc:1", 1.0)
	var told := Rumor.transmit(memory, "npc:2", 5.0)
	assert_eq(told.source_type, MemoryRecord.TRUSTED_TESTIMONY)


func test_trusted_testimony_becomes_stranger_testimony_on_the_next_retelling():
	var memory := _firsthand_memory()
	memory = Rumor.transmit(memory, "npc:2", 5.0)
	memory = Rumor.transmit(memory, "npc:3", 6.0)
	assert_eq(memory.source_type, MemoryRecord.STRANGER_TESTIMONY)


## Past stranger_testimony it settles at RUMOR and stays there -- degradation
## is monotonic, it never climbs back toward a more trustworthy source just
## because it was retold again.
func test_stranger_testimony_becomes_rumor_and_rumor_stays_rumor():
	var memory := _firsthand_memory()
	memory = Rumor.transmit(memory, "npc:2", 5.0)
	memory = Rumor.transmit(memory, "npc:3", 6.0)
	memory = Rumor.transmit(memory, "npc:4", 7.0)
	assert_eq(memory.source_type, MemoryRecord.RUMOR)
	memory = Rumor.transmit(memory, "npc:5", 8.0)
	assert_eq(memory.source_type, MemoryRecord.RUMOR)


# -- distortion accumulates, tracked but not yet applied to content ----------

## Content distortion is deliberately deferred (see docs/concept/npc.md's
## "Memory, beliefs, and rumor propagation": "this pass keeps believed
## actors/location/outcome equal to the source event and only decays
## confidence/salience; content mutation is a real follow-up once a
## scenario actually needs it"). The FIELD is tracked from hop one -- the
## schema names "a distortion accumulator" as part of what a memory holds --
## it just does not yet change what is remembered.
func test_transmission_increases_the_distortion_accumulator():
	var told := Rumor.transmit(_firsthand_memory(), "npc:2", 5.0)
	assert_gt(told.distortion, 0.0)


## Specifics survive retelling, however many hops -- content is not yet
## mutated by distortion, only confidence/source type are.
func test_remembered_actors_survive_transmission_unchanged():
	var memory := _firsthand_memory()
	for hop in 5:
		memory = Rumor.transmit(memory, "npc:%d" % (hop + 2), float(hop + 2))
	assert_eq(memory.remembered_actors, ["npc:1"])


# -- provenance is never lost, however distorted the content gets ------------

## However garbled the retelling, it still points at the SAME real event --
## this is what makes it checkable at all (see docs/emergence/02's own
## worked example: "Fact: village burned during E201. Belief: bandits burned
## it." -- wrong content, but still clearly about E201).
func test_the_event_id_never_changes_no_matter_how_many_hops():
	var memory := _firsthand_memory()
	for hop in 5:
		memory = Rumor.transmit(memory, "npc:%d" % (hop + 2), float(hop + 2))
	assert_eq(memory.event_id, "evt_0_crop_failure")


func test_the_new_holder_is_recorded():
	var told := Rumor.transmit(_firsthand_memory(), "npc:2", 5.0)
	assert_eq(told.holder, "npc:2")


## The original event happened at tick 1.0; this retelling is heard at tick
## 5.0 -- recorded_at tracks the LATTER, since it is about when this holder
## came to know it, not when the event itself occurred.
func test_recorded_at_is_when_the_new_holder_heard_it_not_the_original_event_tick():
	var told := Rumor.transmit(_firsthand_memory(), "npc:2", 5.0)
	assert_eq(told.recorded_at, 5.0)
