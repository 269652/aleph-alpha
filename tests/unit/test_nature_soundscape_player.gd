extends GutTest

## NatureSoundscapePlayer -- the real AudioStreamPlayer node tree for
## docs/concept/soundscape.md's ambient soundscape. build() is tested
## standalone (never added to a tree, same "build once, inspect, free()"
## technique test_rain_overlay.gd already uses for its own node-building
## contract); update()'s playback-state assertions use add_child_autofree
## since AudioStreamPlayer.play()/.playing need a real, live tree the same
## way test_world_play_intro_splash_frame_gate.gd's own CanvasLayer does.

const NatureSoundscape = preload("res://src/audio/nature_soundscape.gd")
const NatureSoundscapePlayer = preload("res://src/audio/nature_soundscape_player.gd")

var player: NatureSoundscapePlayer


func before_each():
	player = NatureSoundscapePlayer.new()


# -- build(): the node tree's own shape --------------------------------------

func test_build_returns_a_node():
	var root := player.build()
	assert_true(root is Node)
	root.free()


func test_build_creates_one_audio_stream_player_per_registered_layer():
	var root := player.build()
	assert_eq(root.get_child_count(), NatureSoundscape.LAYERS.size())
	for layer_name in NatureSoundscape.LAYERS:
		var child := root.get_node_or_null(layer_name)
		assert_not_null(child, "expected a child named %s" % layer_name)
		assert_true(child is AudioStreamPlayer, layer_name)
	root.free()


func test_build_loads_the_real_stream_for_every_layer():
	var root := player.build()
	for layer_name in NatureSoundscape.LAYERS:
		var child: AudioStreamPlayer = root.get_node(layer_name)
		assert_not_null(child.stream, "%s should have a real stream loaded" % layer_name)
	root.free()


func test_build_starts_every_player_silent_and_not_yet_playing():
	var root := player.build()
	for layer_name in NatureSoundscape.LAYERS:
		var child: AudioStreamPlayer = root.get_node(layer_name)
		assert_false(child.playing, layer_name)
		assert_lte(child.volume_db, NatureSoundscapePlayer.SILENT_VOLUME_DB, layer_name)
	root.free()


## Beds/overlays loop (an ambient bed that played once and stopped would be
## a much bigger, much stranger bug than the hawk call's own one-shot).
func test_build_loops_every_bed_and_overlay_layer():
	var root := player.build()
	for layer_name in NatureSoundscape.LAYERS:
		if layer_name == NatureSoundscape.HAWK_CALL_LAYER:
			continue
		var child: AudioStreamPlayer = root.get_node(layer_name)
		assert_true(_stream_loops(child.stream), layer_name)
	root.free()


## The hawk call is an occasional ONE-SHOT accent -- a looping raptor cry
## would be absurd, not atmospheric.
func test_build_does_not_loop_the_hawk_call():
	var root := player.build()
	var hawk: AudioStreamPlayer = root.get_node(NatureSoundscape.HAWK_CALL_LAYER)
	assert_false(_stream_loops(hawk.stream))
	root.free()


