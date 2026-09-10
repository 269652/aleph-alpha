extends GutTest

## InteractionSfxPlayer -- the real AudioStreamPlayer node tree for
## footstep/mushroom-crush/creature-call one-shots (see docs/concept/
## creature_and_footstep_audio.md). build() tested standalone (never added
## to a tree, same "build once, inspect, free()" technique
## test_nature_soundscape_player.gd already uses for its own node-building
## contract); playback-state assertions use add_child_autofree since
## AudioStreamPlayer.play()/.playing need a real, live tree.

const FootstepSound = preload("res://src/audio/footstep_sound.gd")
const CreatureCallSound = preload("res://src/audio/creature_call_sound.gd")
const InteractionSfxPlayer = preload("res://src/audio/interaction_sfx_player.gd")

var player: InteractionSfxPlayer


func before_each():
	player = InteractionSfxPlayer.new()


# -- build(): the node tree's own shape --------------------------------------

func test_build_returns_a_node():
	var root := player.build()
	assert_true(root is Node)
	root.free()


func test_build_creates_the_footstep_voice_pool_as_plain_non_positional_players():
	var root := player.build()
	var voices := 0
	for child in root.get_children():
		# AudioStreamPlayer/AudioStreamPlayer2D are independent classes in
		# Godot (neither is a subtype of the other), so this `is` check
		# alone already excludes the positional call-voice pool below.
		if child is AudioStreamPlayer:
			voices += 1
	assert_eq(voices, InteractionSfxPlayer.FOOTSTEP_POOL_SIZE)
	root.free()


## Positional, not plain -- a creature's call should read quieter/panned
## the farther it is from the player, unlike the always-at-the-listener
## footstep pool above.
func test_build_creates_the_call_voice_pool_as_positional_2d_players():
	var root := player.build()
	var voices := 0
	for child in root.get_children():
		if child is AudioStreamPlayer2D:
			voices += 1
	assert_eq(voices, InteractionSfxPlayer.CALL_POOL_SIZE)
	root.free()


## Left at Godot's own default (2000px), a call voice would barely
## attenuate at all within CreatureCallSound.AUDIBLE_RADIUS_PX (~35 real
## metres -- see that constant's own doc comment), undermining the whole
## "eligibility gate at a real, bounded distance" point of that radius:
## a creature right at the edge of being heard AT ALL should already read
## as quiet, not full volume up to a cutoff eight times further out.
func test_call_voices_attenuate_over_the_same_radius_calls_are_eligible_within():
	var root := player.build()
	for voice in player._call_pool:
		# almost_eq, not eq: max_distance round-trips through Godot's own
		# real_t (32-bit float on most builds), a tiny precision loss
		# GDScript's 64-bit float literal on the right-hand side doesn't
		# have -- not a real behavioral difference worth chasing further.
		assert_almost_eq(voice.max_distance, CreatureCallSound.AUDIBLE_RADIUS_PX, 0.01)
	root.free()


# -- playback: real live-tree state -------------------------------------------

func test_play_footstep_loads_and_plays_the_surface_clip():
	add_child_autofree(player.build())
	player.play_footstep("forest")
	var playing_voice := _find_playing_voice(FootstepSound.clip_path_for("forest"))
	assert_not_null(playing_voice, "expected some footstep voice to be playing the forest clip")


func test_play_footstep_with_an_unheard_of_surface_still_plays_the_default_clip():
	add_child_autofree(player.build())
	player.play_footstep("lava")
	var playing_voice := _find_playing_voice(FootstepSound.clip_path_for("default"))
	assert_not_null(playing_voice, "an unknown surface should still make SOME footstep sound")


func test_play_mushroom_crush_does_not_error():
	add_child_autofree(player.build())
	player.play_mushroom_crush()
	assert_engine_error_count(0)


## Mirrors test_play_footstep_loads_and_plays_the_surface_clip's own shape
## exactly -- a real, sourced clip (see FootstepSound.MUSHROOM_CRUSH_
## CLIP_PATH's own doc comment) must actually load and play, not just fail
## to error.
func test_play_mushroom_crush_loads_and_plays_the_real_clip():
	add_child_autofree(player.build())
	player.play_mushroom_crush()
	var playing_voice := _find_playing_voice(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH)
	assert_not_null(playing_voice, "expected some footstep voice to be playing the mushroom-crush clip")


