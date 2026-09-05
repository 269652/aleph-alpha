extends GutTest

## NpcInteraction (src/dialogue/npc_interaction.gd) -- this stage's own named
## minimum bar (docs/concept/npc.md "Minimal talk interaction" and
## docs/concept/dialogue.md's pipeline/pillar 3 "the player is a node in the
## graph, not a camera"): a player's interaction with a real, scheduled NPC
## produces a real greeting AND appends one real memory record to that NPC's
## own memory log, referencing the interaction.
##
## Deliberately composes two pieces that are already real and already tested
## rather than inventing a third dialogue system: `NpcGreeting`'s
## deterministic personality/need line (docs/concept/npc.md's "Minimal talk
## interaction" placeholder), and `DialogueContext`'s frame for the one new
## fact this stage adds -- `time_block`, sourced from the shared world clock
## the exact way the NPC's own `NpcSchedule`/`NpcPlanner` daily plan already
## is (never `NpcMarker`'s private, per-marker clock -- see
## `DialogueContext`'s own "trap 3" doc comment). Not the full
## `DialogueTopic`/`DialogueMove`/`DialogueBeat`/`OfflineRenderer`/
## `ConversationWindow` Live Dialogue System pipeline (docs/concept/
## dialogue.md), which is real and tested up through `DialogueMove` but has
## no `DialogueBeat`/`OfflineRenderer`/`ConversationWindow` yet -- that is a
## separate, much larger effort this stage does not attempt.

