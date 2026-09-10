extends GutTest

## DialogueBeat (src/dialogue/dialogue_beat.gd) -- the pipeline's fifth stage
## (docs/concept/dialogue.md): packages one DialogueMove.select_one output
## into the one contract OfflineRenderer alone knows how to turn into words
## (the "beat contract"). Pure: Dictionaries in, one Dictionary out.
##
## Two fields ride on the beat beyond the doc's own literal list, both
## documented in dialogue_beat.gd itself: `variant_seed` (carried from the
## Move that produced this beat -- OfflineRenderer's deterministic phrasing-
## pool index, the same DialogueMove.variant_seed_for reused rather than
## re-derived) and `repeat` (also carried from the Move -- "an opener that
## acknowledges the first", dialogue.md's own named mechanism #2).

const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const NpcVoice = preload("res://src/dialogue/npc_voice.gd")


func _frame(overrides: Dictionary = {}) -> Dictionary:
	var frame := {"npc_name": "Bren", "occupation": "potter"}
	for key in overrides:
		frame[key] = overrides[key]
	return frame


func _move_for_topic(topic_id: String, facts: Dictionary, seed_value: int = 42) -> Dictionary:
	var topic := {"topic_id": topic_id, "salience": 0.8, "facts": facts}
	return DialogueMove.select_one([topic], null, "npc:1", 0.0, seed_value)


func test_every_documented_field_is_present_on_a_real_beat():
	var move := _move_for_topic(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "stone_pickaxe", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	for field in DialogueBeat.BEAT_FIELDS:
		assert_true(beat.has(field), "beat is missing documented field '%s'" % field)


func test_an_empty_move_produces_a_deflect_beat_not_an_error():
	var beat := DialogueBeat.build({}, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["kind"], DialogueBeat.KIND_DEFLECT)
	assert_eq(beat["topic_id"], "")
	assert_true(beat["facts"].is_empty())


func test_household_ask_is_the_ask_kind_everything_else_is_answer():
	var ask_move := _move_for_topic(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var ask_beat := DialogueBeat.build(ask_move, _frame(), NpcVoice.register_for({}))
	assert_eq(ask_beat["kind"], DialogueBeat.KIND_ASK)

	var weather_move := _move_for_topic(DialogueTopic.TOPIC_WEATHER, {
		"season": "winter", "weather": "snow", "snow_depth": 0.1,
	})
	var weather_beat := DialogueBeat.build(weather_move, _frame(), NpcVoice.register_for({}))
	assert_eq(weather_beat["kind"], DialogueBeat.KIND_ANSWER)


func test_household_ask_slots_carry_the_first_missing_item_and_its_count():
	var move := _move_for_topic(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}, {"item_id": "wood", "need": 1}],
		"units_short": 4, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["slots"]["item"], "rock")
	assert_eq(beat["slots"]["count"], 3)


func test_neighbour_slots_carry_the_neighbours_name():
	var move := _move_for_topic(DialogueTopic.TOPIC_NEIGHBOUR, {
		"npc_id": "npc:9", "name": "Lira", "occupation": "farmer",
		"memories": [], "top_memory": {}, "strength": 0.6,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["slots"]["name"], "Lira")
	assert_true(beat["speaker"]["allowed_names"].has("Lira"))


func test_speaker_carries_the_frames_own_name_occupation_and_recognition():
	var move := _move_for_topic(DialogueTopic.TOPIC_WEATHER, {
		"season": "winter", "weather": "snow", "snow_depth": 0.1,
	})
	var beat := DialogueBeat.build(
		move, _frame(), NpcVoice.register_for({}), {"tier": "owed"}
	)
	assert_eq(beat["speaker"]["name"], "Bren")
	assert_eq(beat["speaker"]["occupation"], "potter")
	assert_eq(beat["speaker"]["recognition"], "owed")
	assert_true(beat["speaker"]["allowed_names"].has("Bren"))


func test_missing_recognition_reads_as_a_stranger_rather_than_erroring():
	var beat := DialogueBeat.build({}, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["speaker"]["recognition"], "stranger")


func test_voice_key_is_carried_straight_from_the_voice_register():
	var register := NpcVoice.register_for({"gruff": 1.0, "bold": 1.0, "cautious": 0.0, "friendly": 0.0})
	var move := _move_for_topic(DialogueTopic.TOPIC_WEATHER, {
		"season": "winter", "weather": "snow", "snow_depth": 0.1,
	})
	var beat := DialogueBeat.build(move, _frame(), register)
	assert_eq(beat["voice_key"], register["voice_key"])


func test_fact_band_names_the_real_village_status_directly():
	var move := _move_for_topic(DialogueTopic.TOPIC_VILLAGE_STATUS, {
		"status": "declining", "household_count": 5, "capacity": 2, "food_stock": 0,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["fact_band"], "status:declining")


func test_fact_band_bands_hunger_by_the_pinned_thresholds():
	var severe := _move_for_topic(DialogueTopic.TOPIC_HUNGER, {
		"hunger": 0.9, "meal_price": 5, "wallet_gold": 0, "can_afford_meal": false, "meal_available": true,
	})
	var beat := DialogueBeat.build(severe, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["fact_band"], "hunger:severe")

	var moderate := _move_for_topic(DialogueTopic.TOPIC_HUNGER, {
		"hunger": 0.5, "meal_price": 5, "wallet_gold": 0, "can_afford_meal": false, "meal_available": true,
	})
	beat = DialogueBeat.build(moderate, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["fact_band"], "hunger:moderate")


func test_variant_seed_and_repeat_are_carried_from_the_move():
	var topic := {
		"topic_id": DialogueTopic.TOPIC_WEATHER, "salience": 0.8,
		"facts": {"season": "winter", "weather": "snow", "snow_depth": 0.1},
	}
	var ledger = load("res://src/dialogue/npc_seen_ledger.gd").new()
	ledger.mark_told("npc:1", DialogueTopic.TOPIC_WEATHER, 0.0)
	var move := DialogueMove.select_one([topic], ledger, "npc:1", 500.0, 42)

	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["variant_seed"], move["variant_seed"])
	assert_true(beat["repeat"])


func test_a_fresh_topic_never_told_before_is_not_a_repeat():
	var move := _move_for_topic(DialogueTopic.TOPIC_WEATHER, {
		"season": "winter", "weather": "snow", "snow_depth": 0.1,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_false(beat["repeat"])


func test_required_slots_lists_only_the_slots_that_are_actually_filled():
	var move := _move_for_topic(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_true(beat["required_slots"].has("item"))
	assert_true(beat["required_slots"].has("count"))
	assert_false(beat["required_slots"].has("name"), "no neighbour name is available on this topic")


func test_template_and_offline_text_are_left_for_the_next_pipeline_stage():
	var move := _move_for_topic(DialogueTopic.TOPIC_WEATHER, {
		"season": "winter", "weather": "snow", "snow_depth": 0.1,
	})
	var beat := DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))
	assert_eq(beat["template"], "", "wording is OfflineRenderer's job, not DialogueBeat's")
	assert_eq(beat["offline_text"], "")
