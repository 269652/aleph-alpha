extends RefCounted

## The real AudioStreamPlayer node tree for docs/concept/soundscape.md's
## ambient soundscape. Mirrors RainOverlay's own shape exactly: a
## RefCounted controller whose build() constructs a real, freestanding Node
## the caller adds to the scene, and whose update() pushes fresh per-frame
## state into it -- testable by building the tree standalone (same
## "build once, inspect, free()" technique test_rain_overlay.gd already
## uses) without needing a live SceneTree for structural assertions, and
## add_child_autofree for the handful that need real playback state.

const NatureSoundscape = preload("res://src/audio/nature_soundscape.gd")

## Effectively inaudible -- real silence (-inf dB) is a real float value
## AudioStreamPlayer accepts, but linear_to_db(0.0) IS -inf, and comparing
## against -inf elsewhere is a real footgun; a large real finite floor sidesteps
## that everywhere below without an audible difference from true silence.
const SILENT_VOLUME_DB := -80.0

## A ready-to-add Node holding one AudioStreamPlayer per NatureSoundscape.
## LAYERS entry -- real stream loaded, looping for every bed/overlay layer
## (an ambient bed that played once and stopped would be a much stranger
## bug than the hawk call's own deliberate one-shot), silent and stopped.
## Caller adds it to the scene; update() drives it from there.
func build() -> Node:
	var root := Node.new()
	root.name = "NatureSoundscapePlayer"
	for layer_name in NatureSoundscape.LAYERS:
		var stream_player := AudioStreamPlayer.new()
		stream_player.name = layer_name
		var stream: AudioStream = load(NatureSoundscape.LAYERS[layer_name])
		_set_loops(stream, layer_name != NatureSoundscape.HAWK_CALL_LAYER)
		stream_player.stream = stream
		stream_player.volume_db = SILENT_VOLUME_DB
		root.add_child(stream_player)
	return root


## Each of the three stream types this project's 11 assets actually use
## (.ogg/.mp3/.wav) spells looping through a different property -- see
## docs/concept/soundscape.md's own asset list for why all three appear.
func _set_loops(stream: AudioStream, should_loop: bool) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = should_loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = (
			AudioStreamWAV.LOOP_FORWARD if should_loop else AudioStreamWAV.LOOP_DISABLED
		)


## STUB -- not yet implemented.
func update(
	_biome: String, _season: String, _weather: String, _is_night: bool, _is_snowing: bool,
	_delta: float
) -> void:
	pass
