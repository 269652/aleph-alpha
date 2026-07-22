extends GutTest

const FishingMinigame = preload("res://src/gameplay/fishing_minigame.gd")

var minigame: FishingMinigame


func before_each():
	minigame = FishingMinigame.new()


func test_bite_delay_is_deterministic_for_same_inputs():
	assert_eq(minigame.bite_delay(42, 0.5), minigame.bite_delay(42, 0.5))


func test_bite_delay_is_within_expected_range():
	for seed_value in range(20):
		var delay := minigame.bite_delay(seed_value, 0.5)
		assert_between(delay, 2.0, 15.0)


func test_higher_bait_quality_produces_shorter_or_equal_average_delay():
	var total_low := 0.0
	var total_high := 0.0
	var samples := 30
	for seed_value in range(samples):
		total_low += minigame.bite_delay(seed_value, 0.0)
		total_high += minigame.bite_delay(seed_value, 1.0)
	var average_low := total_low / samples
	var average_high := total_high / samples
	assert_true(average_high <= average_low, "higher bait_quality should not increase the average delay")


func test_max_bait_quality_returns_minimum_delay():
	assert_almost_eq(minigame.bite_delay(7, 1.0), 2.0, 0.001)


func test_attempt_catch_true_when_reaction_time_is_less_than_window():
	assert_true(minigame.attempt_catch(0.5, 1.0))


func test_attempt_catch_true_at_exact_equality():
	# Documented boundary behavior: reacting exactly at the window edge still counts as a catch.
	assert_true(minigame.attempt_catch(1.0, 1.0))


func test_attempt_catch_false_when_reaction_time_is_greater_than_window():
	assert_false(minigame.attempt_catch(1.5, 1.0))


func test_fish_rarity_is_deterministic_for_same_seed():
	assert_eq(minigame.fish_rarity(99), minigame.fish_rarity(99))


func test_fish_rarity_produces_all_four_tiers_across_many_seeds():
	var seen := {}
	for seed_value in range(50):
		seen[minigame.fish_rarity(seed_value)] = true
	assert_true(seen.has("common"))
	assert_true(seen.has("uncommon"))
	assert_true(seen.has("rare"))
	assert_true(seen.has("legendary"))


func test_fish_rarity_is_heavily_common_weighted():
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	var samples := 500
	for seed_value in range(samples):
		var rarity: String = minigame.fish_rarity(seed_value)
		counts[rarity] += 1
	assert_true(counts["common"] > counts["uncommon"])
	assert_true(counts["common"] > counts["rare"])
	assert_true(counts["common"] > counts["legendary"])


func test_fish_rarity_returns_only_known_tiers():
	var valid := ["common", "uncommon", "rare", "legendary"]
	for seed_value in range(50):
		assert_true(valid.has(minigame.fish_rarity(seed_value)))
