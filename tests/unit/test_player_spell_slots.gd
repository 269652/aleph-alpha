extends GutTest

## A spell you chose (docs/concept/spell_runtime.md).
##
## Measured before this: `Player.cast_spell(spell_id)` accepted any known id
## and had exactly ONE caller, which passed `DEFAULT_CAST_SPELL_ID`. So the
## cast key cast Fire Bolt for ever and twenty-three authored spells were
## unreachable except by weaving one from scratch -- while
## `World._build_spell_bar` filled four slots with locked placeholders under
## the comment *"there is no spell/ability system yet"*, which had been
## false for a long time.

const PlayerScene = preload("res://scenes/player.tscn")
const SpellTuition = preload("res://src/gameplay/spell_tuition.gd")
const Keybindings = preload("res://src/gameplay/keybindings.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")

var player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)
	# A bare player scene has max_mana 0 -- it is set from the character's
	# own stats (apply_stats, from the class/DNA roll), which no unit test
	# builds. Give this one a pool so "can it cast" is about the spell.
	player.max_mana = 50.0
	player.mana = player.max_mana


func after_each():
	player.queue_free()


# -- the slots are the spells you really know -----------------------------

func test_a_new_character_has_their_starting_spell_in_the_first_slot():
	assert_eq(player.spell_in_slot(0), SpellTuition.STARTING_SPELL_IDS[0])


## The row is a VIEW of what the character knows, not a second list that
## could drift from it: learning a spell fills the next slot with no
## bookkeeping of its own.
func test_the_slots_are_the_known_spells_in_order():
	for index in player.spell_slot_count():
		var known: Array = player.known_spell_ids()
		if index < known.size():
			assert_eq(player.spell_in_slot(index), String(known[index]))
		else:
			assert_eq(player.spell_in_slot(index), "", "an unlearned slot is empty")


func test_a_slot_nobody_could_reach_is_empty_rather_than_a_crash():
	assert_eq(player.spell_in_slot(-1), "")
	assert_eq(player.spell_in_slot(9999), "")


# -- choosing, and casting ------------------------------------------------

## The selection starts on what the character actually knows rather than on
## a hardcoded id, which is the whole bug: DEFAULT_CAST_SPELL_ID was the
## only spell the cast key ever reached.
func test_the_selection_starts_on_the_first_spell_you_know():
	assert_eq(player.selected_spell_id(), String(player.known_spell_ids()[0]))


func test_pressing_a_slot_casts_that_spell_and_selects_it():
	# The slot it lands in is DERIVED, not assumed to be 1. These two tests
	# hardcoded index 1 back when the starting hand held a single spell, and
	# went red the day it learned to teach more than one delivery
	# (docs/concept/magic.md) -- for a reason with nothing to do with slots.
	var slot := _slot_of_a_newly_learned("frost_lance")
	assert_eq(player.spell_in_slot(slot), "frost_lance", "precondition: it reached the row")
	assert_true(player.cast_spell_slot(slot), "the key really casts")
	assert_eq(player.selected_spell_id(), "frost_lance", "and it stays loaded")


## And the cast key then repeats that choice -- the deliberate act and the
## quick one are the same act.
func test_the_cast_key_repeats_the_selection():
	player.cast_spell_slot(_slot_of_a_newly_learned("frost_lance"))
	var before: float = player.mana
	player.mana = player.max_mana
	assert_true(player.cast_held())
	assert_lt(player.mana, player.max_mana, "it really cast something")
	assert_eq(player.selected_spell_id(), "frost_lance")


## An empty slot says why rather than doing nothing, the same rule every
## other verb in this overhaul follows.
func test_an_empty_slot_refuses_out_loud():
	var seen: Array = []
	player.answered.connect(func(feedback): seen.append(feedback))
	assert_false(player.cast_spell_slot(player.spell_slot_count() - 1))
	assert_eq(seen.size(), 1, "a press that could do nothing still answers")
	assert_true(bool(seen[0]["failed"]))
	assert_ne(String(seen[0]["message"]), "")


## The Weave still wins when there is one: a character who has arranged
## atoms meant to cast THAT (docs/concept/spell_weaving.md). The selection
## is what the key falls back to.
func test_a_woven_draft_still_outranks_the_selection():
	var body := _function_body("cast_held")
	assert_false(body.is_empty(), "precondition: cast_held was found")
	assert_true(body.contains("cast_woven"), "the draft is still tried first")
	assert_true(
		body.contains("return cast_spell(selected_spell_id())"),
		"and the fallback is the chosen one"
	)
	assert_false(
		body.contains("cast_spell(DEFAULT_CAST_SPELL_ID)"),
		"the fallback is the chosen spell now, not one hardcoded id"
	)


## The function's own body, not a fixed window of characters -- and the
## assertions above match the CALL rather than the identifier. A first draft
## read 400 characters from the declaration and tripped over a doc comment
## further down that names the very constant it was asserting the absence
## of, which is the second time this suite has taught that lesson.
func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


# -- the keys -------------------------------------------------------------

func test_every_spell_slot_has_a_key_of_its_own():
	var bound: Array = Keybindings.new().action_names()
	for index in player.spell_slot_count():
		assert_true(bound.has("spell_%d" % (index + 1)), "slot %d has no key" % (index + 1))


func test_every_spell_key_answers():
	for index in player.spell_slot_count():
		assert_true(Answerback.has_feedback("spell_%d" % (index + 1)))


## Teaches `spell_id` and says which slot of the bar it landed in. The row
## is the Nth entry of known_spell_ids(), so a spell just appended sits at
## the end of it -- asked rather than assumed, so widening the starting hand
## again cannot make these tests lie.
func _slot_of_a_newly_learned(spell_id: String) -> int:
	player._known_spell_ids.append(spell_id)
	return player.known_spell_ids().size() - 1
