extends GutTest

## See docs/concept/ecosystem_dynamics.md#region-difficulty-gating-the-roster-by-player-readiness.
## Difficulty is a concentric distance-from-spawn gradient (a transparent
## game-design choice), not derived from real-world danger statistics or
## manual per-country curation.

const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

var difficulty: RegionDifficulty


func before_each():
	difficulty = RegionDifficulty.new()


func test_the_spawn_chunk_itself_is_easy():
	assert_eq(difficulty.tier_at(Vector2i.ZERO, Vector2i.ZERO), RegionDifficulty.Tier.EASY)


func test_a_nearby_chunk_is_easy():
	var near := Vector2i(RegionDifficulty.EASY_RADIUS_CHUNKS, 0)
	assert_eq(difficulty.tier_at(near, Vector2i.ZERO), RegionDifficulty.Tier.EASY)


func test_a_moderately_far_chunk_is_medium():
	var mid := Vector2i(RegionDifficulty.EASY_RADIUS_CHUNKS + 1, 0)
	assert_eq(difficulty.tier_at(mid, Vector2i.ZERO), RegionDifficulty.Tier.MEDIUM)


func test_a_very_far_chunk_is_hard():
	var far := Vector2i(RegionDifficulty.MEDIUM_RADIUS_CHUNKS + 1, 0)
	assert_eq(difficulty.tier_at(far, Vector2i.ZERO), RegionDifficulty.Tier.HARD)


func test_difficulty_never_decreases_as_distance_grows():
	var previous_tier = RegionDifficulty.Tier.EASY
	for distance in range(0, 200, 10):
		var tier = difficulty.tier_at(Vector2i(distance, 0), Vector2i.ZERO)
		assert_gte(tier, previous_tier)
		previous_tier = tier


## A diagonal offset of (EASY_RADIUS, EASY_RADIUS) is still within
## EASY_RADIUS_CHUNKS under Chebyshev (max) distance, not Euclidean --
## matches EarthChunkManager's own chunk-radius math (LOAD_RADIUS etc).
func test_uses_chebyshev_distance_not_euclidean():
	var diagonal := Vector2i(RegionDifficulty.EASY_RADIUS_CHUNKS, RegionDifficulty.EASY_RADIUS_CHUNKS)
	assert_eq(difficulty.tier_at(diagonal, Vector2i.ZERO), RegionDifficulty.Tier.EASY)


func test_difficulty_is_relative_to_the_given_spawn_not_a_hardcoded_point():
	var spawn := Vector2i(500, 500)
	assert_eq(difficulty.tier_at(spawn, spawn), RegionDifficulty.Tier.EASY)
	var far := spawn + Vector2i(RegionDifficulty.MEDIUM_RADIUS_CHUNKS + 1, 0)
	assert_eq(difficulty.tier_at(far, spawn), RegionDifficulty.Tier.HARD)
