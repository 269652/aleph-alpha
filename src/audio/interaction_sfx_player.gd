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
## How many sounds each footstep voice has been handed, parallel to
## _footstep_pool -- the token a pending window-closing timer is checked
## against, so a recycled voice is never cut short by the previous step's
## own timer (see _stop_if_still_the_same_sound).
var _footstep_sounds_played: Array[int] = []
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
		_footstep_sounds_played.append(0)
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
##
## Passes `surface` through as well as its clip path: most of the sourced
## clips are long recordings of somebody WALKING rather than single steps,
## and reading one step out of one needs to know which (see FootstepSound's
## own "one step out of a recording of many").
func play_footstep(surface: String) -> void:
	_play_footstep_clip(
		FootstepSound.clip_path_for(surface), FootstepSound.volume_db_for(surface), surface
	)


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
## Capped at MUSHROOM_CRUSH_MAX_DURATION_SECONDS above.
##
## Deliberately passes NO surface: a crush is its own one-shot, played
## whole from its own beginning at its own pitch, never a window into
## somebody's recorded walk -- and never inheriting the pitch a reused
## pool voice was left at by the last footstep, exactly as it already
## relies on the default volume for the same reason.
func play_mushroom_crush() -> AudioStreamPlayer:
	return _play_footstep_clip(
		FootstepSound.MUSHROOM_CRUSH_CLIP_PATH, 0.0, "", MUSHROOM_CRUSH_MAX_DURATION_SECONDS
	)


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
##
## `surface` is what makes a step sound like a step rather than like the
## same recording restarted (reported live: "they sound weak and not
## natural"). Most sourced clips are minutes of somebody walking, not one
## step, so a step is read as a WINDOW into one: it starts somewhere else
## in the recording each time (FootstepSound.offset_for), at a slightly
## different pitch (FootstepSound.pitch_scale_for), and closes again after
## one step's worth (FootstepSound.STEP_WINDOW_SECONDS) instead of leaving
## the rest of a stranger's walk playing underneath the next one. An empty
## surface -- the default -- means "this is not a surface step": played
## whole, from the top, unpitched.
##
## Pitch is set UNCONDITIONALLY for exactly the reason volume_db is above:
## the pool reuses voices, and a pitch left behind by a previous step must
## not ride along on whatever plays next.
##
## `max_seconds` caps playback for a sound that is not a footstep but still
## must not play out its whole source recording (see
## MUSHROOM_CRUSH_MAX_DURATION_SECONDS); 0.0 leaves the choice to the
## surface's own step window above.
func _play_footstep_clip(
	clip_path: String, volume_db: float = 0.0, surface: String = "", max_seconds: float = 0.0
) -> AudioStreamPlayer:
	if clip_path.is_empty():
		return null
	var index := _next_footstep_voice
	var voice := _footstep_pool[index]
	_next_footstep_voice = (_next_footstep_voice + 1) % _footstep_pool.size()
	_footstep_sounds_played[index] += 1
	voice.stream = load(clip_path)
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 if surface.is_empty() else FootstepSound.pitch_scale_for(randf())
	voice.play(FootstepSound.offset_for(surface, randf()))

	var cap := max_seconds
	if cap <= 0.0 and FootstepSound.is_walking_bed(surface):
		cap = FootstepSound.STEP_WINDOW_SECONDS
	# is_inside_tree, not an assumption: a capped sound needs a real tree to
	# get a timer from, and a bed step asks for one on EVERY step rather
	# than once in a while like a mushroom crush -- so a caller playing
	# before the built root is added stays silent about it instead of
	# erroring on every stride.
	if cap > 0.0 and voice.is_inside_tree():
		voice.get_tree().create_timer(cap).timeout.connect(
			_stop_if_still_the_same_sound.bind(index, _footstep_sounds_played[index])
		)
	return voice


## Closes a sound's own window, and only its own. The pool recycles, so by
## the time a window's timer goes off the voice may already be playing a
## LATER sound -- whose window is its own business and typically has most
## of itself still to run. Stopping it there would cut a live step off after
## a fraction of a step, which is precisely the mid-ring truncation the
## window exists to remove.
func _stop_if_still_the_same_sound(index: int, sounds_played_then: int) -> void:
	if _footstep_sounds_played[index] != sounds_played_then:
		return
	_footstep_pool[index].stop()


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
