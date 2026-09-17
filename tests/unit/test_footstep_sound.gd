extends GutTest

## Pure surface-classification + clip lookup for footstep/interaction SFX
## (see docs/concept/creature_and_footstep_audio.md). Reuses the SAME real
## biome/snow/underwater inputs EarthChunkManager.footstep_surface_for
## already computes for the VISUAL footprint sprite -- never re-derives
## them -- but keeps its own, WIDER surface classification: the footprint
## sprite only has art for 4 surfaces and silently draws nothing for the
## other 3 biomes (a correct visual scope cut), which would be a wrong cut
## for sound -- "we need footsteps" (reported live) means every biome
## should make SOME sound.

const FootstepSound = preload("res://src/audio/footstep_sound.gd")


func test_forest_biome_gets_the_forest_surface():
	assert_eq(FootstepSound.surface_for("forest", false, false), "forest")


func test_rainforest_shares_the_forest_surface_as_a_named_simplification():
	assert_eq(FootstepSound.surface_for("rainforest", false, false), "forest")


func test_grassland_biome_gets_the_grass_surface():
	assert_eq(FootstepSound.surface_for("grassland", false, false), "grass")


func test_desert_biome_gets_the_sand_surface():
	assert_eq(FootstepSound.surface_for("desert", false, false), "sand")


func test_tundra_and_mountain_biomes_get_the_rock_surface():
	assert_eq(FootstepSound.surface_for("tundra", false, false), "rock")
	assert_eq(FootstepSound.surface_for("mountain", false, false), "rock")


func test_an_unlisted_biome_falls_back_to_default_rather_than_silence():
	assert_eq(FootstepSound.surface_for("ocean", false, false), "default")


func test_snow_lying_wins_over_the_biome_surface():
	assert_eq(FootstepSound.surface_for("forest", true, false), "snow")


func test_underwater_wins_over_the_biome_surface_but_not_over_snow():
	assert_eq(FootstepSound.surface_for("grassland", false, true), "underwater")
	assert_eq(
		FootstepSound.surface_for("grassland", true, true), "snow",
		"mirrors EarthChunkManager.footstep_surface_for's own priority: snow checked first"
	)


# -- what the cell is actually MADE OF, when that is not the biome's own ---
# -- ground (see GroundImprint.material_underfoot, the same answer the -----
# -- VISUAL footprint gate already reads) -- reported live: "walking over --
# -- cobblestone streets should not leave footprints", whose sibling gap ---
# -- was that the same street still SOUNDED like the grass beside it -------

func test_a_paved_cell_sounds_like_rock_not_like_the_biome_under_it():
	assert_eq(FootstepSound.surface_for("grassland", false, false, "stone"), "rock")
	assert_eq(FootstepSound.surface_for("forest", false, false, "stone"), "rock")


## A built floor is not the ground outside it either -- the same one rule,
## reaching the same materials the print gate already reaches.
func test_a_built_wooden_floor_stops_sounding_like_the_ground_outside_it():
	assert_eq(FootstepSound.surface_for("grassland", false, false, "timber"), "wood")
	assert_eq(FootstepSound.surface_for("grassland", false, false, "wood"), "wood")


## Ordinary ground is still the BIOME's job: "soil" is not a surface of its
## own here, it is the absence of anything laid on top, so grassland still
## sounds like grass and desert still sounds like sand.
func test_plain_soil_still_takes_its_sound_from_the_biome():
	assert_eq(FootstepSound.surface_for("grassland", false, false, "soil"), "grass")
	assert_eq(FootstepSound.surface_for("desert", false, false, "soil"), "sand")
	assert_eq(FootstepSound.surface_for("forest", false, false, "soil"), "forest")


## Snow and standing water lie ON TOP of a street, so they keep the
## priority they already had -- the same order EarthChunkManager.
## footstep_surface_for and GroundImprint.material_underfoot both use.
func test_snow_and_water_still_win_over_whatever_is_paved_underneath():
	assert_eq(FootstepSound.surface_for("grassland", true, false, "stone"), "snow")
	assert_eq(FootstepSound.surface_for("grassland", false, true, "stone"), "underwater")


## Every pre-existing 3-arg call site across the whole project must keep
## resolving to exactly today's answer.
func test_the_material_argument_defaults_to_leaving_every_caller_unchanged():
	assert_eq(FootstepSound.surface_for("grassland", false, false), "grass")
	assert_eq(FootstepSound.surface_for("tundra", false, false), "rock")
	assert_eq(FootstepSound.surface_for("grassland", false, false, ""), "grass")


