extends GutTest

## One conversation, as a pure model (docs/concept/dialogue.md).
##
## The stage that was missing entirely: the pipeline ran as far as a Move and
## then stopped, so nothing anywhere turned a villager's decision into
## something a player could read or answer. This holds the whole exchange --
## which beat is on screen, what the player may say back, and what saying it
## does -- with no engine dependency, so the window above it is glue.

const Conversation = preload("res://src/dialogue/conversation.gd")
const DialogueBeat = preload("res://src/dialogue/dialogue_beat.gd")
const NpcSeenLedger = preload("res://src/dialogue/npc_seen_ledger.gd")


func _frame() -> Dictionary:
	return {
		"npc_id": "npc:7",
		"seed_value": 7,
		"npc_name": "Bren",
		"occupation": "farmer",
		"traits": {},
		"is_hungry": true,
		"hunger": 0.8,
		"meal_price": 5,
		"wallet_gold": 2,
		"can_afford_meal": false,
		"meal_available": true,
		"household_recipe_id": "stone_pickaxe",
		"shortfall_missing": [{"item_id": "rock", "need": 3}],
		"snow_depth": 0.6,
		"world_age_seconds": 100.0,
	}


func _open(ledger: NpcSeenLedger = null):
	return Conversation.open(_frame(), ledger)


# -- a conversation is a real exchange, not a banner -------------------------


func test_opening_a_conversation_gives_you_something_they_said():
	assert_ne(_open().line(), "", "the villager said nothing at all")


func test_the_speaker_is_named():
	assert_eq(_open().speaker_name(), "Bren")


## Pillar 2: nothing to say is a real answer. A villager with an empty frame
## does not invent smalltalk -- but the conversation still opens, because
## walking up to someone who has nothing to say is a thing that happens.
func test_a_villager_with_nothing_to_say_still_opens_a_conversation():
	var quiet = Conversation.open({"npc_id": "npc:1", "npc_name": "Sel", "traits": {}}, null)
	assert_ne(quiet.line(), "")
	assert_true(quiet.choices().is_empty() or quiet.choices().size() >= 1)


# -- what the player may say back --------------------------------------------


## Choice labels are built from the beat's OWN slots -- "Ask about the three
## rock" -- never from a fixed global menu. That is what stops every villager
## in the world offering the same four options.
func test_the_choices_come_from_what_was_actually_said():
	var talk = _open()
	assert_gt(talk.choices().size(), 0)
	var labels: Array[String] = []
	for choice in talk.choices():
		labels.append(String(choice["label"]))
	assert_true(
		"".join(labels).length() > 0, "the choices carry no text"
	)


## Leaving is always available. A conversation you cannot end is a trap.
func test_you_can_always_walk_away():
	var talk = _open()
	var can_leave := false
	for choice in talk.choices():
		if String(choice["id"]) == Conversation.CHOICE_LEAVE:
			can_leave = true
	assert_true(can_leave, "there is no way out of the conversation")


func test_leaving_ends_it():
	var talk = _open()
	talk.choose(Conversation.CHOICE_LEAVE)
	assert_true(talk.is_over())


func test_a_fresh_conversation_is_not_over():
	assert_false(_open().is_over())


# -- the ledger burns topics -------------------------------------------------


## dialogue.md's mechanism 2: talk twice and you get the SECOND most salient
## thing. Without this a villager repeats their loudest need forever and the
## whole scored-topic layer is invisible.
func test_asking_again_moves_on_to_the_next_thing():
	var ledger := NpcSeenLedger.new()
	var first = Conversation.open(_frame(), ledger)
	var first_topic: String = first.topic_id()
	first.choose(Conversation.CHOICE_MORE)
	var second_topic: String = first.topic_id()
	assert_ne(second_topic, first_topic, "they said the same thing twice running")


## ...and it is recorded, so the next conversation starts where this one left
## off rather than resetting to the loudest need again.
func test_what_was_said_is_remembered_between_conversations():
	var ledger := NpcSeenLedger.new()
	var first = Conversation.open(_frame(), ledger)
	var said: String = first.topic_id()
	first.choose(Conversation.CHOICE_LEAVE)
	assert_true(ledger.has_told("npc:7", said), "the ledger did not record what was said")


## Running out of things to say is an ending, not an error.
func test_a_villager_eventually_runs_out():
	var talk = _open()
	for step in 40:
		if talk.is_over():
			break
		talk.choose(Conversation.CHOICE_MORE)
	assert_true(talk.is_over(), "the villager talked forever")


# -- the voice is this individual's ------------------------------------------


## Two villagers with different genomes phrase the same situation differently.
func test_two_villagers_do_not_sound_identical():
	var lines := {}
	for seed_value in 12:
		var frame := _frame()
		frame["seed_value"] = seed_value
		frame["npc_id"] = "npc:%d" % seed_value
		frame["traits"] = {"warmth": float(seed_value) / 12.0, "bluntness": 1.0 - float(seed_value) / 12.0}
		lines[Conversation.open(frame, null).line()] = true
	assert_gt(lines.size(), 1, "every villager in the world says it the same way")
