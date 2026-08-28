extends GutTest

## On-screen prompts must name the KEY, not the action.
##
## Reported live: the lasso banner read "Lasso ready — press the lasso key near
## an animal." There is no key called "the lasso key". The player has to go and
## look it up in the settings screen to use the verb the game is, at that
## moment, telling them to use.
##
## The hover tooltip already gets this right -- World._hover_tooltip_text
## renders "Chop (Space)" from `OS.get_keycode_string(keycode_for(action))`, so
## a rebind shows immediately. The banner simply never used that machinery.
##
## `Keybindings.display_key_for` reads the LIVE InputMap rather than a
## Keybindings instance on purpose: World._apply_keybindings writes each
## resolved keycode (overrides included) into InputMap, so InputMap is the one
## source of truth that every caller can reach -- Player holds no Keybindings
## of its own, and a fresh one would not know the player's rebinds.

const Keybindings = preload("res://src/gameplay/keybindings.gd")

const TEST_ACTION := "test_prompt_action"


func after_each():
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)


func _bind(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func test_the_display_key_is_the_bound_key():
	_bind(TEST_ACTION, KEY_R)
	assert_eq(Keybindings.display_key_for(TEST_ACTION), OS.get_keycode_string(KEY_R))


## The whole reason this reads InputMap: a rebound action must show its NEW key
## the moment it is rebound, exactly as the hover tooltip already does.
func test_rebinding_changes_what_the_prompt_says():
	_bind(TEST_ACTION, KEY_R)
	var before := Keybindings.display_key_for(TEST_ACTION)
	_bind(TEST_ACTION, KEY_J)
	assert_ne(Keybindings.display_key_for(TEST_ACTION), before)
	assert_eq(Keybindings.display_key_for(TEST_ACTION), OS.get_keycode_string(KEY_J))


## Keys with no printable character still have to read as something a player
## can find on their keyboard -- a blank here would be worse than the bug this
## fixes, since the prompt would name nothing at all.
func test_keys_with_no_printable_character_still_name_themselves():
	for keycode in [KEY_SPACE, KEY_SHIFT, KEY_ESCAPE, KEY_QUOTELEFT]:
		_bind(TEST_ACTION, keycode)
		assert_ne(Keybindings.display_key_for(TEST_ACTION), "", "keycode %d named nothing" % keycode)


## An action the InputMap has never heard of is a real case: a Player stepped in
## isolation runs before World registers the map (see Player._unhandled_input's
## own has_action guard). It must return empty rather than erroring, so a prompt
## degrades to no key rather than to a crash.
func test_an_unregistered_action_names_no_key():
	assert_eq(Keybindings.display_key_for("not_a_real_action"), "")


## Every rebindable action must be able to name itself, or some prompt
## somewhere is destined to read "press the something key" again.
func test_every_rebindable_action_can_name_its_key():
	var bindings := Keybindings.new()
	# World._apply_keybindings does this at runtime; a test driving the helper
	# without a World has to stand in for it.
	for action in bindings.action_names():
		_bind(action, bindings.keycode_for(action))
	for action in bindings.action_names():
		assert_ne(
			Keybindings.display_key_for(action), "",
			"%s cannot name its own key" % action
		)


# -- the lasso banner actually uses it ----------------------------------------

## Pinned from source: Player builds this string itself, and the failure mode is
## a hard-coded phrase rather than a wrong value, which no runtime assertion on
## the string's content would catch as clearly.
func _lasso_message_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func _update_lasso_message(")
	assert_gt(start, -1, "Player._update_lasso_message should exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


func test_the_lasso_prompt_names_its_key_rather_than_calling_it_the_lasso_key():
	var body := _lasso_message_body()
	assert_false(
		body.contains("the lasso key"),
		"the prompt should name the bound key, not the phrase 'the lasso key'"
	)
	assert_string_contains(body, "display_key_for")


# -- the slots sit where the taming verbs already were -----------------------
#
# Reported: "R (primary) ... X (secondary)". R was the rope key, which is the
# right home for the primary slot precisely because it is the key a player's
# hand already goes to at an animal -- and the slot subsumes what it used to
# do, since Lasso/Release/Order are all scored candidates now. The dedicated
# rope binding moves aside rather than being deleted, so anyone who wants the
# old single-purpose key can still rebind to it.

func test_the_primary_slot_is_on_the_key_the_rope_verb_used_to_hold():
	var bindings := Keybindings.new()
	assert_eq(bindings.default_keycode_for("primary_action"), KEY_R)
	assert_eq(bindings.default_keycode_for("secondary_action"), KEY_X)


## The important half: nothing may share a default with the slots, or one press
## would fire two verbs -- which is exactly what would have happened if the
## rope key had stayed on R alongside the primary slot.
func test_no_action_shares_a_default_key_with_a_slot():
	var bindings := Keybindings.new()
	var seen := {}
	for entry in Keybindings.ACTIONS:
		var key: int = entry["default"]
		assert_false(
			seen.has(key),
			"%s and %s share a default key" % [seen.get(key, ""), entry["action"]]
		)
		seen[key] = entry["action"]
