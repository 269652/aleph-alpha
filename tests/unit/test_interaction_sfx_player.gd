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
	var voice := player.play_footstep("forest")
	assert_not_null(voice, "expected play_footstep to start a voice")
	assert_true(voice.playing)
	assert_true(
		FootstepSound.step_variants_for("forest").has(voice.stream.resource_path),
		"a forest step played %s" % voice.stream.resource_path
	)


func test_play_footstep_with_an_unheard_of_surface_still_plays_the_default_clip():
	add_child_autofree(player.build())
	player.play_footstep("lava")
	var playing_voice := _find_playing_voice(FootstepSound.FALLBACK_CLIP_PATH)
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
	var voice := player.play_footstep("grass")
	assert_not_null(voice)
	# almost_eq, not eq: volume_db is a 32-bit engine property, and these
	# gains are MEASURED by tools/prepare_footstep_oneshots.py rather than
	# chosen, so most of them are not exactly representable -- snow's 1.1
	# reads back as 1.10000002384186 and failed a plain equality.
	assert_almost_eq(voice.volume_db, FootstepSound.volume_db_for("grass"), 0.0001)


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
	var voice := player.play_footstep("snow")
	assert_not_null(voice)
	assert_almost_eq(voice.volume_db, FootstepSound.volume_db_for("snow"), 0.0001)
	assert_ne(
		FootstepSound.volume_db_for("snow"), FootstepSound.volume_db_for("grass"),
		"the premise: the two surfaces must actually want different volumes"
	)


## Same reuse hazard, the other direction: a mushroom crush landing on a
## voice grass just left quiet must still play at its OWN level.
##
## The expected number moved (2026-09-20, *"can you make the mushroom crush
## sound louder"*) and the test is kept rather than deleted, because what it
## guards did not move: the pool recycles voices, so a crush must set its own
## volume unconditionally instead of taking whatever the last footstep left
## behind. It used to be a flat 0 dB -- which was itself the bug, the one
## sound here that was never matched to the shared target -- and is now
## FootstepSound.MUSHROOM_CRUSH_VOLUME_DB.
func test_play_mushroom_crush_does_not_inherit_a_previous_surfaces_quieter_volume():
	add_child_autofree(player.build())
	for i in InteractionSfxPlayer.FOOTSTEP_POOL_SIZE:
		player.play_footstep("grass")
	player.play_mushroom_crush()
	var voice := _find_playing_voice(FootstepSound.MUSHROOM_CRUSH_CLIP_PATH)
	assert_not_null(voice)
	assert_almost_eq(
		voice.volume_db, FootstepSound.MUSHROOM_CRUSH_VOLUME_DB, 0.01,
		"must not inherit grass's quieter volume from a reused pool voice"
	)
	assert_ne(
		FootstepSound.volume_db_for("grass"), FootstepSound.MUSHROOM_CRUSH_VOLUME_DB,
		"the premise: grass and a crush must actually want different volumes"
	)


## The report itself, at the one place it is finally audible: a crush is
## played at the gain the pipeline measured for it, not at the flat 0 dB it
## used to take by default.
func test_a_crush_is_played_at_its_own_measured_gain_rather_than_flat_zero():
	add_child_autofree(player.build())
	var voice := player.play_mushroom_crush()
	assert_not_null(voice)
	assert_almost_eq(voice.volume_db, FootstepSound.MUSHROOM_CRUSH_VOLUME_DB, 0.01)
	assert_gt(voice.volume_db, 0.0, "the measured correction is upward -- that is the report")


## ...and it starts at a real crush. A gain alone would have made 0.3s of
## the recording's room tone louder, which is why the offset is half of this
## fix: see FootstepSound.MUSHROOM_CRUSH_OFFSET_SECONDS.
func test_a_crush_starts_playing_at_one_of_the_measured_crushes():
	add_child_autofree(player.build())
	var started := {}
	for i in 40:
		var voice := player.play_mushroom_crush()
		assert_not_null(voice)
		var position := voice.get_playback_position()
		var nearest := -1.0
		for offset in FootstepSound.MUSHROOM_CRUSH_OFFSET_SECONDS:
			if nearest < 0.0 or absf(offset - position) < absf(nearest - position):
				nearest = offset
		assert_almost_eq(
			position, nearest, 0.05,
			"a crush started at %.3fs, which is not one of the measured crushes" % position
		)
		started[nearest] = true
	assert_gt(started.size(), 1, "forty crushes must not all be the same one")


