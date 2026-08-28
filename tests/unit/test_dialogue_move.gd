extends GutTest

## DialogueMove (docs/concept/dialogue.md's pipeline, fifth stage): picks what
## this villager actually says, top-k by `salience x NpcSeenLedger.decay`.
##
## Written against hand-built topic Dictionaries. DialogueTopic is a sibling
## module being built alongside this one, and coupling this file to its
## internals would make these tests a test of that module; the only contract
## assumed here is the two keys a scored topic must carry -- `topic_id` and
## `salience` -- with everything else carried through untouched.
##
## Three things this file pins, each a real failure mode rather than a
## restatement of the implementation:
##   1. The output must not depend on the ORDER the topics arrived in.
##      Anything upstream that iterates a Dictionary hands them over in an
##      order that is an implementation detail, so an unstable sort would
##      make a villager's opening line change between two runs of the same
##      world.
##   2. A tie must break on the topic id, not on a hash. Godot's hash() is
##      not a stable ordering to build a save-visible decision on.
##   3. An empty fact is an omitted topic (dialogue.md's second pillar). A
##      villager with nothing worth saying says NOTHING here; the alternative
##      -- a filler line -- is the exact failure this system is designed
##      against, and it would also hide the substrate bug that produced the
##      empty topic.

const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")

const NPC := "npc:4711"

var ledger: NpcSeenLedger


func before_each():
	ledger = NpcSeenLedger.new()


func _topic(topic_id: String, salience: float, extra: Dictionary = {}) -> Dictionary:
	var topic := {"topic_id": topic_id, "salience": salience}
	for key in extra:
		topic[key] = extra[key]
	return topic


func _ids(moves: Array) -> Array[String]:
	var out: Array[String] = []
	for move in moves:
		out.append(move["topic_id"])
	return out


func test_the_most_salient_topic_is_the_one_they_lead_with():
	var topics := [_topic("weather", 0.2), _topic("hunger", 0.9), _topic("village", 0.5)]
	var moves := DialogueMove.select(topics, ledger, NPC, 100.0, 7, 3)
	assert_eq(_ids(moves), ["hunger", "village", "weather"] as Array[String])
	assert_eq(moves[0]["rank"], 0)
	assert_eq(moves[2]["rank"], 2)


## The headline mechanism: talk twice and you get the SECOND most salient
## thing. Nothing about the world changed between these two calls except the
## ledger entry the first conversation wrote.
func test_talking_twice_gives_the_second_most_salient_thing():
	var topics := [_topic("hunger", 0.9), _topic("village", 0.5)]
	var first := DialogueMove.select_one(topics, ledger, NPC, 100.0, 7)
	assert_eq(first["topic_id"], "hunger")

	ledger.mark_told(NPC, first["topic_id"], 100.0)

	var second := DialogueMove.select_one(topics, ledger, NPC, 100.0, 7)
	assert_eq(second["topic_id"], "village")


func test_a_burned_topic_comes_back_once_the_world_has_moved_on():
	var topics := [_topic("hunger", 0.9), _topic("village", 0.5)]
	ledger.mark_told(NPC, "hunger", 100.0)
	var day: float = NpcSeenLedger.REPEAT_DECAY_SECONDS

	# Barely into the day: 0.9 x a small decay is still under 0.5.
	var early := DialogueMove.select_one(topics, ledger, NPC, 100.0 + day * 0.1, 7)
	assert_eq(early["topic_id"], "village")
	# Most of a day on: 0.9 x 0.8 outranks the untouched 0.5 again.
	var late := DialogueMove.select_one(topics, ledger, NPC, 100.0 + day * 0.8, 7)
	assert_eq(late["topic_id"], "hunger")


## Pillar 2, at the move layer. A villager who has just said the only thing
## they had says nothing, rather than saying it twice.
func test_a_villager_with_only_a_burned_topic_says_nothing():
	var topics := [_topic("hunger", 0.9)]
	ledger.mark_told(NPC, "hunger", 100.0)
	assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 3), [] as Array[Dictionary])
	assert_true(DialogueMove.select_one(topics, ledger, NPC, 100.0, 7).is_empty())


func test_a_topic_with_no_salience_is_omitted_rather_than_filled_in():
	var topics := [_topic("hunger", 0.0), _topic("village", -0.3), _topic("weather", 0.1)]
	var moves := DialogueMove.select(topics, ledger, NPC, 100.0, 7, 5)
	assert_eq(_ids(moves), ["weather"] as Array[String])


func test_no_topics_at_all_is_an_empty_answer_not_a_filler_move():
	assert_eq(DialogueMove.select([], ledger, NPC, 100.0, 7, 3), [] as Array[Dictionary])
	assert_true(DialogueMove.select_one([], ledger, NPC, 100.0, 7).is_empty())


