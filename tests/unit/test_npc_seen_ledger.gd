extends GutTest

## NpcSeenLedger (docs/concept/dialogue.md's pipeline, fourth stage): what
## this villager has already told THIS player, and how long ago -- the state
## behind "talk twice and you get the second most salient thing".
##
## Two traps this file exists to pin:
##   1. The ledger is keyed by the villager's entity id ("npc:<seed>"), NOT
##      held on the NpcMarker. Every marker is freed when its chunk unloads
##      (EarthChunkManager tears down a chunk's whole node subtree), so
##      anything remembered on the marker is gone the moment you walk two
##      chunks away -- which is exactly the walk that would otherwise reset a
##      conversation.
##   2. A burn RECOVERS. The ledger is not a "said it, never again" set; a
##      topic is worth saying again once the world has moved on, and how long
##      that takes is the world's own day, not a number picked here.

const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const TEST_PATH := "user://test_npc_seen_ledger.bin"

var ledger: NpcSeenLedger


func before_each():
	ledger = NpcSeenLedger.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


## Trap 1. The key has to be the same string EntityRef already builds for a
## villager, or the ledger indexes something no other system can name.
func test_the_key_is_the_entity_ref_npc_id_not_a_marker():
	assert_eq(NpcSeenLedger.key_for_seed(4711), EntityRef.for_npc(4711))
	assert_eq(NpcSeenLedger.key_for_seed(4711), "npc:4711")


func test_a_topic_never_told_has_no_record():
	assert_false(ledger.has_told("npc:1", "village"))
	assert_eq(ledger.last_told("npc:1", "village"), NpcSeenLedger.NEVER_TOLD)


func test_mark_told_records_the_tick_it_was_told_at():
	ledger.mark_told("npc:1", "village", 120.0)
	assert_true(ledger.has_told("npc:1", "village"))
	assert_eq(ledger.last_told("npc:1", "village"), 120.0)


## The most recent telling wins, the same "a later telling REPLACES the
## holder's existing record" rule MemoryStore._store already follows -- the
## ledger answers "how long since", which only has one answer.
func test_telling_the_same_topic_again_replaces_the_earlier_tick():
	ledger.mark_told("npc:1", "village", 120.0)
	ledger.mark_told("npc:1", "village", 300.0)
	assert_eq(ledger.last_told("npc:1", "village"), 300.0)


func test_one_villagers_burn_is_not_another_villagers():
	ledger.mark_told("npc:1", "village", 120.0)
	assert_false(ledger.has_told("npc:2", "village"))
	assert_eq(ledger.last_told("npc:2", "village"), NpcSeenLedger.NEVER_TOLD)


func test_one_topics_burn_is_not_another_topics():
	ledger.mark_told("npc:1", "village", 120.0)
	assert_false(ledger.has_told("npc:1", "weather"))


func test_topics_told_reads_in_a_deterministic_order():
	ledger.mark_told("npc:1", "weather", 10.0)
	ledger.mark_told("npc:1", "village", 20.0)
	ledger.mark_told("npc:1", "hunger", 30.0)
	var expected: Array[String] = ["hunger", "village", "weather"]
	assert_eq(ledger.topics_told("npc:1"), expected)
	assert_eq(ledger.topics_told("npc:unknown"), [] as Array[String])


func test_npc_ids_reads_in_a_deterministic_order():
	ledger.mark_told("npc:9", "village", 10.0)
	ledger.mark_told("npc:11", "village", 10.0)
	ledger.mark_told("npc:9", "weather", 10.0)
	var expected: Array[String] = ["npc:11", "npc:9"]
	assert_eq(ledger.npc_ids(), expected)


func test_to_dict_is_a_copy_a_caller_cannot_mutate_the_ledger_through():
	ledger.mark_told("npc:1", "village", 120.0)
	var snapshot := ledger.to_dict()
	snapshot["npc:1"]["village"] = 999.0
	snapshot["npc:2"] = {"weather": 5.0}
	assert_eq(ledger.last_told("npc:1", "village"), 120.0)
	assert_false(ledger.has_told("npc:2", "weather"))


## Persistence is someone else's module, but the state has to be something
## that convention can take: the whole ledger is a plain nested Dictionary of
## String -> String -> float, so the store_var/get_var convention PlayerSave/
## EventStorePersistence/WorldClockPersistence already share round-trips it
## with no adapter of its own.
func test_the_state_is_a_plain_dictionary_store_var_round_trips():
	ledger.mark_told("npc:4711", "village", 120.0)
	ledger.mark_told("npc:4711", "weather", 240.5)
	ledger.mark_told("npc:12", "hunger", 0.0)

	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_var(ledger.to_dict())
	file.close()

	var reader := FileAccess.open(TEST_PATH, FileAccess.READ)
	var restored = reader.get_var()
	reader.close()

	assert_eq(typeof(restored), TYPE_DICTIONARY)
	var reloaded := NpcSeenLedger.from_dict(restored)
	assert_eq(reloaded.last_told("npc:4711", "village"), 120.0)
	assert_eq(reloaded.last_told("npc:4711", "weather"), 240.5)
	assert_eq(reloaded.last_told("npc:12", "hunger"), 0.0)
	assert_eq(reloaded.npc_ids(), ledger.npc_ids())


