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