const NpcInteraction = preload("res://src/dialogue/npc_interaction.gd")
const NpcGreeting = preload("res://src/world/npc_greeting.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcRecognition = preload("res://src/dialogue/npc_recognition.gd")
const DialogueContext = preload("res://src/dialogue/dialogue_context.gd")
const NpcSchedule = preload("res://src/world/npc_schedule.gd")

const EntityRef = preload("res://src/emergence/entity_ref.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")

## The real world-clock pacing every live villager's schedule -- and every
## DialogueContext frame -- already runs on. `NpcMarker.SECONDS_PER_SIMULATED_DAY`
## and `EarthChunkManager.SECONDS_PER_SIMULATED_DAY` are pinned equal by
## test_npc_seen_ledger.gd, so reusing the former here (rather than an
## invented fixture constant) means a checkpoint hour below means the same
## thing it would in the live game.
const _SECONDS_PER_DAY := NpcMarker.SECONDS_PER_SIMULATED_DAY
const _SECONDS_PER_HOUR := _SECONDS_PER_DAY / 24.0

var _npcs: Array = []


func after_each():
	for npc in _npcs:
		if is_instance_valid(npc):
			remove_child(npc)
			npc.free()
	_npcs = []


func _identity_for_occupation(occupation: String) -> NpcIdentity:
	for seed_value in range(50):
		var candidate := NpcIdentity.new(seed_value)
		if candidate.occupation == occupation:
			return candidate
	return null


## The middle of `hour`'s own window -- comfortably clear of either boundary,
## so a float-rounding wobble in DialogueContext.hour_of_day can never land
## one hour off (see the guard test below, which checks this against the
## real function rather than trusting the arithmetic on faith).
func _world_age_for_hour(hour: int) -> float:
	return (float(hour) + 0.5) * _SECONDS_PER_HOUR


## Tuned-value guard (this project's own "never an eyeballed comment" rule):
## proves the checkpoint hours the tests below assume really do land in the
## NpcSchedule time blocks they claim, through the REAL DialogueContext/
## NpcSchedule functions rather than an independently hand-copied table.
func test_the_checkpoint_hours_land_in_the_expected_time_blocks():
	var checks := {3: "night", 13: "midday", 21: "evening"}
	for hour in checks:
		var world_age: float = _world_age_for_hour(hour)
		var measured_hour := DialogueContext.hour_of_day(world_age, _SECONDS_PER_DAY)
		assert_eq(measured_hour, hour, "checkpoint hour %d drifted under rounding" % hour)
		assert_eq(
			NpcSchedule.time_block_for_hour(measured_hour),
			checks[hour],
			"checkpoint hour %d is not the time block the test assumes" % hour
		)


func test_without_a_world_clock_the_greeting_is_the_real_npcgreeting_line_unchanged():
	var identity := NpcIdentity.new(7)
	var result := NpcInteraction.talk(identity, {})
	assert_eq(result["greeting"], NpcGreeting.new().greeting_for(identity))
	assert_eq(result["time_block"], "", "an unknown hour must not invent a time-of-day flavor")


func test_the_greeting_differs_between_two_real_times_of_day_for_the_same_villager():
	var identity := NpcIdentity.new(7)
	var midday := NpcInteraction.talk(identity, {
		"world_age_seconds": _world_age_for_hour(13),
		"seconds_per_simulated_day": _SECONDS_PER_DAY,
	})
	var night := NpcInteraction.talk(identity, {
		"world_age_seconds": _world_age_for_hour(3),
		"seconds_per_simulated_day": _SECONDS_PER_DAY,
	})
	assert_eq(midday["time_block"], "midday")
	assert_eq(night["time_block"], "night")
	assert_ne(midday["greeting"], night["greeting"], "the same villager's line should vary by time of day")
	assert_string_contains(midday["greeting"], identity.npc_name)
	assert_string_contains(night["greeting"], identity.npc_name)


func test_with_no_stores_nothing_is_recorded_but_the_greeting_still_returns():
	var identity := NpcIdentity.new(7)
	var result := NpcInteraction.talk(identity, {})
	assert_ne(result["greeting"], "")
	assert_null(result["npc_memory"])
	assert_null(result["player_memory"])


## This stage's own named minimum bar: a real interaction with a real NPC
## produces a real greeting AND grows that NPC's memory log by one real
## record referencing the interaction.
func test_talking_grows_the_npcs_own_memory_log_by_one_real_record_referencing_the_interaction():
	var identity := NpcIdentity.new(7)
	var npc_id := EntityRef.for_npc(identity.seed_value)
	var event_store := EventStore.new()
	var memory_store := MemoryStore.new()

	assert_eq(memory_store.memories_for(npc_id).size(), 0, "precondition: no memory yet")

	var result := NpcInteraction.talk(identity, {
		"event_store": event_store,
		"memory_store": memory_store,
	})

	assert_ne(result["greeting"], "")

	var memories := memory_store.memories_for(npc_id)
	assert_eq(memories.size(), 1, "the NPC's memory log should have grown by exactly one record")
	var record: MemoryRecord = memories[0]
	assert_eq(record.holder, npc_id)
	assert_ne(result["event"].id, "", "the referenced event must be a real, stored one")
	assert_eq(record.event_id, result["event"].id)
	assert_eq(record.source_type, MemoryRecord.FIRSTHAND, "the NPC was a real party to their own conversation")
	assert_eq(record.remembered_type, NpcInteraction.EVENT_TYPE)

	# "Referencing the interaction" means a real, resolvable id in the real
	# EventStore -- not merely a matching string on an object nobody stored.
	var stored_event := event_store.get_event(result["event"].id)
	assert_not_null(stored_event)
	assert_true(stored_event.actors.has(npc_id))


## dialogue.md pillar 3: "the player is a node in the graph, not a camera"
## -- one event per conversation makes player:local a real actor too, not
## just the NPC's own private record of having been talked at.
func test_the_player_also_holds_their_own_firsthand_memory_of_the_same_conversation():
	var identity := NpcIdentity.new(7)
	var event_store := EventStore.new()
	var memory_store := MemoryStore.new()

	var result := NpcInteraction.talk(identity, {
		"event_store": event_store,
		"memory_store": memory_store,
	})

	var player_memories := memory_store.memories_for(PlayerIdentity.PLAYER_ENTITY_ID)
	assert_eq(player_memories.size(), 1)
	assert_eq(player_memories[0].event_id, result["event"].id)
	assert_eq(player_memories[0].source_type, MemoryRecord.FIRSTHAND)
	assert_not_null(result["player_memory"])
	assert_eq(result["player_memory"].event_id, result["event"].id)


func test_two_separate_conversations_grow_the_log_twice_with_distinct_events():
	var identity := NpcIdentity.new(7)
	var npc_id := EntityRef.for_npc(identity.seed_value)
	var event_store := EventStore.new()
	var memory_store := MemoryStore.new()

	var first := NpcInteraction.talk(identity, {"event_store": event_store, "memory_store": memory_store})
	var second := NpcInteraction.talk(identity, {"event_store": event_store, "memory_store": memory_store})

	assert_ne(first["event"].id, second["event"].id, "two real conversations are two real events")
	assert_eq(memory_store.memories_for(npc_id).size(), 2)


## dialogue.md "You are in the graph": a real conversation is real shared
## history, so NpcRecognition -- built to read exactly this event shape --
## should stop calling this player a stranger after just one, with no
## NpcRecognition change of its own required.
func test_after_talking_npcrecognition_no_longer_reads_the_player_as_a_stranger():
	var identity := NpcIdentity.new(7)
	var npc_id := EntityRef.for_npc(identity.seed_value)
	var event_store := EventStore.new()
	var memory_store := MemoryStore.new()

	var before := NpcRecognition.tier_for({"npc_id": npc_id, "event_store": event_store})
	assert_eq(before["tier"], NpcRecognition.STRANGER)

	NpcInteraction.talk(identity, {"event_store": event_store, "memory_store": memory_store})

	var after := NpcRecognition.tier_for({"npc_id": npc_id, "event_store": event_store})
	assert_eq(after["tier"], NpcRecognition.KNOWS_YOU)


## Capstone: a genuinely REAL scheduled NPC -- a live NpcMarker with its own
## default FakeNpcPlanner-produced schedule, advanced through real elapsed
## process time (the same pattern test_npc_daily_schedule_walk.gd's own
## capstone uses), not merely an NpcIdentity constructed in isolation --
## mid-workday, gets a real greeting flavored by that exact moment and a
## real memory of having been talked to.
func test_a_real_scheduled_npc_mid_workday_gets_a_real_greeting_and_a_real_memory():
	var identity := _identity_for_occupation("farmer")
	assert_not_null(identity, "precondition: expected a farmer within 50 seeds")

	var marker := NpcMarker.new()
	marker.home_position = Vector2(1000.0, 1000.0)
	marker.workspot_position = Vector2(1000.0, 1100.0)
	marker.landmarks = {"well": Vector2(1100.0, 1000.0)}
	marker.position = marker.home_position
	marker.identity = identity
	add_child(marker)
	_npcs.append(marker)

	var elapsed := 0.0
	var target: float = _world_age_for_hour(13)  # midday -- see the guard test above
	while elapsed < target:
		marker._process(0.25)
		elapsed += 0.25

	assert_almost_eq(
		marker.position.distance_to(marker.workspot_position), 0.0, 1.0,
		"precondition: the marker's own real (lazily generated) schedule should have it at the field by midday"
	)

	var event_store := EventStore.new()
	var memory_store := MemoryStore.new()
	var result := NpcInteraction.talk(marker.identity, {
		"world_age_seconds": elapsed,
		"seconds_per_simulated_day": NpcMarker.SECONDS_PER_SIMULATED_DAY,
		"event_store": event_store,
		"memory_store": memory_store,
	})

	assert_string_contains(result["greeting"], identity.npc_name)
	assert_eq(result["time_block"], "midday")

	var npc_id := EntityRef.for_npc(identity.seed_value)
	var memories := memory_store.memories_for(npc_id)
	assert_eq(memories.size(), 1, "talking to the real scheduled NPC should grow its memory log by one")
	assert_eq(memories[0].event_id, result["event"].id)
