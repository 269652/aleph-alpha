extends GutTest

## The ambient-soundscape wiring, as the RUNNING GAME actually gets it --
## same reasoning and the same "read World source straight from source"
## technique as test_world_torch_glow_fanout.gd: NatureSoundscapePlayer's
## own pure logic is green in test_nature_soundscape.gd/
## test_nature_soundscape_player.gd, and a feature green in its own unit
## tests while silent while playing is not done (docs/concept/
## soundscape.md's own Status section named exactly this gap before this
## file existed).


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


## The body of one named function, read straight from source.
func _function_body(function_name: String) -> String:
	var source := _source()
	var needle := "func %s(" % function_name
	var start := source.find(needle)
	assert_gt(start, -1, "World.%s should still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	if body_end == -1:
		body_end = source.length()
	return source.substr(start, body_end - start)


## The soundscape player must actually be built into the tree, or update()
## below has no real AudioStreamPlayer to drive.
func test_ready_builds_the_nature_soundscape_player_into_the_tree():
	assert_string_contains(
		_function_body("_ready"),
		"add_child(_nature_soundscape.build())",
		"the soundscape player is never added to the running scene"
	)


## The line that makes the whole mechanism audible while playing. Without
## it, layer_mix's own real, tested logic is dead code and nothing ever
## actually plays.
func test_the_client_frame_updates_the_nature_soundscape():
	assert_string_contains(
		_function_body("_client_process"),
		"_nature_soundscape.update(",
		"the soundscape never learns the world's current biome/season/weather"
	)


## Biome must come from the player's own real tile (CreatureMarker/
## FishMarker/NpcMarker's own biome_at_global convention), not a second,
## differently-scoped biome figure that could disagree with what every
## other per-position system already reads.
func test_the_soundscape_update_uses_the_shared_biome_at_global_lookup():
	assert_string_contains(
		_function_body("_client_process"),
		"_chunk_manager.biome_at_global(player_tile.x, player_tile.y)",
		"the soundscape re-derives biome instead of reusing the shared lookup"
	)


## is_night must be the SAME real sun elevation day/night lighting, the
## HUD, and every Easter-egg cameo already agree on -- a second,
## independently-computed day/night boundary here could disagree with what
## the player sees overhead.
func test_the_soundscape_update_reuses_the_same_elevation_based_is_night():
	assert_string_contains(
		_function_body("_client_process"),
		"elevation <= 0.0",
		"the soundscape computes day/night independently instead of reusing elevation"
	)


## snowing must be the SAME boolean the rain overlay/water/snow accumulation
## already react to this frame -- a second, independently-derived snowing
## flag here could disagree with what the sky is visibly doing.
func test_the_soundscape_update_reuses_the_same_snowing_flag_as_the_rain_overlay():
	var body := _function_body("_client_process")
	var rain_call := body.find("_rain_overlay.set_snowing(snowing)")
	var soundscape_call := body.find("_nature_soundscape.update(")
	assert_gt(rain_call, -1, "sanity: the rain overlay's own snowing call should still exist")
	assert_gt(soundscape_call, -1)
	assert_string_contains(body.substr(soundscape_call), "snowing")


## "fully build the soundscape out of individual nearby animals and
## environment" -- the "environment" half. The river-proximity overlay
## (see docs/concept/soundscape.md) needs the player's own real distance
## to the nearest water, from the SAME EarthChunkManager the biome lookup
## right above already reads, not a second, independent water check.
##
## The raw scan is throttled: cached into _cached_water_distance_tiles
## BEFORE _nature_soundscape.update() is ever called, not evaluated as a
## live call-argument (see WATER_PROXIMITY_REFRESH_INTERVAL's own doc
## comment -- a real "Still at 1fps" fix). So this checks both halves
## separately instead of expecting the raw call inline in update()'s own
## argument list: the cache is fed by the chunk manager's own real scan
## (tolerating that call's args wrapping across lines, the same as
## test_world_footstep_wiring.gd's multi-arg calls do), and update()
## actually consumes that cache rather than re-deriving it.
func test_the_soundscape_update_passes_the_real_water_distance():
	var body := _function_body("_client_process")
	var cache_assignment := body.find(
		"_cached_water_distance_tiles = _chunk_manager.nearest_water_distance_tiles("
	)
	assert_gt(cache_assignment, -1, "the cached water distance must come from the chunk manager's own real scan")
	var scan_call := body.substr(cache_assignment)
	var scan_args := scan_call.substr(0, scan_call.find(")"))
	assert_string_contains(scan_args, "player_tile.x")
	assert_string_contains(scan_args, "player_tile.y")

	var soundscape_call := body.find("_nature_soundscape.update(")
	assert_gt(soundscape_call, -1)
	assert_string_contains(
		body.substr(soundscape_call),
		"_cached_water_distance_tiles",
		"must pass the player's own real (cached) water distance through to the soundscape"
	)
