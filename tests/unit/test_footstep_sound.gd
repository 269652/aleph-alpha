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
		var path: String = FootstepSound.step_clip_path_for(surface, 0.0)
		assert_true(path.begins_with("res://"), "%s should map to a real resource path" % surface)


func test_an_unknown_surface_falls_back_to_the_one_general_walking_recording():
	assert_eq(FootstepSound.step_clip_path_for("lava", 0.0), FootstepSound.FALLBACK_CLIP_PATH)


## Reported live: "so river wading should be used for 'underwater walks'"
## -- a real, distinct water sound, not the same generic dry-land walking
## clip every other unsourced surface shared. That was answered at the time
## by pointing underwater at `river.ogg`, the ambient river-proximity
## layer's own flowing-water recording, because it was the only water in
## the project. It now plays real recordings of feet going INTO water
## instead (see CREDITS.md) -- which is what wading actually is, where
## `river.ogg` is a river heard from the bank. `river.ogg` keeps its
## ambient job untouched.
func test_underwater_gets_real_water_steps_not_the_general_walking_recording():
	for path in FootstepSound.step_variants_for("underwater"):
		assert_ne(path, FootstepSound.FALLBACK_CLIP_PATH)
		assert_true(path.begins_with("res://"))
	assert_gte(FootstepSound.step_variants_for("underwater").size(), 5)


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
## The pack that recording came from held nine numbered grass variations
## and only the first was ever copied in, because the lookup was one path
## per surface. All nine ship now; `steps/grass_00.ogg` is byte-for-byte
## the file this test used to name.
func test_grass_steps_point_at_the_real_sourced_recordings():
	var pool := FootstepSound.step_variants_for("grass")
	assert_eq(pool.size(), 9, "the pack's nine grass variations")
	for path in pool:
		assert_true(path.begins_with("res://assets/audio/footsteps/steps/grass_"), path)


# -- per-surface volume: distinct sourced clips were never level-matched --

## Reported live: "The grass footsteps are way too loud... can you make
## them fainter?" -12.0 dB was the answer then, arrived at by ear. Kept as
## its own test because the pipeline, decoding grass's nine clips and
## solving for the level every OTHER surface is also matched to, landed on
## -12.0 for grass independently -- so this is now a check that a measured
## result still agrees with the one a person heard.
func test_grass_footsteps_play_quieter_than_the_default_volume():
	assert_almost_eq(FootstepSound.volume_db_for("grass"), -12.0, 0.05)


## A surface nobody has recorded plays at the plain default (0dB) rather
## than silently drifting quieter or louder. Every REAL surface has a
## measured gain -- see test_every_surfaces_volume_is_the_gain_the_pipeline_
## measured, which is what pins those.
func test_an_unrecognized_surface_plays_at_the_default_volume():
	assert_eq(FootstepSound.volume_db_for("lava"), 0.0)


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
	assert_true(
		FootstepSound.is_walking_bed(FootstepSound.FALLBACK_CLIP_PATH),
		"3.64s of walking is not one step"
	)


func test_a_real_one_shot_is_left_alone():
	assert_false(
		FootstepSound.is_walking_bed("res://assets/audio/footsteps/steps/grass_00.ogg"),
		"a quarter-second clip IS one step"
	)


## A bed is read at a different place every step, which is where the variety
## comes from: the recording already holds dozens of real, different steps.
func test_every_step_into_a_bed_starts_somewhere_else():
	var bed := FootstepSound.FALLBACK_CLIP_PATH
	var first := FootstepSound.offset_for(bed, 0.0)
	var middle := FootstepSound.offset_for(bed, 0.5)
	var last := FootstepSound.offset_for(bed, 1.0)
	assert_almost_eq(first, 0.0, 0.0001, "the first roll starts at the top")
	assert_gt(middle, first)
	assert_gt(last, middle)


## ...and never so late that the window would run off the end of the clip,
## which would be a step that fades into nothing.
func test_a_step_never_starts_so_late_that_it_runs_out_of_recording():
	for clip_path in FootstepSound.CLIP_LENGTH_SECONDS:
		var latest: float = FootstepSound.offset_for(clip_path, 1.0)
		assert_lte(
			latest + FootstepSound.STEP_WINDOW_SECONDS,
			float(FootstepSound.CLIP_LENGTH_SECONDS[clip_path]) + 0.0001,
			"%s's last step runs off the end" % clip_path
		)


func test_a_one_shot_always_starts_at_its_own_beginning():
	for roll in [0.0, 0.5, 1.0]:
		var one_shot := "res://assets/audio/footsteps/steps/grass_00.ogg"
		assert_almost_eq(FootstepSound.offset_for(one_shot, roll), 0.0, 0.0001)


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
	for clip_path in FootstepSound.CLIP_LENGTH_SECONDS:
		var stream = load(clip_path)
		assert_not_null(stream, clip_path)
		assert_almost_eq(
			stream.get_length(), float(FootstepSound.CLIP_LENGTH_SECONDS[clip_path]), 0.05,
			"%s is not the length it is pinned at -- re-run tools/prepare_footstep_oneshots.py" % clip_path
		)


