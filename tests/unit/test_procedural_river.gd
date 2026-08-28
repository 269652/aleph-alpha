extends GutTest

## Stylized procedural river fallback -- see docs/concept/rivers.md's
## "Procedural fallback" section. Deliberately NOT a flow-accumulation
## simulation: a real-elevation gate combined with a seeded noise field's
## zero-contour (winding threads, not blobs -- a well-known cheap
## procedural-content technique).

const ProceduralRiver = preload("res://src/world/procedural_river.gd")

var river: ProceduralRiver

const SEA_LEVEL := 0.5556
const MOUNTAIN_LEVEL := 0.75


func before_each():
	river = ProceduralRiver.new()


# -- passes_elevation_gate ---------------------------------------------------

func test_ocean_elevation_never_passes_the_gate():
	assert_false(river.passes_elevation_gate(SEA_LEVEL - 0.05, SEA_LEVEL, MOUNTAIN_LEVEL))


func test_mountain_elevation_never_passes_the_gate():
	assert_false(river.passes_elevation_gate(MOUNTAIN_LEVEL + 0.05, SEA_LEVEL, MOUNTAIN_LEVEL))
	assert_false(river.passes_elevation_gate(MOUNTAIN_LEVEL, SEA_LEVEL, MOUNTAIN_LEVEL))


func test_low_lying_land_passes_the_gate():
	# Just above sea level -- the lowest real land there is.
	assert_true(river.passes_elevation_gate(SEA_LEVEL + 0.001, SEA_LEVEL, MOUNTAIN_LEVEL))


func test_high_land_just_below_the_mountain_band_does_not_pass():
	# Real rivers don't run along the foot of the highest peaks -- see
	# MAX_ELEVATION_FRACTION's own doc comment.
	assert_false(river.passes_elevation_gate(MOUNTAIN_LEVEL - 0.001, SEA_LEVEL, MOUNTAIN_LEVEL))


# -- is_on_contour ------------------------------------------------------------

func test_a_zero_noise_sample_is_on_the_contour():
	assert_true(river.is_on_contour(0.0))


func test_a_noise_sample_just_inside_the_band_is_on_the_contour():
	assert_true(river.is_on_contour(ProceduralRiver.ISO_BAND * 0.5))
	assert_true(river.is_on_contour(-ProceduralRiver.ISO_BAND * 0.5))


func test_a_noise_sample_outside_the_band_is_not_on_the_contour():
	assert_false(river.is_on_contour(ProceduralRiver.ISO_BAND * 2.0))
	assert_false(river.is_on_contour(-ProceduralRiver.ISO_BAND * 2.0))


func test_a_far_noise_sample_is_never_on_the_contour():
	assert_false(river.is_on_contour(1.0))
	assert_false(river.is_on_contour(-1.0))


# -- is_river_candidate (composition + real noise wiring) --------------------

func test_is_river_candidate_is_false_when_the_elevation_gate_fails_regardless_of_noise():
	# Scan a real range of coordinates -- with ocean elevation, EVERY one
	# must be false no matter what the noise field says at that point.
	for x in range(0, 500, 37):
		assert_false(river.is_river_candidate(x, 0, SEA_LEVEL - 0.05, SEA_LEVEL, MOUNTAIN_LEVEL))


func test_is_river_candidate_is_sometimes_true_for_qualifying_land():
	# The noise wiring must not be dead -- some tile in a reasonably large,
	# real, low-lying-land scan must actually be a candidate.
	var land_elevation := SEA_LEVEL + 0.01
	var found_one := false
	for x in range(0, 2000, 1):
		if river.is_river_candidate(x, 12345, land_elevation, SEA_LEVEL, MOUNTAIN_LEVEL):
			found_one = true
			break
	assert_true(found_one, "expected at least one procedural river candidate in a 2000-tile scan")


func test_is_river_candidate_is_deterministic():
	var land_elevation := SEA_LEVEL + 0.01
	var first := river.is_river_candidate(777, 888, land_elevation, SEA_LEVEL, MOUNTAIN_LEVEL)
	var second := river.is_river_candidate(777, 888, land_elevation, SEA_LEVEL, MOUNTAIN_LEVEL)
	assert_eq(first, second)


func test_is_river_candidate_is_not_true_everywhere():
	# The whole point of the contour-band technique is winding threads, not
	# a filled region -- a real scan must find at least some false cells too.
	var land_elevation := SEA_LEVEL + 0.01
	var found_a_false := false
	for x in range(0, 2000, 1):
		if not river.is_river_candidate(x, 12345, land_elevation, SEA_LEVEL, MOUNTAIN_LEVEL):
			found_a_false = true
			break
	assert_true(found_a_false, "procedural rivers should not cover every tile")