func _stream_loops(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		return stream.loop
	if stream is AudioStreamWAV:
		return stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	fail_test("unexpected stream type %s" % stream)
	return false


# -- update(): throttled mixing + crossfade + hawk-call roll -----------------
# AudioStreamPlayer.play()/.playing need a real, live tree the same way
# test_world_play_intro_splash_frame_gate.gd's own CanvasLayer does -- built
# fresh per test via add_child_autofree rather than shared setup, since
# update() carries real internal ramp state across calls.

func _live_root() -> Node:
	var root := player.build()
	add_child_autofree(root)
	return root


## The very first call must not sit silent for a full REFRESH_INTERVAL_
## SECONDS before doing anything -- mirrors World's own MINIMAP_REFRESH_
## ACCUMULATOR convention (starts pre-due, refreshes immediately).
func test_first_update_call_refreshes_the_mix_immediately():
	var root := _live_root()
	player.update("ocean", "summer", "clear", false, false, 1.0, 0.01)
	var ocean: AudioStreamPlayer = root.get_node("ocean")
	assert_gt(ocean.volume_db, NatureSoundscapePlayer.SILENT_VOLUME_DB)


## A tiny delta must NOT already be at the target -- a crossfade that
## reaches full volume in one small step is not a crossfade.
func test_volume_ramps_gradually_rather_than_snapping_to_target():
	var root := _live_root()
	player.update("ocean", "summer", "clear", false, false, 1.0, 0.01)
	var ocean: AudioStreamPlayer = root.get_node("ocean")
	assert_lt(ocean.volume_db, linear_to_db(NatureSoundscape.FULL_BED_VOLUME) - 0.01)


## Enough cumulative time must actually settle at the target and start
## playing -- a ramp that asymptotically approaches but never starts the
## player would be silent forever in practice.
func test_volume_reaches_target_and_plays_after_enough_time():
	var root := _live_root()
	player.update("ocean", "summer", "clear", false, false, 1.0, 100.0)
	var ocean: AudioStreamPlayer = root.get_node("ocean")
	assert_almost_eq(ocean.volume_db, linear_to_db(NatureSoundscape.FULL_BED_VOLUME), 0.01)
	assert_true(ocean.playing)


## Switching biome must fade the old layer back out and stop it, not leave
## it playing silently (or worse, audibly) forever underneath the new one.
func test_switching_biome_fades_out_and_stops_the_previous_layer():
	var root := _live_root()
	player.update("ocean", "summer", "clear", false, false, 1.0, 100.0)
	var ocean: AudioStreamPlayer = root.get_node("ocean")
	assert_true(ocean.playing, "sanity: ocean should be playing before the switch")
	player.update("desert", "summer", "clear", false, false, 1.0, 100.0)
	assert_false(ocean.playing, "the old layer must stop once it fades out")
	var wind: AudioStreamPlayer = root.get_node("wind")
	assert_true(wind.playing)


## Reported live: "when I walk into the water it takes a while before the
## river wading sound is played then it fades out and takes a while again"
## -- REFRESH_INTERVAL_SECONDS (5s) throttled the target-mix recompute
## UNCONDITIONALLY, so a real, discrete state change (the player stepping
## into/out of a biome, a storm starting) could sit for up to a full 5s
## BEFORE the ramp toward the new target even starts -- on top of the
## ramp's own several real seconds. Any real INPUT change now recomputes
## immediately; only repeated calls with the exact same inputs stay
## throttled (nothing changed to react to yet, so there is nothing to
## gain from recomputing every single frame).
func test_an_input_change_refreshes_immediately_not_after_the_throttle():
	var root := _live_root()
	player.update("desert", "summer", "clear", false, false, 1.0, 100.0)  # settle fully
	var wind: AudioStreamPlayer = root.get_node("wind")
	assert_true(wind.playing, "sanity: wind should be settled in before the switch")
	# A tiny delta, far short of REFRESH_INTERVAL_SECONDS -- under the OLD
	# throttle-everything behavior this would sit un-refreshed.
	player.update("ocean", "summer", "clear", false, false, 1.0, 0.01)
	var ocean: AudioStreamPlayer = root.get_node("ocean")
	assert_gt(
		ocean.volume_db, NatureSoundscapePlayer.SILENT_VOLUME_DB,
		"a genuine biome change should start ramping in immediately, not wait out the throttle"
	)


## The flip side: repeated calls with EVERY input unchanged must stay
## throttled exactly as before -- this fix targets real transitions
## specifically, not a blanket "always refresh every call" regression that
## would defeat REFRESH_INTERVAL_SECONDS (and the hawk-call roll's own
## intended rarity, which rides the same throttle) entirely.
func test_unchanged_inputs_still_only_refresh_on_the_normal_throttle():
	var root := _live_root()
	player.update("mountain", "summer", "clear", false, false, 1.0, 100.0)  # settle fully
	var wind: AudioStreamPlayer = root.get_node("wind")
	var settled_volume_db := wind.volume_db
	# Same inputs, tiny delta -- nothing changed, so this should still be
	# a no-op recompute (the ramp has nothing left to do either, already
	# fully settled from the call above).
	player.update("mountain", "summer", "clear", false, false, 1.0, 0.01)
	assert_almost_eq(wind.volume_db, settled_volume_db, 0.01)


func test_hawk_call_plays_when_eligible_and_the_roll_clears_the_threshold():
	var root := _live_root()
	player.update("mountain", "summer", "clear", false, false, 0.0, 100.0)
	var hawk: AudioStreamPlayer = root.get_node(NatureSoundscape.HAWK_CALL_LAYER)
	assert_true(hawk.playing)


func test_hawk_call_does_not_play_when_not_eligible_even_with_a_guaranteed_roll():
	var root := _live_root()
	player.update("forest", "summer", "clear", false, false, 0.0, 100.0)
	var hawk: AudioStreamPlayer = root.get_node(NatureSoundscape.HAWK_CALL_LAYER)
	assert_false(hawk.playing)


func test_hawk_call_does_not_play_when_the_roll_misses_the_threshold():
	var root := _live_root()
	player.update("mountain", "summer", "clear", false, false, 1.0, 100.0)
	var hawk: AudioStreamPlayer = root.get_node(NatureSoundscape.HAWK_CALL_LAYER)
	assert_false(hawk.playing)


# -- river proximity: passthrough for the "environment" half of ------------
# -- "compose the sound from what's actually around you" -------------------

## Omitting water_distance_tiles entirely (every pre-existing 7-arg call
## site above) must keep behaving exactly as before -- no river layer.
func test_omitting_water_distance_targets_no_river_volume_at_all():
	var root := _live_root()
	player.update("grassland", "summer", "clear", false, false, 1.0, 100.0)
	var river: AudioStreamPlayer = root.get_node(NatureSoundscape.RIVER_LAYER)
	assert_false(river.playing)


func test_standing_on_water_ramps_the_river_layer_up_and_plays_it():
	var root := _live_root()
	player.update("grassland", "summer", "clear", false, false, 1.0, 100.0, 0.0)
	var river: AudioStreamPlayer = root.get_node(NatureSoundscape.RIVER_LAYER)
	assert_true(river.playing)
	assert_almost_eq(
		db_to_linear(river.volume_db), NatureSoundscape.RIVER_OVERLAY_MAX_VOLUME, 0.01
	)


func test_walking_away_from_water_ramps_the_river_layer_back_down():
	var root := _live_root()
	player.update("grassland", "summer", "clear", false, false, 1.0, 100.0, 0.0)  # settle fully, close
	player.update(
		"grassland", "summer", "clear", false, false, 1.0, 100.0, NatureSoundscape.RIVER_AUDIBLE_RADIUS_TILES
	)  # settle fully, far
	var river: AudioStreamPlayer = root.get_node(NatureSoundscape.RIVER_LAYER)
	assert_false(river.playing)