func test_play_creature_call_positions_the_voice_at_the_creatures_world_position():
	add_child_autofree(player.build())
	player.play_creature_call("horse", Vector2(123.0, 456.0))
	for voice in player._call_pool:
		if voice.playing:
			assert_eq(voice.global_position, Vector2(123.0, 456.0))
			return
	fail_test("expected some call voice to be playing after play_creature_call")


func test_play_creature_call_for_an_unsourced_species_plays_nothing():
	add_child_autofree(player.build())
	player.play_creature_call("dragon", Vector2.ZERO)
	for voice in player._call_pool:
		assert_false(voice.playing)


## Round-robins rather than always reusing voice 0 -- otherwise rapid
## alternating left/right footsteps would keep cutting each other off
## instead of the small pool giving them room to overlap.
func test_repeated_footsteps_advance_through_the_pool_round_robin():
	add_child_autofree(player.build())
	var first_index := player._next_footstep_voice
	player.play_footstep("grass")
	assert_eq(
		player._next_footstep_voice, (first_index + 1) % InteractionSfxPlayer.FOOTSTEP_POOL_SIZE
	)


## Reported live: "Can you make the mushroom crush sound only 0.3s long?
## It plays long after you stepped on it." Real audio-editing tooling to
## trim the FILE itself isn't available in this environment (see
## assets/audio/footsteps/CREDITS.md's own note on why forest_twigs.ogg
## needed a transcode swap for the same underlying reason) -- capped in
## PLAYBACK instead. A real wall-clock wait (not a fake-delta trick).
func test_mushroom_crush_stops_itself_after_its_own_max_duration():
	add_child_autofree(player.build())
	player.play_mushroom_crush()
	var voice := _find_playing_voice(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH)
	assert_not_null(voice, "the premise: it must actually be playing right after triggering")
	assert_true(voice.playing)

	await wait_seconds(InteractionSfxPlayer.MUSHROOM_CRUSH_MAX_DURATION_SECONDS + 0.15)

	assert_false(
		voice.playing,
		"should have been cut short at MUSHROOM_CRUSH_MAX_DURATION_SECONDS, not left to play out"
	)


# -- per-surface volume: reported live, "grass footsteps are way too --
# -- loud... make them fainter" -----------------------------------------

func test_play_footstep_applies_the_surfaces_own_volume_adjustment():
	add_child_autofree(player.build())
	player.play_footstep("grass")
	var voice := _find_playing_voice(FootstepSound.clip_path_for("grass"))
	assert_not_null(voice)
	assert_eq(voice.volume_db, FootstepSound.volume_db_for("grass"))


## The round-robin pool REUSES voices across different surfaces over
## time -- a voice left at grass's own quieter volume_db must not bleed
## into whatever surface plays next on that same voice. Cycles the full
## pool with the quieter surface first so the next call is GUARANTEED to
## land on a voice that was actually left at -12dB, not just a fresh one
## that happened to already read 0dB by coincidence.
func test_play_footstep_does_not_inherit_a_previous_surfaces_quieter_volume():
	add_child_autofree(player.build())
	for i in InteractionSfxPlayer.FOOTSTEP_POOL_SIZE:
		player.play_footstep("grass")
	player.play_footstep("snow")
	var voice := _find_playing_voice(FootstepSound.clip_path_for("snow"))
	assert_not_null(voice)
	assert_eq(voice.volume_db, 0.0)


## Same reuse hazard, the other direction: a mushroom crush landing on a
## voice grass just left quiet must still play at full volume.
func test_play_mushroom_crush_does_not_inherit_a_previous_surfaces_quieter_volume():
	add_child_autofree(player.build())
	for i in InteractionSfxPlayer.FOOTSTEP_POOL_SIZE:
		player.play_footstep("grass")
	player.play_mushroom_crush()
	var voice := _find_playing_voice(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH)
	assert_not_null(voice)
	assert_eq(voice.volume_db, 0.0, "must not inherit grass's quieter volume from a reused pool voice")


func _find_playing_voice(expected_clip_path: String) -> AudioStreamPlayer:
	for voice in player._footstep_pool:
		if voice.playing and voice.stream != null and voice.stream.resource_path == expected_clip_path:
			return voice
	return null
