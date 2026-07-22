extends GutTest

const Keybindings = preload("res://src/gameplay/keybindings.gd")

var bindings: Keybindings


func before_each():
	bindings = Keybindings.new()


func test_exposes_the_expected_rebindable_actions():
	var names := bindings.action_names()
	for expected in ["move_up", "move_down", "move_left", "move_right",
			"attack", "block", "build", "destroy",
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