func test_every_surface_key_resolves_to_a_real_non_empty_clip_path():
	for surface in ["grass", "forest", "snow", "underwater", "sand", "rock", "wood", "default"]:
		var path: String = FootstepSound.clip_path_for(surface)
		assert_true(path.begins_with("res://"), "%s should map to a real resource path" % surface)


func test_an_unknown_surface_falls_back_to_the_default_clip():
	assert_eq(FootstepSound.clip_path_for("lava"), FootstepSound.clip_path_for("default"))


## Reported live: "so river wading should be used for 'underwater walks'"
## -- a real, distinct water sound, not the same generic dry-land walking
## clip every other unsourced surface shares. Reuses river.ogg (the
## ambient river-proximity layer's own real flowing-water recording, see
## docs/concept/soundscape.md) rather than a second, separately-licensed
## file -- the same water, the same real reason to be heard, whether it's
## the continuous bed nearby or the one-shot underfoot when you're
## actually standing in it.
func test_underwater_gets_a_real_distinct_water_clip_not_the_default():
	var path := FootstepSound.clip_path_for("underwater")
	assert_ne(path, FootstepSound.clip_path_for("default"))
	assert_true(path.begins_with("res://"))


## Requested directly ("find a styrofoam crushing sound and use it for the
## mushroom crushing sound") once a real Wikimedia Commons search for a
## genuine mushroom squish/splat came up empty (see MUSHROOM_CRUSH_CLIP_
## PATH's own doc comment) -- a deliberate, named Foley stand-in, not a
## silent gap anymore. Pinned to the real sourced path, not just "non-empty",
## so a future accidental revert back to "" fails loudly here.
func test_mushroom_crush_clip_path_points_at_the_real_sourced_recording():
	assert_eq(
		FootstepSound.MUSHROOM_CRUSH_CLIP_PATH, "res://assets/audio/footsteps/mushroom_crush.mp3"
	)


## "It sounds like a drum, not like walking on grass" (reported live) --
## grass was silently sharing the generic default.ogg recording, which this
## pins against regressing back to. A real grass-footstep recording now
## exists (see CREDITS.md: a genuine Freesound field recording, rehosted
## ungated on OpenGameArt.org -- both Wikimedia Commons and Freesound.org's
## own direct downloads were real dead ends, and a Pixabay candidate turned
## out to be login/CAPTCHA-gated in practice). Pinned to the real sourced
## path, not just "non-default", mirroring the mushroom-crush test above --
## the current convention in this file now that both departures from the
## Commons-only pattern are real, named sources rather than a gap.
func test_grass_clip_path_points_at_the_real_sourced_recording():
	assert_eq(FootstepSound.clip_path_for("grass"), "res://assets/audio/footsteps/grass.ogg")


# -- per-surface volume: distinct sourced clips were never level-matched --

## Reported live: "The grass footsteps are way too loud... can you make
## them fainter?" Real audio-editing tooling to re-normalize the source
## recording's own level isn't available in this environment (the same
## constraint already named elsewhere in this file for trimming/codec
## fixes) -- corrected in PLAYBACK instead, the same "cap it in code, not
## the asset" shape MUSHROOM_CRUSH_MAX_DURATION_SECONDS already
## established for the crush sound's own length.
func test_grass_footsteps_play_quieter_than_the_default_volume():
	assert_lt(FootstepSound.volume_db_for("grass"), 0.0)


## Every OTHER surface's clip was sourced from the same two places
## (Wikimedia Commons, Pixabay) at a level nobody has reported as
## mismatched -- only grass gets an adjustment; everything else,
## including an unrecognized surface, stays at the plain default (0dB,
## i.e. unchanged) rather than silently drifting too.
func test_every_other_surface_plays_at_the_default_volume():
	for surface in ["snow", "forest", "underwater", "default", "sand", "rock", "lava"]:
		assert_eq(FootstepSound.volume_db_for(surface), 0.0, surface)


