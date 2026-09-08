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

var _mixer := NatureSoundscape.new()
var _root: Node

## layer_name -> current/target LINEAR volume (0..1), for every layer
## EXCEPT the hawk-call one-shot -- it is never ramped or looped, only
## triggered directly by _maybe_play_hawk_call, so it has no "target" to
## sit at in between calls the way a bed/overlay does.
var _current_volume: Dictionary = {}
var _target_volume: Dictionary = {}

## Starts already due, same convention World's own MINIMAP_REFRESH_
## ACCUMULATOR uses -- the very first update() call must refresh
## immediately rather than sitting silent for a full REFRESH_INTERVAL_
## SECONDS first.
var _refresh_accumulator := REFRESH_INTERVAL_SECONDS

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
	_root = Node.new()
	_root.name = "NatureSoundscapePlayer"
	for layer_name in NatureSoundscape.LAYERS:
		var stream_player := AudioStreamPlayer.new()
		stream_player.name = layer_name
		var stream: AudioStream = load(NatureSoundscape.LAYERS[layer_name])
		# Explicitly typed, not `:=` -- `layer_name` here comes from iterating
		# a Dictionary's keys, an untyped Variant loop variable, and `:=`
		# type inference on an expression involving one can fail to resolve
		# a concrete type (confirmed: this exact line failed to parse as
		# `:=`, silently taking every test in this file down with it).
		var is_bed_or_overlay: bool = layer_name != NatureSoundscape.HAWK_CALL_LAYER
		_set_loops(stream, is_bed_or_overlay)
		stream_player.stream = stream
		stream_player.volume_db = SILENT_VOLUME_DB
		_root.add_child(stream_player)
		if is_bed_or_overlay:
			_current_volume[layer_name] = 0.0
			_target_volume[layer_name] = 0.0
	return _root


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


## How often the target mix is actually recomputed and the hawk-call roll
## drawn -- ambient audio doesn't need sub-second reaction, see docs/concept/
## soundscape.md's own "Playback" section.
const REFRESH_INTERVAL_SECONDS := 5.0

## How fast a layer's volume ramps toward its target, in linear volume units
## per second -- slow enough to read as a real crossfade, not a snap.
const VOLUME_RAMP_PER_SECOND := 0.2

## Recomputes the target mix (throttled -- see REFRESH_INTERVAL_SECONDS)
## and ramps every bed/overlay layer's volume toward it every call, so a
## change crossfades rather than snapping. Rolls the hawk-call accent on
## the same throttled cadence.
##
## `roll` is the hawk-call rarity draw -- same "caller draws randf(), the
## module only decides" split every chance_per_check cameo in
## scenes/world.gd already uses (e.g. EasterEggCreatures.check_one(...,
## randf())), so this stays fully deterministic to test.
func update(
	biome: String, season: String, weather: String, is_night: bool, is_snowing: bool,
	roll: float, delta: float
) -> void:
	_refresh_accumulator += delta
	if _refresh_accumulator >= REFRESH_INTERVAL_SECONDS:
		_refresh_accumulator = 0.0
		_refresh_targets(biome, season, weather, is_night, is_snowing)
		_maybe_play_hawk_call(biome, is_night, roll)
	_advance_ramp(delta)


func _refresh_targets(
	biome: String, season: String, weather: String, is_night: bool, is_snowing: bool
) -> void:
	var mix := _mixer.layer_mix(biome, season, weather, is_night, is_snowing)
	for layer_name in _target_volume:
		_target_volume[layer_name] = mix.get(layer_name, 0.0)


func _maybe_play_hawk_call(biome: String, is_night: bool, roll: float) -> void:
	if not _mixer.check_hawk_call(biome, is_night, roll):
		return
	var hawk: AudioStreamPlayer = _root.get_node(NatureSoundscape.HAWK_CALL_LAYER)
	hawk.volume_db = 0.0
	hawk.play()


## Ramps every bed/overlay layer's LINEAR volume toward its target and
## reflects that onto the real player -- starting it once volume rises off
## silence, stopping it once volume settles back at silence, so nothing
## keeps playing (even silently) once faded all the way out.
func _advance_ramp(delta: float) -> void:
	var step := VOLUME_RAMP_PER_SECOND * delta
	for layer_name in _target_volume:
		var stream_player: AudioStreamPlayer = _root.get_node(layer_name)
		var current: float = move_toward(_current_volume[layer_name], _target_volume[layer_name], step)
		_current_volume[layer_name] = current
		var silent := current <= 0.001
		stream_player.volume_db = SILENT_VOLUME_DB if silent else linear_to_db(current)
		if silent and stream_player.playing:
			stream_player.stop()
		elif not silent and not stream_player.playing:
			stream_player.play()