func _find_playing_voice(expected_clip_path: String) -> AudioStreamPlayer:
	for voice in player._footstep_pool:
		if voice.playing and voice.stream != null and voice.stream.resource_path == expected_clip_path:
			return voice
	return null


# -- one step out of a recording of many ------------------------------------
#
# The wiring half of "they sound weak and not natural" (see
# FootstepSound's own "one step out of a recording of many"): an offset and
# a pitch nothing applies changes nothing about how a step sounds.


func test_a_step_into_a_walking_bed_starts_somewhere_other_than_the_top():
	add_child_autofree(player.build())
	var starts: Dictionary = {}
	for _step in 24:
		var voice := player._play_footstep_clip(
			FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava"
		)
		assert_not_null(voice)
		starts[snappedf(voice.get_playback_position(), 0.01)] = true
	assert_gt(
		starts.size(), 1,
		"every step into the bed started in the same place, which made them identical"
	)


## A real one-shot is played whole, from its own beginning: grass.ogg IS one
## step, and starting it late would clip the only step it has.
func test_a_one_shot_still_starts_at_its_own_beginning():
	add_child_autofree(player.build())
	for _step in 8:
		var voice := player._play_footstep_clip(
			FootstepSound.step_clip_path_for("grass", 0.0), 0.0, "grass"
		)
		assert_almost_eq(voice.get_playback_position(), 0.0, 0.05)


func test_no_two_steps_land_on_exactly_the_same_pitch():
	add_child_autofree(player.build())
	var pitches: Dictionary = {}
	for _step in 24:
		var voice := player._play_footstep_clip(
			FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava"
		)
		pitches[snappedf(voice.pitch_scale, 0.001)] = true
	assert_gt(pitches.size(), 1, "every step played at the same pitch")


## And the swing stays inside what FootstepSound allows -- a voice is reused
## across surfaces, so a pitch left from a previous call must never ride
## along, exactly like the volume it already sets unconditionally.
func test_every_step_is_pitched_inside_the_allowed_swing():
	add_child_autofree(player.build())
	for _step in 24:
		var voice := player._play_footstep_clip(
			FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava"
		)
		assert_gte(voice.pitch_scale, 1.0 - FootstepSound.PITCH_VARIATION - 0.0001)
		assert_lte(voice.pitch_scale, 1.0 + FootstepSound.PITCH_VARIATION + 0.0001)


