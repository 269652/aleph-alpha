extends GutTest

## InteractionSfxPlayer -- the real AudioStreamPlayer node tree for
## footstep/mushroom-crush/creature-call one-shots (see docs/concept/
## creature_and_footstep_audio.md). build() tested standalone (never added
## to a tree, same "build once, inspect, free()" technique
## test_nature_soundscape_player.gd already uses for its own node-building
## contract); playback-state assertions use add_child_autofree since
## AudioStreamPlayer.play()/.playing need a real, live tree.

const FootstepSound = preload("res://src/audio/footstep_sound.gd")
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


## Mushroom crush is a real, honest no-op today (see FootstepSound.
## MUSHROOM_CRUSH_CLIP_PATH's own doc comment) -- must not error just
## because there is nothing to play yet.
func test_play_mushroom_crush_does_not_error_while_unsourced():
	add_child_autofree(player.build())
	player.play_mushroom_crush()
	assert_engine_error_count(0, "an unsourced one-shot should be a silent no-op, not an error")


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


func _find_playing_voice(expected_clip_path: String) -> AudioStreamPlayer:
	for voice in player._footstep_pool:
		if voice.playing and voice.stream != null and voice.stream.resource_path == expected_clip_path:
			return voice
	return null
