extends GutTest

const Keybindings = preload("res://src/gameplay/keybindings.gd")

var bindings: Keybindings


func before_each():
	bindings = Keybindings.new()


func test_exposes_the_expected_rebindable_actions():
	var names := bindings.action_names()
	for expected in ["move_up", "move_down", "move_left", "move_right",
			"attack", "block", "build", "destroy", "plant",
			"hotbar_1", "hotbar_5", "toggle_inventory", "toggle_settings", "toggle_crafting",
			"pickup"]:
		assert_true(names.has(expected), "missing rebindable action %s" % expected)


func test_every_action_has_a_non_empty_label_and_a_default_keycode():
	for action in bindings.action_names():
		assert_ne(bindings.label_for(action), "", "no label for %s" % action)
		assert_gt(bindings.default_keycode_for(action), 0, "no default keycode for %s" % action)


func test_keycode_for_returns_the_default_when_not_overridden():
	assert_eq(bindings.keycode_for("attack"), bindings.default_keycode_for("attack"))


func test_set_keycode_overrides_the_default():
	bindings.set_keycode("attack", KEY_F)
	assert_eq(bindings.keycode_for("attack"), KEY_F)


func test_reset_action_restores_the_default():
	bindings.set_keycode("attack", KEY_F)
	bindings.reset_action("attack")
	assert_eq(bindings.keycode_for("attack"), bindings.default_keycode_for("attack"))


func test_reset_clears_every_override():
	bindings.set_keycode("attack", KEY_F)
	bindings.set_keycode("block", KEY_G)
	bindings.reset()
	assert_eq(bindings.keycode_for("attack"), bindings.default_keycode_for("attack"))
	assert_eq(bindings.keycode_for("block"), bindings.default_keycode_for("block"))


func test_overrides_round_trip_through_a_dictionary():
	bindings.set_keycode("attack", KEY_F)
	bindings.set_keycode("build", KEY_B)
	var saved := bindings.to_dict()

	var restored := Keybindings.new()
	restored.apply_dict(saved)
	assert_eq(restored.keycode_for("attack"), KEY_F)
	assert_eq(restored.keycode_for("build"), KEY_B)
	# Un-overridden actions keep their defaults.
	assert_eq(restored.keycode_for("block"), bindings.default_keycode_for("block"))


func test_apply_dict_ignores_unknown_actions_gracefully():
	bindings.apply_dict({"not_a_real_action": KEY_Z, "attack": KEY_F})
	assert_eq(bindings.keycode_for("attack"), KEY_F)
	assert_false(bindings.action_names().has("not_a_real_action"))


func test_keycode_for_an_unknown_action_is_zero():
	assert_eq(bindings.keycode_for("nope"), 0)


func test_is_rebindable_reports_membership():
	assert_true(bindings.is_rebindable("attack"))
	assert_false(bindings.is_rebindable("nope"))


func test_pickup_defaults_to_e_and_build_moves_off_e():
	assert_eq(bindings.default_keycode_for("pickup"), KEY_E)
	assert_ne(bindings.default_keycode_for("build"), KEY_E)


func test_ui_toggle_defaults_match_the_requested_layout():
	assert_eq(bindings.default_keycode_for("toggle_inventory"), KEY_I)
	assert_eq(bindings.default_keycode_for("toggle_crafting"), KEY_C)
	assert_eq(bindings.default_keycode_for("toggle_settings"), KEY_ESCAPE)


func test_fish_action_defaults_to_f():
	assert_eq(bindings.default_keycode_for("fish"), KEY_F)
	assert_true(bindings.action_names().has("fish"))


## "talk" needs its own key -- F/T are already fish/trade.
func test_talk_action_defaults_to_g_and_does_not_collide_with_other_defaults():
	assert_true(bindings.action_names().has("talk"))
	assert_eq(bindings.default_keycode_for("talk"), KEY_G)
	for action in bindings.action_names():
		if action == "talk":
			continue
		assert_ne(
			bindings.default_keycode_for("talk"), bindings.default_keycode_for(action),
			"talk's default collides with %s" % action
		)