func test_the_move_carries_the_numbers_it_was_ranked_by():
	var topics := [_topic("hunger", 0.8)]
	ledger.mark_told(NPC, "hunger", 100.0)
	var day: float = NpcSeenLedger.REPEAT_DECAY_SECONDS
	var move := DialogueMove.select_one(topics, ledger, NPC, 100.0 + day * 0.5, 7)

	assert_eq(move["topic_id"], "hunger")
	assert_almost_eq(float(move["salience"]), 0.8, 0.0001)
	assert_almost_eq(float(move["decay"]), 0.5, 0.0001)
	assert_almost_eq(float(move["score"]), 0.4, 0.0001)
	assert_eq(move["last_told"], 100.0)
	assert_true(move["repeat"], "a topic the ledger has a row for is a repeat")


func test_a_first_telling_is_not_marked_as_a_repeat():
	var move := DialogueMove.select_one([_topic("hunger", 0.8)], ledger, NPC, 100.0, 7)
	assert_false(move["repeat"])
	assert_eq(move["last_told"], NpcSeenLedger.NEVER_TOLD)
	assert_eq(move["decay"], 1.0)


func test_a_move_carries_exactly_the_declared_fields():
	var move := DialogueMove.select_one([_topic("hunger", 0.8)], ledger, NPC, 100.0, 7)
	var keys: Array[String] = []
	for key in move:
		keys.append(key)
	keys.sort()
	var expected := DialogueMove.MOVE_FIELDS.duplicate()
	expected.sort()
	assert_eq(keys, expected)


## The topic Dictionary rides along untouched, because the facts a beat needs
## to render are on it and this module is not the one that knows what they
## mean.
func test_the_scored_topic_rides_along_verbatim():
	var topic := _topic("shortfall", 0.7, {"facts": [{"key": "item", "value": "rock"}], "kind": "ask"})
	var move := DialogueMove.select_one([topic], ledger, NPC, 100.0, 7)
	assert_eq(move["topic"], topic)


## Trap 2. Two topics with identical salience and identical history: the
## alphabetically-first id leads, whichever order they arrived in.
func test_a_tie_breaks_on_the_topic_id():
	var village_first := [_topic("village", 0.5), _topic("hunger", 0.5)]
	var hunger_first := [_topic("hunger", 0.5), _topic("village", 0.5)]
	var forwards := DialogueMove.select(village_first, ledger, NPC, 100.0, 7, 2)
	var backwards := DialogueMove.select(hunger_first, ledger, NPC, 100.0, 7, 2)
	assert_eq(_ids(forwards), ["hunger", "village"] as Array[String])
	assert_eq(_ids(backwards), ["hunger", "village"] as Array[String])


## Trap 1, generalised: reversing the input must not move anything.
func test_the_answer_does_not_depend_on_the_order_the_topics_arrived_in():
	var topics := [
		_topic("weather", 0.4),
		_topic("hunger", 0.4),
		_topic("village", 0.9),
		_topic("shortfall", 0.1),
	]
	var reversed_topics := topics.duplicate()
	reversed_topics.reverse()
	var forwards := DialogueMove.select(topics, ledger, NPC, 100.0, 7, 4)
	var backwards := DialogueMove.select(reversed_topics, ledger, NPC, 100.0, 7, 4)
	assert_eq(_ids(forwards), _ids(backwards))
	assert_eq(_ids(forwards), ["village", "hunger", "weather", "shortfall"] as Array[String])


func test_the_same_input_always_gives_the_same_output():
	var topics := [
		_topic("weather", 0.4),
		_topic("hunger", 0.42),
		_topic("village", 0.41),
		_topic("shortfall", 0.4),
	]
	ledger.mark_told(NPC, "hunger", 60.0)
	var first := DialogueMove.select(topics, ledger, NPC, 100.0, 7, 3)
	for i in range(25):
		assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 3), first, "call %d differed" % i)


## Selecting is a READ. The conversation burns a topic when it has actually
## been said, which is a decision the window makes after rendering -- a
## select() that burned would consume every topic it merely considered, and
## the second-most-salient thing would be gone before it was ever spoken.
func test_selecting_burns_nothing_and_mutates_nothing():
	var topic := _topic("hunger", 0.8, {"facts": ["untouched"]})
	var topics := [topic]
	DialogueMove.select(topics, ledger, NPC, 100.0, 7, 3)
	assert_false(ledger.has_told(NPC, "hunger"))
	assert_eq(ledger.npc_ids(), [] as Array[String])
	assert_eq(topics.size(), 1)
	assert_eq(topic, _topic("hunger", 0.8, {"facts": ["untouched"]}))