## A mushroom crush is its own one-shot and must not be pitch-shifted by
## whatever surface last used the voice -- the same reuse guard the volume
## already has.
func test_a_mushroom_crush_plays_at_its_own_pitch():
	add_child_autofree(player.build())
	for _step in 8:
		player._play_footstep_clip(FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava")
	var voice := player.play_mushroom_crush()
	if voice != null:
		assert_almost_eq(voice.pitch_scale, 1.0, 0.0001, "a crush inherited a footstep's pitch")


## One step is one step. A bed is 41 seconds of somebody walking, so a step
## read out of one has to be CLOSED again -- otherwise the rest of that
## stranger's walk keeps playing under your own next step, four voices deep,
## until the pool's round-robin happens to cut it off. A real wall-clock
## wait, like test_mushroom_crush_stops_itself_after_its_own_max_duration.
func test_a_step_into_a_bed_stops_after_one_steps_worth_of_it():
	add_child_autofree(player.build())
	var voice := player._play_footstep_clip(FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava")
	assert_true(voice.playing, "the premise: it must actually be playing right after the step")

	await wait_seconds(FootstepSound.STEP_WINDOW_SECONDS + 0.15)

	assert_false(voice.playing, "41 seconds of someone else's walk kept playing under the next step")


## ...and a real one-shot is never cut: grass.ogg is already one step, well
## inside the window, and stopping it early would clip its own tail.
func test_a_one_shot_is_left_to_play_itself_out():
	add_child_autofree(player.build())
	var voice := player._play_footstep_clip(FootstepSound.step_clip_path_for("grass", 0.0), 0.0, "grass")
	assert_true(voice.playing)
	assert_lt(
		float(load(FootstepSound.step_clip_path_for("grass", 0.0)).get_length()), FootstepSound.STEP_WINDOW_SECONDS,
		"the premise: a one-shot ends before the window would ever close it"
	)


## Closing the window must close THIS step's window, not whichever step
## happens to hold the voice when the timer goes off. The pool is 4 deep and
## recycles, so a fifth step lands back on voice 0 while voice 0's first
## window is still counting down -- and a timer that just calls stop() would
## cut the new step off after a fraction of its own window.
func test_a_recycled_voice_is_not_cut_short_by_the_previous_steps_window():
	add_child_autofree(player.build())
	for _step in InteractionSfxPlayer.FOOTSTEP_POOL_SIZE:
		player._play_footstep_clip(FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava")

	# Late in the first step's window, but before it closes.
	await wait_seconds(FootstepSound.STEP_WINDOW_SECONDS * 0.8)
	var recycled := player._play_footstep_clip(FootstepSound.FALLBACK_CLIP_PATH, 0.0, "lava")
	assert_true(recycled.playing, "the premise: the recycled voice took the new step")

	# Past the point the FIRST step's window closes, well inside the new one's.
	await wait_seconds(FootstepSound.STEP_WINDOW_SECONDS * 0.4)

	assert_true(recycled.playing, "the previous step's timer cut this step short")


## The whole reason the pools exist: consecutive steps on the SAME ground
## must not be the same recording over and over. Reported live: "they sound
## weak and not natural".
##
## Reads the clip off the voice play_footstep RETURNS, not off whichever
## voice is found playing. An earlier version of this searched the pool for
## a playing voice and failed consistently on one variant -- correctly: in a
## tight loop all four voices are legitimately mid-step, so that search
## reported the lowest-indexed clip still sounding rather than the one this
## step took, and the last clip in a pool could never win it.
func test_consecutive_steps_on_one_surface_do_not_all_play_the_same_recording():
	add_child_autofree(player.build())
	var heard: Dictionary = {}
	for _step in 60:
		var voice := player.play_footstep("grass")
		assert_not_null(voice, "a grass step played nothing")
		heard[voice.stream.resource_path] = true
	assert_gt(
		heard.size(), 1,
		"every grass step played the same file, which is what a single clip per surface did"
	)


## ...and over enough steps it reaches the whole pool, rather than a couple
## of favourites.
func test_enough_steps_reach_every_recording_in_the_pool():
	add_child_autofree(player.build())
	var heard: Dictionary = {}
	for _step in 400:
		heard[player.play_footstep("sand").stream.resource_path] = true
	assert_eq(
		heard.size(), FootstepSound.step_variants_for("sand").size(),
		"some of the sand pool never plays"
	)

# -- the accessor the audio diagnostic reads (see AudioDiagnostics, -------
# -- World._log_audio_diagnostics) ----------------------------------------

func test_the_root_is_not_in_the_tree_until_it_is_really_added():
	var player := InteractionSfxPlayer.new()
	assert_false(player.root_in_tree(), "nothing is built yet")
	var root := player.build()
	assert_false(player.root_in_tree(), "built is not the same as added")
	add_child_autofree(root)
	assert_true(player.root_in_tree())


## Reported live: "Mushroom crush sounds are gone". The clip is 7.5 seconds of
## continuous crinkling styrofoam, and it was never measured into
## FootstepSound.CLIP_LENGTH_SECONDS -- so it read as a one-shot, every crush
## started at 0.0, and the 0.3s cap played the same opening lead-in every
## time, before the performer has touched the styrofoam.
##
## The wiring half of that fix: a crush must actually start somewhere inside
## the recording, and two crushes must not start in the same place. Mirrors
## test_a_step_into_a_walking_bed_starts_somewhere_other_than_the_top exactly.
func test_a_mushroom_crush_starts_somewhere_inside_its_recording():
	add_child_autofree(player.build())
	var starts: Dictionary = {}
	var deepest := 0.0
	for _crush in 24:
		var voice := player.play_mushroom_crush()
		assert_not_null(voice)
		var started := voice.get_playback_position()
		deepest = maxf(deepest, started)
		starts[snappedf(started, 0.01)] = true
	assert_gt(starts.size(), 1, "every crush started in the same place")
	# Not just "not exactly zero" -- playback advances a hair on its own, so
	# that would pass even with every offset pinned at the top. At least one
	# crush must read from genuinely deeper inside the recording than a whole
	# window's worth, which is impossible when the offset is always 0.
	assert_gt(
		deepest, FootstepSound.STEP_WINDOW_SECONDS,
		"no crush read from deeper inside the recording than its own lead-in"
	)
