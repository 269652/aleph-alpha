extends GutTest

## The New Game / Host Game intro-splash ordering, as the RUNNING GAME
## actually gets it -- same "read World's own source and assert on function-
## body text" technique as test_world_compass_window_fanout.gd/
## test_world_torch_glow_fanout.gd: World is too heavy (EarthChunkManager,
## MainMenu, multiplayer spawn, ...) to stand up a real instance of just to
## prove one await was moved, and IntroSplash's own playback/skip behavior is
## already green in test_intro_splash.gd -- this file is only about WHEN
## World calls it, not whether it plays correctly once called.
##
## Requested live: "make it so the intro scene plays before the world
## starts? So you click new game; start; then it loads and when it loaded it
## shows the earth intro scene" -- the reverse of how _on_menu_start_requested
## shipped (docs/concept/intro_splash.md, fix/intro-splash-plays-after-menu-
## loads): the intro used to play FIRST, then the loading overlay, then the
## real work. Now the real work happens first, and the intro is the reveal
## once it's actually done.

const World = preload("res://scenes/world.gd")


## The body of one named function, read straight from source.
func _function_body(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var needle := "func %s(" % function_name
	var start := source.find(needle)
	assert_gt(start, -1, "World.%s should exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


# -- New Game / Host Game: intro plays AFTER the world is actually ready ----

## The real world-setup work (wipe, spawn) must start BEFORE the intro is
## awaited -- the whole point of the reorder: no more "intro plays, then a
## loading overlay, then the real work nobody watched the intro for."
func test_the_real_world_setup_starts_before_the_intro_is_awaited():
	var body := _function_body("_on_menu_start_requested")
	var wipe_at := body.find("_wipe_persisted_world()")
	var intro_at := body.find("await _play_intro_splash()")
	assert_gt(wipe_at, -1, "the world wipe should still happen")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_lt(wipe_at, intro_at, "the world should start setting itself up before the intro plays")


## The player must actually be spawned -- the real "loading finished"
## milestone (_compute_dry_land_spawn_tile awaits the real chunk load) --
## before the intro plays. Anchoring on _show_loading_overlay alone would
## only prove the overlay was shown, not that the heavy work behind it
## (wipe/spawn) had actually finished.
func test_the_player_is_spawned_before_the_intro_is_awaited():
	var body := _function_body("_on_menu_start_requested")
	var spawn_at := body.find("await _spawn_local_singleplayer()")
	var intro_at := body.find("await _play_intro_splash()")
	assert_gt(spawn_at, -1, "the player should still be spawned")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_lt(spawn_at, intro_at, "the intro should play only once the player has actually spawned")


## The intro is still the reveal moment BEFORE the menu is dismissed and
## control hands to the player -- not something that plays late, over
## gameplay already in progress.
func test_the_intro_is_still_awaited_before_the_menu_is_dismissed():
	var body := _function_body("_on_menu_start_requested")
	var intro_at := body.find("await _play_intro_splash()")
	var dismiss_at := body.find("_dismiss_main_menu()")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_gt(dismiss_at, -1, "the menu should still be dismissed")
	assert_lt(intro_at, dismiss_at, "the intro should finish before the menu is dismissed and control hands over")


## The loading overlay's spinner must not still be sitting there, visible,
## underneath/behind the intro -- it should be explicitly dismissed once the
## real work it was covering for is actually done, mirroring the identical
## defensive `if _loading_overlay.visible: _loading_overlay.hide_overlay()`
## guard _run_initial_client_chunk_load already uses for the same overlay.
func test_the_loading_overlay_is_hidden_before_the_intro_plays():
	var body := _function_body("_on_menu_start_requested")
	var spawn_at := body.find("await _spawn_local_singleplayer()")
	var hide_at := body.find("_loading_overlay.hide_overlay()")
	var intro_at := body.find("await _play_intro_splash()")
	assert_gt(hide_at, -1, "the loading overlay should be explicitly hidden once real loading is done")
	assert_lt(spawn_at, hide_at, "the overlay should only be hidden once the player has actually spawned")
	assert_lt(hide_at, intro_at, "the overlay should be hidden before the intro plays, not left showing behind it")


# -- Boot path: unaffected regression guard ----------------------------------
#
# This request is specifically about New Game/Host Game -- the ordinary boot
# bumper (plays over the already-shown main menu) is a separate call site and
# was never asked to change.

func test_the_boot_intro_still_plays_after_the_main_menu_is_shown():
	var body := _function_body("_ready")
	var menu_at := body.find("_show_main_menu()")
	var intro_at := body.find("await _play_intro_splash()")
	assert_gt(menu_at, -1, "the main menu should still be shown on boot")
	assert_gt(intro_at, -1, "the boot intro should still be awaited")
	assert_lt(menu_at, intro_at, "the boot intro should still play as a bumper over the already-shown menu")