# -- a pool of real steps per surface --------------------------------------
#
# The other half of "find better sounds for the footsteps on every terrain".
# The clips this file used to reach for were recordings of somebody WALKING,
# one per surface, and their levels were 35 dB apart end to end:
#
#     grass.ogg          rms -12.59 dBFS   (a real one-shot)
#     snow.mp3           rms -38.42 dBFS
#     forest_twigs.ogg   rms -41.26 dBFS
#     default.ogg        rms -47.63 dBFS
#
# So grass was reported "way too loud" and got -12 dB -- a third of the way
# across a 35 dB gap -- while everything else stayed "weak". Every surface
# now has several real, isolated footstep one-shots instead, measured and
# level-matched by tools/prepare_footstep_oneshots.py, which writes what it
# measured into steps/levels.json. These tests bind this file to that
# measurement: the numbers below are never eyeballed, and the code cannot
# drift away from the files it is describing.

const LEVELS_MANIFEST_PATH := "res://assets/audio/footsteps/steps/levels.json"

## Every surface the game can actually put underfoot -- both halves of
## surface_for's own answer (the biome's ground and anything laid on top of
## it), plus the fallback, so "every terrain" is checked as literally as the
## ask was phrased.
const EVERY_REAL_SURFACE := [
	"grass", "forest", "sand", "rock", "wood", "snow", "underwater", "default"
]


func _levels() -> Dictionary:
	var file := FileAccess.open(LEVELS_MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file, "no levels manifest -- run tools/prepare_footstep_oneshots.py")
	return JSON.parse_string(file.get_as_text())


func test_every_surface_has_a_pool_of_real_steps_not_one_recording():
	for surface in EVERY_REAL_SURFACE:
		assert_gte(
			FootstepSound.step_variants_for(surface).size(), 5,
			"%s has too few real steps to stop sounding repetitive" % surface
		)


func test_every_step_a_surface_offers_is_a_real_loadable_file():
	for surface in EVERY_REAL_SURFACE:
		for path in FootstepSound.step_variants_for(surface):
			assert_true(ResourceLoader.exists(path), path)
			assert_not_null(load(path), path)


## Re-measured off the real files every run, like the bed lengths above: a
## variant that is seconds long is a recording of walking that slipped into
## the pool, and the whole point of the pool is that it is not one.
func test_every_step_is_the_length_of_one_step():
	for surface in EVERY_REAL_SURFACE:
		for path in FootstepSound.step_variants_for(surface):
			var stream = load(path)
			var length: float = stream.get_length()
			assert_gt(length, 0.05, "%s is too short to be a step" % path)
			assert_lt(length, 0.8, "%s is a recording of walking, not a step" % path)


## ...and so is never read as a window into anything -- it IS the step.
func test_a_real_step_is_never_treated_as_a_bed():
	for surface in EVERY_REAL_SURFACE:
		for path in FootstepSound.step_variants_for(surface):
			assert_false(FootstepSound.is_walking_bed(path), path)
			assert_almost_eq(FootstepSound.offset_for(path, 1.0), 0.0, 0.0001, path)


## A surface with nothing sourced still makes a sound: the generic walking
## recording, read one window at a time, exactly as before the pools existed.
## This is what keeps that fallback load-bearing rather than decoration.
func test_a_surface_with_no_pool_of_its_own_still_falls_back_to_the_bed():
	assert_eq(FootstepSound.step_variants_for("lava"), [])
	var fallback := FootstepSound.step_clip_path_for("lava", 0.5)
	assert_true(FootstepSound.is_walking_bed(fallback), "the fallback must still be windowed")
	assert_gt(FootstepSound.offset_for(fallback, 1.0), 0.0)


func test_consecutive_steps_walk_through_the_whole_pool():
	var seen: Dictionary = {}
	var pool := FootstepSound.step_variants_for("grass")
	for i in 200:
		seen[FootstepSound.step_clip_path_for("grass", float(i) / 200.0)] = true
	assert_eq(seen.size(), pool.size(), "some of the pool is unreachable")


func test_a_roll_at_either_extreme_still_lands_inside_the_pool():
	var pool := FootstepSound.step_variants_for("snow")
	for roll in [-1.0, 0.0, 0.999, 1.0, 2.0]:
		assert_true(pool.has(FootstepSound.step_clip_path_for("snow", roll)), str(roll))


# -- the levels are measured, never guessed --------------------------------


