extends GutTest

## ConversationWindow (scenes/conversation_window.gd) -- the player-facing
## surface docs/concept/dialogue.md's own Status section names as the last
## unbuilt piece, opening on the existing "talk" key. Same "toggle window,
## built entirely in code, tested post-hoc via a constructed tree" pattern
## InventoryWindow/CraftingWindow/QuestLogWindow already use (see this
## session's own established convention -- construction code is not
## red-first, but every behavior it drives is covered immediately after).
##
## This window never calls into DialogueContext/DialogueTopic/DialogueMove/
## DialogueBeat itself -- World hands it an already-built greeting and a
## fixed list of Beats, and the window's only pipeline dependency is
## OfflineRenderer (wording is the window's own job per dialogue.md's "pure
## core, thin glue"). Tests below build real Beats via DialogueBeat.build
## rather than hand-fabricated Dictionaries, so a shape drift in the real
## contract fails here too.

const ConversationWindow = preload("res://scenes/conversation_window.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const DialogueTopic = preload("res://src/dialogue/dialogue_topic.gd")
const DialogueMove = preload("res://src/dialogue/dialogue_move.gd")
const NpcVoice = preload("res://src/dialogue/npc_voice.gd")
const OfflineRenderer = preload("res://src/dialogue/offline_renderer.gd")

var window: ConversationWindow


func before_each():
	window = ConversationWindow.new()
	add_child(window)


func after_each():
	window.free()


func _frame() -> Dictionary:
	return {"npc_name": "Bren", "occupation": "potter"}


func _beat_for(topic_id: String, facts: Dictionary, seed_value: int = 1) -> Dictionary:
	var topic := {"topic_id": topic_id, "salience": 0.8, "facts": facts}
	var move := DialogueMove.select_one([topic], null, "npc:1", 0.0, seed_value)
	return DialogueBeat.build(move, _frame(), NpcVoice.register_for({}))


func _weather_beat(seed_value: int = 1) -> Dictionary:
	return _beat_for(DialogueTopic.TOPIC_WEATHER, {"season": "winter", "weather": "snow", "snow_depth": 0.1}, seed_value)


func _household_ask_beat() -> Dictionary:
	return _beat_for(DialogueTopic.TOPIC_HOUSEHOLD_ASK, {
		"recipe_id": "r", "missing": [{"item_id": "rock", "need": 3}],
		"units_short": 3, "recipe_units": 5, "items_player_has": [], "covered_by_player": false,
	}, 2)


func _deflect_beat() -> Dictionary:
	return DialogueBeat.build({}, _frame(), NpcVoice.register_for({}))


func _buttons() -> Array:
	var found: Array = []
	for child in window.find_children("*", "Button", true, false):
		found.append(child)
	return found


func test_starts_closed():
	assert_false(window.is_open())
	assert_false(window.visible)


func test_toggle_flips_visibility():
	window.toggle()
	assert_true(window.is_open())
	window.toggle()
	assert_false(window.is_open())


func test_open_for_shows_the_window_and_the_speakers_name_and_greeting():
	window.open_for("npc:1", "Bren the Potter", "Bren nods hello.", [])
	assert_true(window.is_open())
	assert_string_contains(_all_text(), "Bren the Potter")
	assert_string_contains(_all_text(), "Bren nods hello.")


func test_open_for_builds_one_button_per_real_beat():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat(), _household_ask_beat()])
	assert_eq(_buttons().size(), 3, "2 topics + Farewell")


func test_button_labels_come_from_offline_renderers_own_choice_labels():
	var beat := _household_ask_beat()
	window.open_for("npc:1", "Bren", "Hello.", [beat])
	assert_eq(_buttons()[0].text, OfflineRenderer.choice_label_for(beat))


func test_a_deflect_beat_is_shown_as_the_response_not_a_button():
	window.open_for("npc:1", "Bren", "Hello.", [_deflect_beat()])
	assert_eq(_buttons().size(), 1, "no topic button -- just Farewell")
	assert_string_contains(_all_text(), OfflineRenderer.render(_deflect_beat()))


func test_no_topics_at_all_shows_an_honest_empty_message_not_a_blank_list():
	window.open_for("npc:1", "Bren", "Hello.", [])
	assert_eq(_buttons().size(), 1, "no topic button -- just Farewell")
	assert_ne(_all_text().strip_edges(), "Bren\nHello.", "an empty topic list should still say something about itself")


func test_clicking_a_topic_button_renders_its_offline_text_as_the_response():
	var beat := _weather_beat()
	window.open_for("npc:1", "Bren", "Hello.", [beat])
	_buttons()[0].pressed.emit()
	assert_string_contains(_all_text(), OfflineRenderer.render(beat))