## Kick (see docs/concept/stone.md) gets K -- toggle_skills moves off K onto
## L (the very next key over, an easy muscle-memory shift) to make room,
## rather than colliding two actions on the same default.
func test_kick_action_defaults_to_k_and_toggle_skills_moved_off_k():
	assert_true(bindings.action_names().has("kick"))
	assert_eq(bindings.default_keycode_for("kick"), KEY_K)
	assert_eq(bindings.default_keycode_for("toggle_skills"), KEY_L)


func test_kick_action_does_not_collide_with_any_other_default():
	for action in bindings.action_names():
		if action == "kick":
			continue
		assert_ne(
			bindings.default_keycode_for("kick"), bindings.default_keycode_for(action),
			"kick's default collides with %s" % action
		)


## See docs/concept/spell_runtime.md -- casting is a wholly new trigger, not
## routed through the hotbar/item system, so it needs its own real key.
func test_cast_action_exists_and_does_not_collide_with_any_other_default():
	assert_true(bindings.action_names().has("cast"))
	for action in bindings.action_names():
		if action == "cast":
			continue
		assert_ne(
			bindings.default_keycode_for("cast"), bindings.default_keycode_for(action),
			"cast's default collides with %s" % action
		)


## Block moves off Shift onto Ctrl to make room for sprint (see below) --
## the same "move the other one off the key rather than share" precedent
## kick/toggle_skills already set above.
func test_block_action_moved_off_shift_onto_ctrl():
	assert_eq(bindings.default_keycode_for("block"), KEY_CTRL)


## See docs/concept/input.md's "Level actions" -- sprint is a held state
## (am I sprinting right now), the same shape block/pickup/fish/lasso/mount
## already are, not a one-shot tap.
func test_sprint_action_defaults_to_shift_and_does_not_collide_with_any_other_default():
	assert_true(bindings.action_names().has("sprint"))
	assert_eq(bindings.default_keycode_for("sprint"), KEY_SHIFT)
	for action in bindings.action_names():
		if action == "sprint":
			continue
		assert_ne(
			bindings.default_keycode_for("sprint"), bindings.default_keycode_for(action),
			"sprint's default collides with %s" % action
		)


## Asked directly, with the bug in shot: *"space now toggles between plann
## mode and rpg ... bind it to P key"*.
##
## Two separate things went wrong. Space is the ATTACK key, and the mode
## toggle is a real Button in the HUD, so once it had been clicked it kept
## keyboard focus and every later Space press went to it as `ui_accept`
## instead of to the player (see World._build_view_mode_toggle, which now
## refuses focus outright). And the toggle had no key of its own at all.
func test_the_planner_toggle_has_its_own_key_and_it_is_p():
	assert_true(bindings.action_names().has("toggle_planner"))
	assert_eq(bindings.default_keycode_for("toggle_planner"), KEY_P)
	assert_ne(
		bindings.default_keycode_for("toggle_planner"), bindings.default_keycode_for("attack"),
		"the mode toggle must never be the attack key again"
	)


## P was the planting key. Moved one key over to O -- the same
## muscle-memory-shift reasoning that moved toggle_skills off K to make room
## for kick.
func test_planting_moved_one_key_over_to_make_room():
	assert_eq(bindings.default_keycode_for("plant"), KEY_O)


## The invariant the collision above was a symptom of missing: no two
## actions may share a default key at all. Pinned once here rather than as
## one more per-action collision test each time a key is added -- that is
## how a collision got in.
func test_no_two_actions_share_a_default_key():
	var by_keycode := {}
	for action in bindings.action_names():
		var keycode: int = bindings.default_keycode_for(action)
		assert_false(
			by_keycode.has(keycode),
			"%s and %s share a default key" % [by_keycode.get(keycode, ""), action]
		)
		by_keycode[keycode] = action
