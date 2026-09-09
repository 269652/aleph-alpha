extends GutTest

## The boot-time loading screen, as the RUNNING GAME actually gets it -- same
## "read World._ready() straight from source and assert on ordering" technique
## as test_world_intro_splash_after_load_fanout.gd/test_world_torch_glow_
## fanout.gd/test_world_compass_window_fanout.gd: World is too heavy
## (EarthChunkManager, MainMenu, multiplayer spawn, ...) to stand up a real
## instance of just to prove a few calls got reordered, and LoadingOverlay's
## own show/hide/set_progress behavior is already green in
## test_loading_overlay.gd -- this file is only about WHEN World shows it
## during boot, not whether it renders correctly once shown.
##
## Reported live (a screenshot): the FIRST thing a fresh launch shows is a
## dark screen with a plain, unstyled "Loading..." label top-left, a solid
## green bar under it, and a stray yellow square top-right -- read as "stuck"
## and "not professional". Traced to source, not guessed: `_build_loading_
## overlay()`/`_show_loading_overlay(...)` are never called until deep inside
## _ready(), well AFTER the real, still-substantial `MushroomMarker.
## warm_art_cache()` boot cost (measured ~52s dominant contributor, see
## docs/concept/soil_fauna.md's "FPS regression round 6" / this file's own
## commit) already starts -- so for that whole stretch, nothing is covering
## the raw, never-yet-updated scene.tscn UI: `UI/DebugLabel`'s literal
## `.tscn`-authored default text IS "Loading..." (see scenes/world.tscn),
## `UI/PlayerHealthBar/Fill` is a green ColorRect sitting at its authored
## default (unset) width since the player's real HP hasn't been assigned
## yet, and `UI/Minimap/PlayerDot` is a yellow ColorRect floating with no
## minimap texture behind it yet. None of that was ever a designed loading
## screen -- it's an accidental symptom of showing the real loading overlay
## too late.
##
## Fix: build and show the loading overlay FIRST, before the heavy setup
## starts, wire MushroomMarker.warm_art_cache's own existing (already built,
## never-yet-used) `on_progress` callback parameter to it -- mirroring
## World._on_chunk_load_progress's identical existing wiring for
## EarthChunkManager.update_with_progress exactly -- and hide it again once
## that setup is done, before any of the three post-setup launch paths
## (--solo / --server-or-join / the ordinary menu) proceed.

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


func _ready_body() -> String:
	return _function_body("_ready")


# -- the overlay must actually cover the heavy boot setup, not just exist ---

func test_the_loading_overlay_is_built_before_the_heavy_boot_setup_starts():
	var body := _ready_body()
	var build_at := body.find("_build_loading_overlay()")
	var chunk_manager_at := body.find("EarthChunkManager.new(")
	assert_gt(build_at, -1, "the loading overlay should be built somewhere in _ready()")
	assert_gt(chunk_manager_at, -1, "the chunk manager should still be built here")
	assert_lt(
		build_at, chunk_manager_at,
		"the overlay must be built before the heavy chunk-manager setup, not after"
	)


func test_the_loading_overlay_is_shown_before_the_mushroom_art_is_warmed():
	var body := _ready_body()
	var show_at := body.find("_show_loading_overlay(")
	var warm_at := body.find("MushroomMarker.warm_art_cache(")
	assert_gt(show_at, -1, "the loading overlay should be shown somewhere in _ready()")
	assert_gt(warm_at, -1, "warm_art_cache should still be awaited here")
	assert_lt(
		show_at, warm_at,
		"the overlay must be shown (and painted) before the real, slow art-warming work starts"
	)


# -- real, determinate progress -- not just an indeterminate cover ----------

## MushroomMarker.warm_art_cache already accepts an optional `on_progress`
## callback (see its own doc comment: "wired for the same reason update_
## with_progress's is: a future boot-time loading readout, not invented
## here") -- this is that readout finally being wired up, not a new API.
func test_warming_the_mushroom_art_cache_reports_real_progress():
	assert_string_contains(
		_ready_body(), "MushroomMarker.warm_art_cache(_on_mushroom_art_progress)",
		"warm_art_cache should be called WITH its progress callback, not bare -- " +
		"otherwise the overlay has nothing to show but an indeterminate spinner " +
		"for the whole real duration, same complaint as the chunks-loading screen once had"
	)


## Mirrors _on_chunk_load_progress's own exact shape -- the callback must
## actually reach the overlay, not just exist as a dead function nothing
## calls through to.
func test_mushroom_art_progress_updates_the_loading_overlay_with_a_real_unit():
	var body := _function_body("_on_mushroom_art_progress")
	assert_string_contains(
		body, "_loading_overlay.set_progress(",
		"the progress callback should actually update the loading overlay"
	)
	assert_string_contains(
		body, "\"species\"",
		"the unit word should honestly say species, not silently inherit set_progress's " +
		"own \"chunks\" default -- the same real-vs-lying-unit fix set_progress's own " +
		"third parameter already exists for"
	)


# -- the overlay must not linger, covering (or racing) whatever comes next --

func test_the_loading_overlay_is_hidden_once_the_heavy_boot_setup_finishes():
	var body := _ready_body()
	var warm_at := body.find("MushroomMarker.warm_art_cache(")
	var hide_at := body.find("_loading_overlay.hide_overlay()")
	var solo_branch_at := body.find("if \"--solo\" in args:")
	assert_gt(warm_at, -1, "warm_art_cache should still be awaited here")
	assert_gt(hide_at, -1, "the overlay should be explicitly hidden once the heavy setup is done")
	assert_gt(solo_branch_at, -1, "the post-setup launch-mode dispatch should still exist")
	assert_lt(warm_at, hide_at, "the overlay must stay up for the whole real duration of the heavy setup")
	assert_lt(
		hide_at, solo_branch_at,
		"the overlay must be hidden before ANY launch-mode path proceeds -- solo/server/join included, " +
		"not just the ordinary menu path"
	)
