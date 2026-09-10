extends GutTest

## QuestLogWindow: the player-facing surface for the real, live production-
## shortfall quest system (toggle U) -- see this window's own doc comment
## for the reported gap (QuestLog.reconcile already ran every frame, but
## nothing ever called accept/abandon and there was no UI at all). This
## file covers layout/interaction glue, the same class of bug
## test_crafting_window.gd/test_inventory_window.gd pin for their windows --
## the underlying quest logic itself is Quest/QuestLog's own, covered by
## test_quest.gd/test_quest_log.gd.

const QuestLogWindow = preload("res://scenes/quest_log_window.gd")
const QuestLog = preload("res://src/emergence/quest_log.gd")

var window: QuestLogWindow


func before_each():
	window = QuestLogWindow.new()
	add_child(window)


func after_each():
	window.free()


func _quest(household_id: String, occupation: String, recipe_id: String, missing: Array) -> Dictionary:
	return {
		"settlement_id": "settlement:0_0",
		"household_id": household_id,
		"occupation": occupation,
		"recipe_id": recipe_id,
		"missing": missing,
	}


## Depth-first search for the first Button under `node` -- the exact card
## structure (PanelContainer > HBoxContainer > [text, Button]) is an
## implementation detail this test shouldn't have to hardcode.
func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _first_button(child)
		if found != null:
			return found
	return null


func test_starts_hidden():
	assert_false(window.visible)


func test_toggle_flips_visibility():
	window.toggle()
	assert_true(window.is_open())
	window.toggle()
	assert_false(window.is_open())


func test_refresh_shows_an_available_quest_with_the_occupation_and_missing_items():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	window.refresh([quest], [])

	var found_who := false
	var found_need := false
	for card in window._available_container.get_children():
		for label in card.find_children("*", "Label", true, false):
			if "Blacksmith" in label.text:
				found_who = true
			if "3" in label.text and "Rock" in label.text:
				found_need = true
	assert_true(found_who, "must show the household's own occupation, not a raw id")
	assert_true(found_need, "must show the specific missing item and amount")


func test_an_available_quest_already_accepted_does_not_appear_twice():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	var offer_id := QuestLog.offer_id_for(quest)
	window.refresh([quest], [offer_id])

	assert_eq(window._available_container.get_child_count(), 1, "the premise: an empty-state label still counts as one child")
	assert_true(
		(window._available_container.get_child(0) as Label).text.contains("Nothing"),
		"an accepted quest must move to the Accepted section, not linger in Available too"
	)
	assert_eq(window._accepted_container.get_child_count(), 1)


func test_accepting_a_quest_emits_the_real_offer_id():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	window.refresh([quest], [])
	watch_signals(window)

	var card: Control = window._available_container.get_child(0)
	_first_button(card).pressed.emit()

	assert_signal_emitted_with_parameters(window, "accept_requested", [QuestLog.offer_id_for(quest)])


func test_abandoning_a_quest_emits_the_real_offer_id():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	var offer_id := QuestLog.offer_id_for(quest)
	window.refresh([quest], [offer_id])
	watch_signals(window)

	var card: Control = window._accepted_container.get_child(0)
	_first_button(card).pressed.emit()

	assert_signal_emitted_with_parameters(window, "abandon_requested", [offer_id])


func test_accepted_button_reads_abandon_available_button_reads_accept():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	var offer_id := QuestLog.offer_id_for(quest)
	window.refresh([quest], [offer_id])

	var accepted_card: Control = window._accepted_container.get_child(0)
	assert_eq(_first_button(accepted_card).text, "Abandon")

	window.refresh([quest], [])
	var available_card: Control = window._available_container.get_child(0)
	assert_eq(_first_button(available_card).text, "Accept")


func test_empty_available_section_shows_a_real_message_not_a_blank_list():
	window.refresh([], [])
	assert_eq(window._available_container.get_child_count(), 1)
	assert_true((window._available_container.get_child(0) as Label).text.length() > 0)


func test_empty_accepted_section_shows_a_real_message_not_a_blank_list():
	window.refresh([], [])
	assert_eq(window._accepted_container.get_child_count(), 1)
	assert_true((window._accepted_container.get_child(0) as Label).text.length() > 0)


## An accepted quest whose household no longer appears in the live
## projection (settlement out of range, or the shortage resolved a frame
## before this exact refresh) must still show something real, not vanish --
## the player still needs a way to see/abandon it.
func test_an_accepted_quest_missing_from_the_live_list_still_shows_something_real():
	var offer_id := "production:household:7:iron_sword"
	window.refresh([], [offer_id])

	assert_eq(window._accepted_container.get_child_count(), 1)
	var card: Control = window._accepted_container.get_child(0)
	assert_not_null(_first_button(card), "must still offer a real Abandon button")
	assert_eq(_first_button(card).text, "Abandon")


func test_refresh_is_a_no_op_when_nothing_relevant_changed():
	var quest := _quest("household:1", "blacksmith", "stone_pickaxe", [{"item_id": "rock", "need": 3}])
	window.refresh([quest], [])
	var first_card: Control = window._available_container.get_child(0)

	window.refresh([quest], [])  # identical inputs

	assert_same(
		window._available_container.get_child(0), first_card,
		"an identical refresh must not tear down and rebuild the same cards"
	)
