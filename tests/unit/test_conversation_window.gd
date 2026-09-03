extends GutTest

## The window, as glue (docs/concept/dialogue.md).
##
## Every decision belongs to Conversation and the pure pipeline under it; this
## pins that the window renders what they decide and reports back, and in
## particular that it can always be closed -- a conversation the player cannot
## leave is a soft lock with a face on it.

const ConversationWindow = preload("res://scenes/conversation_window.gd")
const Conversation = preload("res://src/dialogue/conversation.gd")

var window: ConversationWindow


func before_each():
	window = ConversationWindow.new()
	add_child(window)


func after_each():
	remove_child(window)
	window.free()


func _talk():
	return Conversation.open({
		"npc_id": "npc:7",
		"seed_value": 7,
		"npc_name": "Bren",
		"traits": {},
		"is_hungry": true,
		"hunger": 0.8,
		"meal_price": 5,
		"wallet_gold": 2,
		"can_afford_meal": false,
		"meal_available": true,
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"household_recipe_id": "stone_pickaxe",
	}, null)


func test_a_fresh_window_is_closed():
	assert_false(window.is_open())


func test_opening_shows_it():
	window.open_with(_talk())
	assert_true(window.is_open())


func test_closing_hides_it():
	window.open_with(_talk())
	window.close()
	assert_false(window.is_open())


## World hands keyboard control back on this, so it has to actually fire.
func test_closing_announces_itself():
	window.open_with(_talk())
	var heard := [false]
	window.closed.connect(func(): heard[0] = true)
	window.close()
	assert_true(heard[0], "nothing was told the conversation ended")


## The window shows what the villager said -- it does not compose a line of
## its own.
func test_it_shows_what_the_villager_said():
	var talk = _talk()
	window.open_with(talk)
	assert_eq(window._line_label.text, talk.line())
	assert_eq(window._speaker_label.text, talk.speaker_name())


## ...and the choices it offers are the conversation's, not a fixed menu.
func test_the_buttons_are_the_conversations_own_choices():
	var talk = _talk()
	window.open_with(talk)
	assert_eq(window._choices.get_child_count(), talk.choices().size())


## There is always a way out, in every state the window can be in -- including
## after the villager has run out of things to say.
func test_there_is_always_a_button():
	var talk = _talk()
	window.open_with(talk)
	for step in 40:
		assert_gt(window._choices.get_child_count(), 0, "the window offered no way forward")
		if talk.is_over():
			break
		window._on_choice(Conversation.CHOICE_MORE)
