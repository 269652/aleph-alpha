extends GutTest

var Knapping = load("res://src/gameplay/knapping.gd")
var knapping = null


func before_each():
	knapping = Knapping.new()


func test_constants():
	assert_eq(Knapping.SHARD_CHANCE, 0.6, "SHARD_CHANCE pinned at 0.6")
	assert_eq(Knapping.MAX_SHARDS_PER_SMASH, 2, "MAX_SHARDS_PER_SMASH pinned at 2")


func test_shard_yield_deterministic_per_seed():
	for seed_value in [0, 1, 42, 999, -7]:
		assert_eq(
			knapping.shard_yield(seed_value),
			knapping.shard_yield(seed_value),
			"same seed must give same yield (seed %d)" % seed_value
		)


func test_shard_yield_within_bounds():
	for seed_value in range(500):
		var y: int = knapping.shard_yield(seed_value)
		assert_between(y, 0, Knapping.MAX_SHARDS_PER_SMASH, "yield in [0, MAX] for seed %d" % seed_value)


func test_shard_yield_varies_across_seeds():
	var seen := {}
	for seed_value in range(500):
		seen[knapping.shard_yield(seed_value)] = true
	assert_gt(seen.size(), 1, "distribution should not be constant")


func test_success_fraction_matches_shard_chance():
	var fraction: float = knapping.success_fraction_over(500)
	assert_between(
		fraction,
		Knapping.SHARD_CHANCE - 0.1,
		Knapping.SHARD_CHANCE + 0.1,
		"observed success fraction %f should be within +/-0.1 of SHARD_CHANCE" % fraction
	)


func test_success_fraction_over_agrees_with_shard_yield():
	var count := 0
	for seed_value in range(500):
		if knapping.shard_yield(seed_value) >= 1:
			count += 1
	assert_almost_eq(knapping.success_fraction_over(500), float(count) / 500.0, 0.0001)