## The one binding that matters: the gain this file applies per surface is
## the gain the pipeline MEASURED, not a number anybody chose. Godot cannot
## read raw samples out of a compressed stream, so the measurement itself
## lives in the manifest the tool writes -- and this pins the code to it, so
## re-running the tool on swapped clips cannot silently leave stale dB
## behind in the source.
func test_every_surfaces_volume_is_the_gain_the_pipeline_measured():
	var surfaces: Dictionary = _levels()["surfaces"]
	for surface in surfaces:
		assert_almost_eq(
			FootstepSound.volume_db_for(surface), float(surfaces[surface]["gain_db"]), 0.001,
			"%s's volume drifted from the measurement" % surface
		)


## What the whole exercise was for. 35 dB apart is why one surface was "way
## too loud" and the rest "weak"; no surface may sit more than a few dB off
## its neighbours now.
##
## **Corrected 2026-09-19.** This measured `achieved_rms_dbfs`, and passed,
## while pavement was genuinely ~10 dB louder than grass to listen to --
## reported live as *"pavement footsteps are way too loud ..."*. RMS is
## simply not loudness for an impulsive sound: at equal RMS, rock's peaks
## sit 8.4 dB above grass's. So this now measures what it always meant to.
##
## The RMS spread is deliberately WIDE now (12.74 dB) and that is the
## correct outcome, not a regression: surfaces whose energy is shaped
## differently must sit at different RMS to sound equally loud.
func test_no_surface_is_dramatically_louder_than_another():
	var surfaces: Dictionary = _levels()["surfaces"]
	var quietest := 999.0
	var loudest := -999.0
	for surface in surfaces:
		var level := float(surfaces[surface]["achieved_lufs"])
		quietest = minf(quietest, level)
		loudest = maxf(loudest, level)
	assert_lt(loudest - quietest, 1.5, "the surfaces are not loudness-matched")


## And nothing was pushed into clipping to get there -- there has to be room
## left for the pitch and volume the player applies on top, per step.
func test_no_surface_was_pushed_into_clipping():
	var manifest := _levels()
	for surface in manifest["surfaces"]:
		assert_lte(
			float(manifest["surfaces"][surface]["achieved_peak_dbfs"]),
			float(manifest["peak_ceiling_dbfs"]) + 0.001, surface
		)


## Nothing ships unreferenced: a clip in the directory that no surface names
## is either a pool that was renamed out from under the code, or dead weight
## in the repository.
func test_no_shipped_step_file_is_unreachable_from_any_surface():
	var referenced: Dictionary = {}
	for surface in EVERY_REAL_SURFACE:
		for path in FootstepSound.step_variants_for(surface):
			referenced[path.get_file()] = true
	var directory := DirAccess.open("res://assets/audio/footsteps/steps")
	assert_not_null(directory)
	for name in directory.get_files():
		if not name.ends_with(".ogg"):
			continue
		assert_true(referenced.has(name), "%s is shipped but no surface plays it" % name)


## Reported live: *"pavement footsteps are way too loud ..."*.
##
## test_no_surface_is_dramatically_louder_than_another above says the
## surfaces ARE level-matched, and it is right about what it measures: every
## pool's RMS lands within 2.5 dB of the same target. The complaint was
## still correct, because **RMS is not loudness for an impulsive sound.** A
## footstep is a transient, and a hard surface packs its energy into a much
## sharper one: at equal RMS, rock's peaks sit 8.4 dB above grass's (crest
## factor 20.64 dB against 12.28 dB). So pavement measured matched and hit
## the ear far louder.
##
## The metric loudness is actually defined by is ITU-R BS.1770's K-weighted
## mean square -- the same one EBU R128 broadcast normalisation uses, and
## the standard answer to exactly this failure of RMS. The pipeline now
## measures it per pool and matches on it, anchored where it was already
## anchored: on grass, the one footstep level signed off by ear.
##
## Under the RMS match, applying each shipped gain put grass at -33.65 LUFS
## and rock at -23.80 -- pavement was running 9.85 dB hot, and sand 13.5.
func test_every_surface_carries_a_real_loudness_measurement():
	var surfaces: Dictionary = _levels()["surfaces"]
	for surface in surfaces:
		assert_true(
			surfaces[surface].has("achieved_lufs"),
			"%s has no K-weighted measurement to be matched on" % surface
		)
		assert_true(
			surfaces[surface].has("raw_lufs"),
			"%s does not record what it measured before its gain" % surface
		)


## And pavement specifically -- the surface that was reported -- really did
## come down. It sat at gain -3.3 under the RMS match; anything near that
## again means the loudness match has been undone.
func test_pavement_is_no_longer_ten_decibels_hot():
	assert_lt(
		FootstepSound.volume_db_for("rock"), -10.0,
		"stone/pavement plays the rock pool, which was 9.85 dB over grass"
	)


## Grass is the anchor and must not move: it is the one level a person
## actually listened to and accepted, and every other surface is matched to
## it rather than to a number chosen here.
func test_grass_keeps_the_level_that_was_signed_off_by_ear():
	assert_almost_eq(FootstepSound.volume_db_for("grass"), -12.0, 0.001)
