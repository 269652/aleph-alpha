extends RefCounted

## Thin one-shot SFX playback for footstep/mushroom-crush/creature-call
## sounds (see docs/concept/creature_and_footstep_audio.md). Mirrors
## NatureSoundscapePlayer's own "RefCounted controller builds a real Node
## tree, caller adds it" shape, but plays discrete ONE-SHOT clips from a
## small round-robin pool rather than looping per-layer beds -- footsteps/
## calls are events, not a continuous mix.
##
## Two separate pools, not one: footstep/mushroom-crush sounds always
## happen AT THE LISTENER (the local player's own feet), so a plain
## non-positional AudioStreamPlayer is correct and simplest. A creature's
## call happens at THAT CREATURE's own position, which should read
## quieter/panned the farther it is from the player -- that needs a
## positional AudioStreamPlayer2D instead. Conflating the two would mean
## either footsteps losing their always-at-full-volume simplicity or
## creature calls losing real distance falloff.

const FootstepSound = preload("res://src/audio/footstep_sound.gd")
const CreatureCallSound = preload("res://src/audio/creature_call_sound.gd")

## Enough concurrent one-shots that the player's own alternating left/
## right steps, an occasional mushroom crush, and a nearby creature call
## don't audibly steal voices from each other -- a small, cheap pool, not
## a hard simultaneous-sound cap tuned against a measured real collision.
const FOOTSTEP_POOL_SIZE := 4
const CALL_POOL_SIZE := 4

var _root: Node
var _footstep_pool: Array[AudioStreamPlayer] = []
var _next_footstep_voice := 0
var _call_pool: Array[AudioStreamPlayer2D] = []
var _next_call_voice := 0


## A ready-to-add Node holding both voice pools, silent and stopped.
## Caller adds it to the scene; play_footstep/play_mushroom_crush/
## play_creature_call drive it from there.
func build() -> Node:
	_root = Node.new()
	_root.name = "InteractionSfxPlayer"
	for i in FOOTSTEP_POOL_SIZE:
		var voice := AudioStreamPlayer.new()
		voice.name = "FootstepVoice%d" % i
		_root.add_child(voice)
		_footstep_pool.append(voice)
	for i in CALL_POOL_SIZE:
		var voice := AudioStreamPlayer2D.new()
		voice.name = "CallVoice%d" % i
		# Godot's own default (2000px) barely attenuates at all within
		# CreatureCallSound.AUDIBLE_RADIUS_PX (~35 real metres) -- matched
		# here so a call already reads near-silent right around the same
		# real distance it stops being eligible at all, instead of full
		# volume up to a cutoff eight times further out (see that
		# constant's own doc comment).
		voice.max_distance = CreatureCallSound.AUDIBLE_RADIUS_PX
		_root.add_child(voice)
		_call_pool.append(voice)
	return _root


## The footstep sound for `surface` (see FootstepSound.surface_for) --
## always at the listener, non-positional. Reported live: "we need
## footsteps." Applies that surface's own volume adjustment (see
## FootstepSound.volume_db_for's own doc comment -- grass specifically
## reads noticeably hotter than every other sourced clip, reported live
## as "way too loud").
func play_footstep(surface: String) -> void:
	_play_footstep_clip(FootstepSound.clip_path_for(surface), FootstepSound.volume_db_for(surface))


## How long (seconds) a mushroom-crush one-shot is allowed to keep
## playing before being cut short. Reported live: "Can you make the
## mushroom crush sound only 0.3s long? It plays long after you stepped
## on it." Unlike footsteps -- naturally cut short by the very next
## step's own restart, since they repeat every stride -- a mushroom crush
## is a rare, one-off event that otherwise plays out its source
## recording's full native length. Real audio-editing tooling to trim the
## FILE itself isn't available in this environment (see assets/audio/
## footsteps/CREDITS.md's own note on the same constraint elsewhere), so
## this caps PLAYBACK instead of the asset.
const MUSHROOM_CRUSH_MAX_DURATION_SECONDS := 0.3

## A mushroom crushed underfoot -- see FootstepSound.MUSHROOM_CRUSH_
## CLIP_PATH's own doc comment for the real, sourced clip this plays.
## Capped at MUSHROOM_CRUSH_MAX_DURATION_SECONDS above; every other
## one-shot (footsteps) plays its clip out in full.
func play_mushroom_crush() -> void:
	var voice := _play_footstep_clip(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH)
	if voice == null:
		return
	voice.get_tree().create_timer(MUSHROOM_CRUSH_MAX_DURATION_SECONDS).timeout.connect(voice.stop)


## Returns the voice that started playing, or null for a real, silent
## no-op (an empty clip path -- see e.g. FootstepSound.MUSHROOM_CRUSH_
## CLIP_PATH's own doc comment for when that's still the case) rather
## than an error.
##
## `volume_db` defaults to 0.0 (the plain default, i.e. unchanged) and is
## set UNCONDITIONALLY on every call, not just when a caller has a real
## adjustment to apply -- the round-robin pool REUSES voices across
## different surfaces/sounds over time, so a voice left at a previous
## call's quieter volume (e.g. grass's own -12dB, see FootstepSound.
## volume_db_for) must never bleed into whatever plays next on that same
## voice. play_mushroom_crush deliberately relies on this default rather
## than passing 0.0 explicitly -- always full volume regardless of
## whichever surface last used this voice.
func _play_footstep_clip(clip_path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	if clip_path.is_empty():
		return null
	var voice := _footstep_pool[_next_footstep_voice]
	_next_footstep_voice = (_next_footstep_voice + 1) % _footstep_pool.size()
	voice.stream = load(clip_path)
	voice.volume_db = volume_db
	voice.play()
	return voice


## A creature's own occasional vocalization, at its real world position
## (see CreatureCallSound.check_call for the chance-per-check gate a
## caller should apply before reaching here) -- a real, silent no-op for
## any species with nothing sourced yet (see CreatureCallSound.has_call).
func play_creature_call(species: String, world_position: Vector2) -> void:
	var clip_path := CreatureCallSound.clip_path_for(species)
	if clip_path.is_empty():
		return
	var voice := _call_pool[_next_call_voice]
	_next_call_voice = (_next_call_voice + 1) % _call_pool.size()
	voice.global_position = world_position
	voice.stream = load(clip_path)
	voice.play()
