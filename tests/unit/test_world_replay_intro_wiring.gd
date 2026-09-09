extends GutTest

## Replaying the boot intro splash on demand (see docs/concept/
## intro_splash.md's "Replaying the intro on demand") -- asked directly: a
## way to watch it again, either from the main menu or a console command.
## Two independent triggers, both calling the exact same, unmodified
## World._play_intro_splash() the two existing AUTOMATIC triggers already
## use (boot, New Game/Host Game -- see test_world_intro_splash_after_
## load_fanout.gd) -- purely additive, touches neither existing call site
## nor _play_intro_splash()'s own shape at all.
##
## Pinned from source text rather than by driving a real World node (needs
## a full chunk manager/multiplayer/MainMenu -- see test_earth_chunk_
## manager.gd's own runtime), the same shape test_mushroom_command_
## clarity.gd (console commands) and test_world_footstep_wiring.gd/
## test_world_intro_splash_after_load_fanout.gd (World's own internal
## wiring) already use for exactly this reason.

const World = preload("res://scenes/world.gd")


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


## The body of one named function, read straight from source -- mirrors
## test_world_intro_splash_after_load_fanout.gd's own identical helper.
func _function_body(function_name: String) -> String:
	var source := _source()
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "World.%s should still exist" % function_name)
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


# -- the main-menu button: MainMenu.replay_intro_requested ------------------
#
# MainMenu has no idea what IntroSplash even is (only World preloads it and
# owns _ui, the CanvasLayer _play_intro_splash() needs) -- it only emits a
# signal, the same "emit and let World answer" shape load_requested/
# join_requested already use (see _on_menu_load_requested/
# _on_menu_join_requested's own identical one-line bodies).

func test_show_main_menu_connects_replay_intro_requested():
	var body := _function_body("_show_main_menu")
	assert_string_contains(
		body, "_main_menu.replay_intro_requested.connect(_on_menu_replay_intro_requested)"
	)


func test_on_menu_replay_intro_requested_plays_the_real_intro():
	var body := _function_body("_on_menu_replay_intro_requested")
	assert_string_contains(body, "_play_intro_splash()")


# -- the console command: /intro ---------------------------------------------
#
# Reachable mid-game only, not from the main menu itself -- DevConsole's own
# input never runs while the tree is paused (see _show_main_menu's own
# `get_tree().paused = true`), and nothing gives World/DevConsole
# PROCESS_MODE_ALWAYS the way SettingsOverlay explicitly does. A real,
# narrower reach than the menu button, not a bug -- the button covers the
# menu, this covers "I'm already playing and want to see it again."

func test_the_intro_command_is_registered_in_the_dispatch_table():
	var dispatch := _function_body("_on_console_command")
	assert_string_contains(dispatch, "\"intro\":")
	assert_string_contains(dispatch, "_handle_intro_command()")


func test_handle_intro_command_plays_the_real_intro():
	var body := _function_body("_handle_intro_command")
	assert_string_contains(body, "_play_intro_splash()")


func test_the_help_text_mentions_the_intro_command():
	var source := _source()
	var help_start := source.find("Commands: /day")
	assert_gt(help_start, -1, "the help text should still start with /day")
	var help_end := source.find(")", help_start)
	var help := source.substr(help_start, help_end - help_start)
	assert_string_contains(help, "/intro")
