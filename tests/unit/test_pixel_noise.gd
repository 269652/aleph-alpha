extends GutTest

## PixelNoise: the shared deterministic randomness every procedural
## generator draws with (see docs/concept/pixel_art_engine.md).
##
## Generators used to seed themselves with Godot's string `hash()` --
## hash("%d_thing_%d" % [seed, i]). That correlates badly across
## near-identical inputs, and this project has been bitten by it twice:
## once where a seeded index froze to a single bucket, and once where whole
## ROWS of tree leaves came out at the same angle. These tests pin the
## distribution properties that bug class violates.

const PixelNoise = preload("res://src/rendering/pixel_noise.gd")


func test_is_deterministic():
	assert_eq(PixelNoise.value(7, 3, 11), PixelNoise.value(7, 3, 11))
	assert_eq(PixelNoise.unit(7, 3, 11), PixelNoise.unit(7, 3, 11))


func test_unit_stays_in_range():
	for i in 200:
		assert_between(PixelNoise.unit(i, i * 3, 5), 0.0, 1.0)


## The regression that motivated this module: sequential inputs must not
## produce clustered outputs. Godot's string hash gave near-identical
## values for "..._0", "..._1", "..._2", so consecutive leaves shared an
## angle.
func test_sequential_inputs_do_not_correlate():
	var previous := PixelNoise.unit(42, 0, 0)
	var big_jumps := 0
	for i in range(1, 100):
		var current := PixelNoise.unit(42, i, 0)
		if absf(current - previous) > 0.25:
			big_jumps += 1
		previous = current
	assert_gt(big_jumps, 40, "consecutive values should scatter, not drift together")


## Values must spread across the whole range, not pile into a few buckets
## (the "froze to one bucket" failure).
func test_values_spread_across_the_whole_range():
	var buckets := {}
	for i in 500:
		buckets[int(PixelNoise.unit(3, i, 0) * 10.0)] = true
	assert_gte(buckets.size(), 9, "should reach nearly every tenth of the range")


func test_different_seeds_give_different_sequences():
	var same := 0
	for i in 100:
		if is_equal_approx(PixelNoise.unit(1, i, 0), PixelNoise.unit(2, i, 0)):
			same += 1
	assert_lt(same, 5, "different seeds should produce different sequences")


## Both coordinates must actually matter -- a 2D field that ignores y would
## produce vertical banding in every texture drawn with it.
func test_both_coordinates_affect_the_result():
	var differing := 0
	for i in 50:
		if not is_equal_approx(PixelNoise.unit(9, i, 0), PixelNoise.unit(9, i, 1)):
			differing += 1
	assert_gt(differing, 45, "changing y must change the value")


## range_value is the ergonomic form generators actually call for "pick a
## size/length/offset in [low, high]".
func test_range_value_stays_within_its_bounds():
	for i in 200:
		var v := PixelNoise.range_value(4, i, 0, 3.0, 9.0)
		assert_between(v, 3.0, 9.0)


func test_range_index_stays_within_its_bounds_and_uses_every_option():
	var seen := {}
	for i in 300:
		var index := PixelNoise.range_index(6, i, 0, 5)
		assert_between(index, 0, 4)
		seen[index] = true
	assert_eq(seen.size(), 5, "every option should be reachable")


## Smooth value noise for organic gradients (cloud/fur/marble style), as
## opposed to the per-pixel scatter above.
func test_smooth_noise_is_continuous_between_neighbours():
	var biggest_jump := 0.0
	for x in 60:
		var a := PixelNoise.smooth(5, float(x) * 0.25, 0.0)
		var b := PixelNoise.smooth(5, float(x + 1) * 0.25, 0.0)
		biggest_jump = maxf(biggest_jump, absf(b - a))
	assert_lt(biggest_jump, 0.5, "smooth noise should not jump like white noise")


func test_smooth_noise_stays_in_range_and_is_deterministic():
	for i in 60:
		var v := PixelNoise.smooth(2, float(i) * 0.3, float(i) * 0.17)
		assert_between(v, 0.0, 1.0)
	assert_eq(PixelNoise.smooth(2, 1.5, 2.5), PixelNoise.smooth(2, 1.5, 2.5))
