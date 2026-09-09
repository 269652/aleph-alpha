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
## A SECOND reversal of this same ordering (see docs/concept/intro_splash.md
## for the full history). First it played BEFORE any real work, as a pure
## bumper nobody watched a loading screen through. Then, requested live
## ("make it so the intro scene plays before the world starts... when it
## loaded it shows the earth intro scene"), it moved to play AFTER the real
## work, as the reveal once the freshly-spawned world was actually ready.
## Now, requested live again -- "play the intro right after overwrite and
## start / right before the world creation loading screen" -- it moves back
## to playing FIRST, but precisely anchored at the moment the player commits
## to starting (Begin/"Overwrite and start"), not at boot: intro, THEN the
## "Preparing a new world..." loading overlay covers the real wipe/spawn
## work, exactly the original pre-reversal shape, just requested again on
## purpose rather than accidentally reintroduced.

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


# -- New Game / Host Game: intro plays FIRST, right when start is requested -

## The whole point of this pass: the intro is the very first thing that
## happens once the player commits (Begin / "Overwrite and start"), before
## the loading overlay ever shows and before any real world-setup work
## starts -- not buried after wipe/spawn as the prior ordering had it.
func test_the_intro_plays_before_the_loading_overlay_shows():
	var body := _function_body("_on_menu_start_requested")
	var intro_at := body.find("await _play_intro_splash()")
	var overlay_at := body.find("await _show_loading_overlay(")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_gt(overlay_at, -1, "the loading overlay should still be shown")
	assert_lt(intro_at, overlay_at, "the intro should play before the loading overlay ever shows")


## The real world-setup work (wipe) must not start until the intro has
## already played -- otherwise the intro would be racing/overlapping real
## work again, exactly what this reorder moves away from.
func test_the_real_world_setup_starts_after_the_intro_has_played():
	var body := _function_body("_on_menu_start_requested")
	var intro_at := body.find("await _play_intro_splash()")
	var wipe_at := body.find("_wipe_persisted_world()")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_gt(wipe_at, -1, "the world wipe should still happen")
	assert_lt(intro_at, wipe_at, "the intro should finish before the world starts wiping/rebuilding itself")


## Same guarantee for the player's own spawn -- the intro is a bumper before
## ANY of the real work now, not just before the wipe specifically.
func test_the_player_is_spawned_after_the_intro_has_played():
	var body := _function_body("_on_menu_start_requested")
	var intro_at := body.find("await _play_intro_splash()")
	var spawn_at := body.find("await _spawn_local_singleplayer()")
	assert_gt(intro_at, -1, "the intro splash should still be awaited somewhere")
	assert_gt(spawn_at, -1, "the player should still be spawned")
	assert_lt(intro_at, spawn_at, "the intro should finish before the player is spawned")


## The menu must still only be dismissed once the real work is genuinely
## done and the loading overlay is no longer covering it -- unaffected by
## WHERE the intro sits, since the intro now finishes long before either of
## these anyway.
func test_the_menu_is_dismissed_only_once_the_world_is_actually_ready():
	var body := _function_body("_on_menu_start_requested")
	var spawn_at := body.find("await _spawn_local_singleplayer()")
	var hide_at := body.find("_loading_overlay.hide_overlay()")
	var dismiss_at := body.find("_dismiss_main_menu()")
	assert_gt(spawn_at, -1, "the player should still be spawned")
	assert_gt(hide_at, -1, "the loading overlay should still be explicitly hidden once real loading is done")
	assert_gt(dismiss_at, -1, "the menu should still be dismissed")
	assert_lt(spawn_at, hide_at, "the overlay should only be hidden once the player has actually spawned")
	assert_lt(hide_at, dismiss_at, "the menu should only be dismissed once the overlay is no longer covering it")


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