func test_clicking_a_topic_button_emits_topic_chosen_with_the_real_topic_id():
	watch_signals(window)
	var beat := _weather_beat()
	window.open_for("npc:1", "Bren", "Hello.", [beat])
	_buttons()[0].pressed.emit()
	assert_signal_emitted_with_parameters(window, "topic_chosen", [DialogueTopic.TOPIC_WEATHER])


func test_clicking_a_topic_button_removes_it_so_it_cannot_be_asked_twice():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat(), _household_ask_beat()])
	assert_eq(_buttons().size(), 3, "2 topics + Farewell")
	_buttons()[0].pressed.emit()
	assert_eq(_buttons().size(), 2, "1 topic + Farewell")


func test_farewell_closes_the_window():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()])
	var farewell := _find_button_with_text("Farewell")
	assert_not_null(farewell, "precondition: a Farewell button must exist")
	farewell.pressed.emit()
	assert_false(window.is_open())


func test_opening_a_new_conversation_replaces_the_previous_ones_topics():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()])
	assert_eq(_buttons().size(), 2, "1 topic + Farewell")
	window.open_for("npc:2", "Lira", "Hi there.", [_weather_beat(3), _household_ask_beat()])
	assert_eq(_buttons().size(), 3, "2 topics + Farewell")


func _find_button_with_text(text: String) -> Node:
	for button in _buttons():
		if button.text == text:
			return button
	return null


func _all_text() -> String:
	var text := ""
	for label in window.find_children("*", "Label", true, false):
		text += label.text + "\n"
	return text


# -- the give verb, at the villager's door -------------------------------
#
# docs/concept/errands.md: the villager already says "I could use three
# more rock" through the household_ask beat; the button that hands them
# over belongs in the same window the saying happens in. An unavailable
# offer is shown as a named reason rather than hidden, so a player
# carrying the wrong thing learns what the right thing is.

const ErrandDelivery = preload("res://src/gameplay/errand_delivery.gd")


func _give_offer(carried: Dictionary) -> Dictionary:
	return ErrandDelivery.offer_from_frame({
		"npc_name": "Bren",
		"household_id": "household:7",
		"settlement_id": "settlement:1_2",
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"player_carrying": carried,
	})


func _give_buttons() -> Array:
	var found: Array = []
	for child in window._topics_container.get_children():
		if child is Button and String(child.text).begins_with("Give"):
			found.append(child)
	return found


func test_no_offer_means_no_give_button():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()], {})
	assert_eq(_give_buttons().size(), 0)


func test_an_offer_the_player_can_meet_shows_a_give_button_naming_the_goods():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()], _give_offer({"rock": 5}))
	var buttons := _give_buttons()
	assert_eq(buttons.size(), 1, "exactly one give button")
	assert_true(String(buttons[0].text).contains("3"), buttons[0].text)
	assert_false(buttons[0].disabled, "the player is carrying the goods")


func test_an_offer_the_player_cannot_meet_is_shown_disabled_with_its_reason():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()], _give_offer({"wood": 9}))
	var buttons := _give_buttons()
	assert_eq(buttons.size(), 0, "there is nothing to give, so no give button")
	var reasons: Array = []
	for child in window._topics_container.get_children():
		if child is Label and String(child.text).contains("rock"):
			reasons.append(child)
	assert_eq(reasons.size(), 1, "the refusal is a sentence naming what is needed, not a dead button")


func test_pressing_give_emits_the_offer_it_was_built_from():
	var offer := _give_offer({"rock": 5})
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()], offer)
	var emitted: Array = []
	window.give_requested.connect(func(o): emitted.append(o))
	_give_buttons()[0].emit_signal("pressed")
	assert_eq(emitted.size(), 1, "one press, one request")
	assert_eq(emitted[0]["given"], [{"item_id": "rock", "count": 3}])
	assert_eq(emitted[0]["household_id"], "household:7")


func test_the_give_button_survives_a_topic_being_chosen():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat(), _household_ask_beat()], _give_offer({"rock": 5}))
	assert_eq(_give_buttons().size(), 1, "precondition")
	for child in window._topics_container.get_children():
		if child is Button and not String(child.text).begins_with("Give"):
			child.emit_signal("pressed")
			break
	assert_eq(_give_buttons().size(), 1, "asking about the weather does not withdraw the offer")


func test_giving_withdraws_the_offer_so_it_cannot_be_pressed_twice():
	window.open_for("npc:1", "Bren", "Hello.", [_weather_beat()], _give_offer({"rock": 5}))
	var emitted: Array = []
	window.give_requested.connect(func(o): emitted.append(o))
	_give_buttons()[0].emit_signal("pressed")
	assert_eq(_give_buttons().size(), 0, "the goods are gone; the button goes with them")
	assert_eq(emitted.size(), 1)
