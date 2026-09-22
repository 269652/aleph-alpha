extends GutTest

## The spell bar stops lying, and mana gets a readout
## (docs/concept/spell_runtime.md).
##
## Measured before this: `World._build_spell_bar` filled four slots with
## locked placeholders under the comment *"A fixed row of locked
## placeholder slots for future abilities -- there is no spell/ability
## system yet ... an honest stub, not fake functionality."* There has been a
## whole spell system -- a parser, an executor, a book of twenty-four
## authored spells, a guild that teaches them -- for a long time. And
## `grep -n mana scenes/world.gd` matched only the word "manager": the one
## resource every cast spends was invisible, so *"Not enough mana"* was the
## first a player ever heard of it.
##
## Source-level for the same reason test_world_arrival_card.gd and
## test_world_hurt_flash_wiring.gd are: World is an 8500-line scene script.
## The RULES are pinned behaviourally in test_player_spell_slots.gd; what is
## pinned here is that World really draws them.

const World = preload("res://scenes/world.gd")
const PlayerScript = preload("res://scenes/player.gd")


func _function_body(name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % name)
	if start < 0:
		return ""
	var rest := source.substr(start)
	var next := rest.find("\nfunc ")
	return rest if next < 0 else rest.substr(0, next)


# -- the bar is the character's own spells ---------------------------------

func test_the_spell_bar_has_a_slot_for_every_spell_slot_the_player_has():
	assert_eq(World.SPELL_BAR_SLOT_COUNT, PlayerScript.SPELL_SLOT_COUNT)


func test_the_bar_is_filled_from_the_spells_the_character_knows():
	var body := _function_body("_update_spell_bar")
	assert_false(body.is_empty(), "there is no spell bar update at all")
	assert_true(body.contains("spell_in_slot("), "the row reads the player's own slots")


## Which one the cast key would repeat has to be visible, or choosing is a
## guess.
func test_the_bar_shows_which_spell_is_loaded():
	var body := _function_body("_update_spell_bar")
	assert_true(body.contains("selected_spell_id()"), "the selection must read")


## And it is really driven, not merely written: a builder nobody calls is
## exactly the failure this whole overhaul keeps finding.
func test_the_spell_bar_update_is_really_called():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_true(source.contains("_update_spell_bar("), "somebody has to call it")


func test_the_stub_comment_is_gone():
	var body := _function_body("_build_spell_bar")
	assert_false(
		body.contains("no spell/ability system yet"),
		"the comment outlived the thing it described"
	)


# -- and mana is on screen -------------------------------------------------

func test_mana_has_a_meter():
	var body := _function_body("_build_survival_bar")
	assert_true(body.contains("_mana_fill"), "the one resource every cast spends was invisible")


## Through the same row widget as hunger, thirst, stamina and warmth, so it
## cannot drift from them.
func test_the_mana_meter_is_the_same_widget_as_every_other_meter():
	var body := _function_body("_build_survival_bar")
	var marker := "_make_survival_meter_row(container,"
	assert_eq(body.count(marker), 5, "five meters, one widget")


func test_the_mana_meter_really_reads_the_players_mana():
	var body := _function_body("_update_survival_bar")
	assert_true(body.contains("local_player.mana"))
	assert_true(body.contains("local_player.max_mana"))


## The caption prints the key each slot answers to, because four unlabelled
## boxes answer no question a player has of them. Pinned against the real
## bindings so the printed digit and the key that works cannot disagree.
func test_the_printed_keys_are_the_keys_that_really_cast():
	const Keybindings = preload("res://src/gameplay/keybindings.gd")
	var bindings := Keybindings.new()
	for index in World.SPELL_BAR_SLOT_COUNT:
		var expected := OS.get_keycode_string(bindings.default_keycode_for("spell_%d" % (index + 1)))
		assert_eq(
			str(index + World.SPELL_SLOT_FIRST_KEY_DIGIT), expected,
			"slot %d prints a key it does not answer to" % (index + 1)
		)