func test_k_bounds_how_many_moves_come_back():
	var topics := [_topic("weather", 0.2), _topic("hunger", 0.9), _topic("village", 0.5)]
	var top_two := _ids(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 2))
	assert_eq(top_two, ["hunger", "village"] as Array[String])
	assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 99).size(), 3)
	assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 0), [] as Array[Dictionary])
	assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7, -1), [] as Array[Dictionary])


## One, because a Beat carries exactly one topic_id (dialogue.md's beat
## contract) -- not a tuned number.
func test_the_default_is_the_one_topic_a_beat_can_carry():
	assert_eq(DialogueMove.DEFAULT_K, 1)
	var topics := [_topic("weather", 0.2), _topic("hunger", 0.9)]
	assert_eq(DialogueMove.select(topics, ledger, NPC, 100.0, 7).size(), 1)


## Fail-open, the same shape DialogueContext uses for every absent source: a
## villager the ledger has never heard of and a missing ledger are the same
## state -- no history.
func test_a_missing_ledger_is_a_villager_with_no_history():
	var topics := [_topic("hunger", 0.9), _topic("village", 0.5)]
	var moves := DialogueMove.select(topics, null, NPC, 100.0, 7, 2)
	assert_eq(_ids(moves), ["hunger", "village"] as Array[String])
	assert_eq(moves[0]["decay"], 1.0)
	assert_false(moves[0]["repeat"])


func test_a_malformed_topic_is_skipped_rather_than_crashing_the_conversation():
	var topics := [
		{"salience": 0.9},
		{"topic_id": "", "salience": 0.9},
		{"topic_id": "hunger"},
		"not a topic at all",
		_topic("village", 0.5),
	]
	var survivors := _ids(DialogueMove.select(topics, ledger, NPC, 100.0, 7, 5))
	assert_eq(survivors, ["village"] as Array[String])


## Two rows for the same topic can only mean one thing was scored twice; the
## villager still says it once, and says it at the higher of the two scores.
func test_the_same_topic_twice_is_carried_once():
	var topics := [_topic("hunger", 0.3), _topic("hunger", 0.8)]
	var moves := DialogueMove.select(topics, ledger, NPC, 100.0, 7, 5)
	assert_eq(_ids(moves), ["hunger"] as Array[String])
	assert_almost_eq(float(moves[0]["salience"]), 0.8, 0.0001)


## The seed's whole job. The renderer picks a phrasing out of a pool indexed
## by voice_key, and it needs an index that is the same every time this
## villager raises this topic and different between two villagers saying the
## same thing -- without reaching for Godot's hash(), whose value is not a
## contract across engine versions.
func test_the_variant_is_stable_for_a_villager_and_differs_between_villagers():
	assert_eq(DialogueMove.variant_seed_for(7, "village"), DialogueMove.variant_seed_for(7, "village"))
	assert_ne(DialogueMove.variant_seed_for(7, "village"), DialogueMove.variant_seed_for(8, "village"))
	assert_ne(DialogueMove.variant_seed_for(7, "village"), DialogueMove.variant_seed_for(7, "weather"))
	assert_true(DialogueMove.variant_seed_for(7, "village") >= 0, "must be usable as an index")

	var move := DialogueMove.select_one([_topic("village", 0.5)], ledger, NPC, 100.0, 7)
	assert_eq(move["variant_seed"], DialogueMove.variant_seed_for(7, "village"))


func test_variant_for_indexes_a_pool_and_reaches_every_slot():
	var seen := {}
	for seed_value in range(400):
		var index := DialogueMove.variant_for(seed_value, "village", 4)
		assert_true(index >= 0 and index < 4, "index %d out of a 4-slot pool" % index)
		seen[index] = true
	assert_eq(seen.size(), 4, "a pool slot no villager can ever reach is a dead phrasing")
	assert_eq(DialogueMove.variant_for(7, "village", 0), 0, "an empty pool has no index to give")
	assert_eq(DialogueMove.variant_for(7, "village", -3), 0)


## The mixer's exact output, pinned. This is not a claim that these are the
## right numbers -- any well-mixed function would do -- it is a claim that
## they never CHANGE. A phrasing index is written into no save, but it is
## what makes a villager sound like themselves across sessions, and the
## reason the arithmetic is spelled out in the module instead of borrowed
## from hash() is precisely so a red here is the only way it can move.
func test_the_mixers_exact_output_is_pinned_so_it_cannot_drift():
	assert_eq(DialogueMove.variant_seed_for(0, ""), 2938590176187398597)
	assert_eq(DialogueMove.variant_seed_for(4711, "village"), 8788173117002268556)
	assert_eq(DialogueMove.variant_seed_for(4711, "hunger"), 3949483202773849951)
	assert_eq(DialogueMove.variant_seed_for(4712, "village"), 5016409883551809009)
