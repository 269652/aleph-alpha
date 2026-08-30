extends GutTest

## The continuous streak-phase field -- see river_phase_field.gd and
## docs/concept/rivers.md's "Flow rendering" section.

const RiverPhaseField = preload("res://src/world/river_phase_field.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")


# -- the anti-aliasing guarantee --------------------------------------------
#
# The old shader's temporal frequency was flow_speed * streak_frequency =
# 32 * 0.12 = 3.84 Hz. At the measured ~7 fps floor that is 0.549
# cycles/frame -- past the 0.5 Nyquist limit -- so the fastest rivers
# visibly flowed BACKWARDS. One global rate is what makes that impossible.

func test_the_streak_rate_cannot_alias_even_at_the_worst_measured_frame_rate():
	const WORST_MEASURED_FPS := 7.0
	var cycles_per_frame := RiverPhaseField.STREAK_RATE_HZ / WORST_MEASURED_FPS
	assert_lt(
		cycles_per_frame, 0.5,
		"%f cycles/frame is past Nyquist -- the river would flow backwards" % cycles_per_frame
	)


## The streak is pow(max(sin,0), 4), whose harmonics reach ~3x the
## fundamental. Those must stay under Nyquist too, or the pattern shimmers
## even when the fundamental is safe.
func test_even_the_streaks_harmonics_stay_under_nyquist():
	const WORST_MEASURED_FPS := 7.0
	const HARMONIC := 3.0
	assert_lt((RiverPhaseField.STREAK_RATE_HZ * HARMONIC) / WORST_MEASURED_FPS, 0.5)


# -- continuity: the whole point --------------------------------------------

func test_phase_grows_smoothly_along_a_course():
	var previous := -1.0
	for step in 21:
		var phase := RiverPhaseField.phase_cycles(float(step) / 20.0, 30.0)
		assert_gte(phase, previous, "phase must advance monotonically downstream")
		previous = phase


## The real continuity claim: two neighbouring points on a course differ in
## phase by exactly the number of wavelengths between them -- never by an
## arbitrary reset. Stepping one tile must always advance the phase by
## exactly 1/STREAK_WAVELENGTH_TILES cycles, anywhere on the course.
func test_one_tile_of_course_always_advances_the_phase_by_the_same_amount():
	var length := 40.0
	var expected := 1.0 / RiverPhaseField.STREAK_WAVELENGTH_TILES
	for start_tile in [0.0, 7.0, 19.0, 33.0]:
		var a := RiverPhaseField.phase_cycles(start_tile / length, length)
		var b := RiverPhaseField.phase_cycles((start_tile + 1.0) / length, length)
		assert_almost_eq(b - a, expected, 0.0001)


## Contrast with what the OLD construction did. Reproduced here so the
## regression this field prevents is pinned rather than only described: at
## real world scale, a one-bin direction change flipped the phase by tens of
## thousands of cycles, i.e. an arbitrary reset.
func test_the_old_world_projection_really_did_reset_the_phase_arbitrarily():
	const OLD_STREAK_FREQUENCY := 0.12
	var world_extent := float(EarthChunkGenerator.WORLD_WIDTH_TILES) * 16.0
	var one_bin_chord := 2.0 * sin(deg_to_rad(360.0 / 16.0) * 0.5)
	var phase_jump := world_extent * one_bin_chord * OLD_STREAK_FREQUENCY
	assert_gt(
		phase_jump, 1000.0,
		"the old projection jumped %f cycles at a bin change -- an arbitrary reset" % phase_jump
	)


# -- wrapped phase ----------------------------------------------------------

func test_wrapped_phase_always_stays_in_unit_range():
	for fraction in [0.0, 0.13, 0.5, 0.77, 1.0]:
		assert_between(RiverPhaseField.wrapped_phase(fraction, 37.0), 0.0, 1.0)


func test_wrapped_phase_is_the_fractional_part_of_the_real_phase():
	var full := RiverPhaseField.phase_cycles(0.4, 25.0)
	assert_almost_eq(RiverPhaseField.wrapped_phase(0.4, 25.0), fposmod(full, 1.0), 0.0001)


# -- degenerate inputs ------------------------------------------------------

func test_a_zero_length_course_has_no_phase_rather_than_dividing_by_zero():
	assert_eq(RiverPhaseField.phase_cycles(0.5, 0.0), 0.0)


# -- real course lengths ----------------------------------------------------

func test_every_curated_river_has_a_real_course_length():
	for river_name in RiverCatalog.RIVERS:
		var length := RiverPhaseField.course_length_tiles(
			river_name, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		assert_gt(length, 0.0, "%s has no measurable course" % river_name)


func test_an_unknown_river_has_no_course_length():
	assert_eq(
		RiverPhaseField.course_length_tiles(
			"Amazon", EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		),
		0.0
	)


## A real sanity check on the wavelength: streaks must be dense enough to
## read as flowing texture at the game's own tile size, not so sparse that a
## whole river shows one band.
func test_a_real_river_carries_many_streaks_along_its_length():
	var dreisam := RiverPhaseField.course_length_tiles(
		"Dreisam", EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	var cycles := RiverPhaseField.phase_cycles(1.0, dreisam)
	assert_gt(cycles, 20.0, "even the smallest river should carry many streaks")