# -- a long recording is not a footstep ------------------------------------
#
# Reported live: "Can you find better sounds for the footsteps on every
# terrain? They sound weak and not natural".
#
# Measured before changing anything (tools/probe_footstep_levels.gd), and the
# lengths were the whole explanation: a footstep one-shot is ~0.2-0.5s, and
# only grass.ogg is one. forest_twigs.ogg is 41.67s, snow.mp3 13.72s,
# default.ogg 3.64s -- long recordings of somebody walking continuously, and
# every step played them from 0.0. So each step was the same fraction of the
# same run-in, at the same pitch, identically, forever: quiet where the
# recording had not reached a real impact yet ("weak"), and mechanically
# identical when it had ("not natural").
#
# The clips do not need replacing for that. A long recording of walking is
# full of real, varied footsteps -- it just has to be READ as one step at a
# time.


func test_a_long_recording_is_treated_as_a_bed_of_many_steps():
	assert_true(FootstepSound.is_walking_bed("forest"), "41s of walking is not one step")
	assert_true(FootstepSound.is_walking_bed("snow"))
	assert_true(FootstepSound.is_walking_bed("default"))


func test_a_real_one_shot_is_left_alone():
	assert_false(FootstepSound.is_walking_bed("grass"), "a quarter-second clip IS one step")


## A bed is read at a different place every step, which is where the variety
## comes from: the recording already holds dozens of real, different steps.
func test_every_step_into_a_bed_starts_somewhere_else():
	var first := FootstepSound.offset_for("forest", 0.0)
	var middle := FootstepSound.offset_for("forest", 0.5)
	var last := FootstepSound.offset_for("forest", 1.0)
	assert_almost_eq(first, 0.0, 0.0001, "the first roll starts at the top")
	assert_gt(middle, first)
	assert_gt(last, middle)


## ...and never so late that the window would run off the end of the clip,
## which would be a step that fades into nothing.
func test_a_step_never_starts_so_late_that_it_runs_out_of_recording():
	for surface in ["forest", "snow", "default"]:
		var latest: float = FootstepSound.offset_for(surface, 1.0)
		assert_lte(
			latest + FootstepSound.STEP_WINDOW_SECONDS,
			FootstepSound.CLIP_LENGTH_SECONDS[surface] + 0.0001,
			"%s's last step runs off the end" % surface
		)


func test_a_one_shot_always_starts_at_its_own_beginning():
	for roll in [0.0, 0.5, 1.0]:
		assert_almost_eq(FootstepSound.offset_for("grass", roll), 0.0, 0.0001)


## The other half of "not natural": the same sample at the same pitch every
## step reads as a machine. A few percent either way is the standard cure.
func test_no_two_steps_land_on_the_same_pitch():
	var low := FootstepSound.pitch_scale_for(0.0)
	var high := FootstepSound.pitch_scale_for(1.0)
	assert_lt(low, 1.0, "the low roll should pitch down")
	assert_gt(high, 1.0, "the high roll should pitch up")
	assert_almost_eq(FootstepSound.pitch_scale_for(0.5), 1.0, 0.0001, "the middle is unaltered")


## Small: a footstep that swings a whole semitone reads as a different
## person's boot, not as the same boot on a different patch of ground.
func test_the_pitch_swing_stays_subtle():
	assert_lt(FootstepSound.PITCH_VARIATION, 0.12, "more than this is a different boot")
	assert_gt(FootstepSound.PITCH_VARIATION, 0.01, "less than this is inaudible")


## A step is allowed to sound for about as long as a real one does. Longer
## and the tails of four voices pile into a crowd walking behind you; that
## overlap is what the pool's own recycling used to cut off mid-ring.
func test_one_step_sounds_for_about_as_long_as_a_step():
	assert_gte(FootstepSound.STEP_WINDOW_SECONDS, 0.2)
	assert_lte(FootstepSound.STEP_WINDOW_SECONDS, 0.6)


## The lengths are MEASURED off the real files every run, not trusted: the
## offsets above are derived from them, so a swapped clip that nobody
## re-measured would silently start reading steps off the end of it.
func test_the_pinned_clip_lengths_are_the_real_files_own():
	for surface in FootstepSound.CLIP_LENGTH_SECONDS:
		var stream = load(FootstepSound.clip_path_for(surface))
		assert_not_null(stream, surface)
		assert_almost_eq(
			stream.get_length(), float(FootstepSound.CLIP_LENGTH_SECONDS[surface]), 0.05,
			"%s is not the length it is pinned at -- re-measure with tools/probe_footstep_levels.gd" % surface
		)