func test_from_dict_of_junk_is_an_empty_ledger_rather_than_a_crash():
	assert_eq(NpcSeenLedger.from_dict({}).npc_ids(), [] as Array[String])
	var wrong_shape := {"npc:1": "not a topic map", "npc:2": {"village": "not a tick"}}
	var loaded := NpcSeenLedger.from_dict(wrong_shape)
	assert_false(loaded.has_told("npc:1", "village"))
	assert_eq(loaded.last_told("npc:2", "village"), 0.0)


func test_from_dict_is_not_a_view_onto_the_dictionary_it_was_given():
	var data := {"npc:1": {"village": 120.0}}
	var loaded := NpcSeenLedger.from_dict(data)
	data["npc:1"]["village"] = 999.0
	assert_eq(loaded.last_told("npc:1", "village"), 120.0)


## Trap 2, the anchor. REPEAT_DECAY_SECONDS is not a number chosen in this
## module: it is the world's own simulated day, read here off the two scripts
## that declare it so this test fails if either is retuned OR if the two ever
## drift apart from each other. Loading a script is not constructing one --
## no EarthChunkManager is instantiated here and no update() is run.
func test_repeat_decay_is_the_worlds_own_day_not_a_number_picked_here():
	var manager_day: float = (
		load("res://src/world/earth_chunk_manager.gd")
		. get_script_constant_map()["SECONDS_PER_SIMULATED_DAY"]
	)
	var marker_day: float = (
		load("res://src/rendering/npc_marker.gd")
		. get_script_constant_map()["SECONDS_PER_SIMULATED_DAY"]
	)
	assert_eq(manager_day, marker_day, "the two declarations of the day have drifted")
	assert_eq(NpcSeenLedger.SECONDS_PER_SIMULATED_DAY, manager_day)
	assert_eq(NpcSeenLedger.REPEAT_DECAY_SECONDS, manager_day)


func test_a_topic_never_told_decays_to_full_salience():
	assert_eq(ledger.decay("npc:1", "village", 0.0), 1.0)
	assert_eq(ledger.decay("npc:1", "village", 9999.0), 1.0)


func test_a_topic_just_told_is_fully_burned():
	ledger.mark_told("npc:1", "village", 120.0)
	assert_eq(ledger.decay("npc:1", "village", 120.0), 0.0)


## The whole mechanism in one assert: half a day on, the topic is worth half
## of what it was, so anything above half its salience outranks it.
func test_a_burn_recovers_linearly_with_world_age():
	var day: float = NpcSeenLedger.REPEAT_DECAY_SECONDS
	ledger.mark_told("npc:1", "village", 100.0)
	assert_almost_eq(ledger.decay("npc:1", "village", 100.0 + day * 0.25), 0.25, 0.0001)
	assert_almost_eq(ledger.decay("npc:1", "village", 100.0 + day * 0.5), 0.5, 0.0001)
	assert_almost_eq(ledger.decay("npc:1", "village", 100.0 + day * 0.75), 0.75, 0.0001)


func test_a_days_worth_of_world_age_recovers_the_topic_completely():
	var day: float = NpcSeenLedger.REPEAT_DECAY_SECONDS
	ledger.mark_told("npc:1", "village", 100.0)
	assert_eq(ledger.decay("npc:1", "village", 100.0 + day), 1.0)
	assert_eq(ledger.decay("npc:1", "village", 100.0 + day * 10.0), 1.0)


func test_decay_never_falls_back_as_the_world_ages():
	ledger.mark_told("npc:1", "village", 100.0)
	var previous := -1.0
	var step: float = NpcSeenLedger.REPEAT_DECAY_SECONDS / 20.0
	for i in range(40):
		var value := ledger.decay("npc:1", "village", 100.0 + step * i)
		assert_true(value >= previous, "decay went backwards at step %d" % i)
		previous = value


## A rewound clock must clamp to a full burn, never to a NEGATIVE multiplier.
## The world clock really can move backwards under this ledger: New Game
## calls EarthChunkManager.randomize_world_age, so a ledger restored beside a
## younger world would otherwise multiply salience by a negative number and
## inverse-sort every topic -- the least interesting thing said first.
func test_a_rewound_world_clock_clamps_to_a_burn_rather_than_going_negative():
	ledger.mark_told("npc:1", "village", 500.0)
	assert_eq(ledger.decay("npc:1", "village", 100.0), 0.0)
	assert_eq(ledger.decay("npc:1", "village", 0.0), 0.0)


func test_a_burn_is_per_villager_and_per_topic():
	ledger.mark_told("npc:1", "village", 100.0)
	assert_eq(ledger.decay("npc:2", "village", 100.0), 1.0)
	assert_eq(ledger.decay("npc:1", "weather", 100.0), 1.0)


func test_decay_survives_the_round_trip_the_marker_would_not():
	ledger.mark_told("npc:4711", "village", 100.0)
	var reloaded := NpcSeenLedger.from_dict(ledger.to_dict())
	assert_eq(reloaded.decay("npc:4711", "village", 100.0), 0.0)
	assert_almost_eq(
		reloaded.decay("npc:4711", "village", 100.0 + NpcSeenLedger.REPEAT_DECAY_SECONDS / 2.0),
		0.5,
		0.0001
	)
