extends GutTest

const RarityTier = preload("res://src/gameplay/rarity_tier.gd")

var rarity: RarityTier


func before_each():
	rarity = RarityTier.new()


func test_roll_tier_is_deterministic_for_the_same_seed():
	assert_eq(rarity.roll_tier(123), rarity.roll_tier(123))


func test_roll_tier_only_ever_returns_a_defined_tier():
	for seed_value in range(200):
		assert_true(RarityTier.TIERS.has(rarity.roll_tier(seed_value)))


func test_roll_tier_produces_all_four_tiers_across_many_seeds():
	var seen := {}
	for seed_value in range(200):
		seen[rarity.roll_tier(seed_value)] = true
	assert_true(seen.has("common"))
	assert_true(seen.has("uncommon"))
	assert_true(seen.has("rare"))
	assert_true(seen.has("legendary"))


func test_roll_tier_is_common_weighted_across_many_seeds():
	var counts := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
	var samples := 500
	for seed_value in range(samples):
		var tier: String = rarity.roll_tier(seed_value)
		counts[tier] += 1
	assert_true(counts["common"] > counts["uncommon"])
	assert_true(counts["common"] > counts["rare"])
	assert_true(counts["common"] > counts["legendary"])


func test_stat_multiplier_is_strictly_increasing_from_common_to_legendary():
	var common: float = rarity.stat_multiplier("common")
	var uncommon: float = rarity.stat_multiplier("uncommon")
	var rare: float = rarity.stat_multiplier("rare")
	var legendary: float = rarity.stat_multiplier("legendary")
	assert_true(common < uncommon)
	assert_true(uncommon < rare)
	assert_true(rare < legendary)


func test_stat_multiplier_of_common_is_one():
	assert_almost_eq(rarity.stat_multiplier("common"), 1.0, 0.001)


func test_tier_color_returns_a_distinct_color_per_tier():
	var colors := []
	for tier in RarityTier.TIERS:
		colors.append(rarity.tier_color(tier))
	for i in range(colors.size()):
		for j in range(colors.size()):
			if i != j:
				assert_ne(colors[i], colors[j])


func test_tier_color_unrecognized_tier_returns_fallback_color_without_erroring():
	var fallback: Color = rarity.tier_color("not_a_real_tier")
	assert_eq(fallback, rarity.FALLBACK_COLOR)


func test_tier_color_known_tiers_do_not_return_the_fallback_color():
	for tier in RarityTier.TIERS:
		assert_ne(rarity.tier_color(tier), rarity.FALLBACK_COLOR)


func test_roll_tier_result_is_always_a_key_in_the_multiplier_mapping():
	for seed_value in range(50):
		var tier: String = rarity.roll_tier(seed_value)
		assert_gt(rarity.stat_multiplier(tier), 0.0)


# --- complexity-derived tier (2026-07-15 brainstorm: "spell gems are sealed
# IP, priced by complexity") -------------------------------------------------
# (docs/concept/magic.md: "a gem's rarity/value derives from the spell's
# complexity and material cost ... slotting into the shared item rarity
# vocabulary.") Unlike roll_tier() (a random seed roll), this derives a tier
# straight from a numeric complexity/cost score -- e.g. spell_cost.gd's
# derived_base() -- so a costlier-to-author spell is inherently rarer.
# Boundaries are exact constants pinned by the tests below, not eyeballed.

func test_tier_from_complexity_only_ever_returns_a_defined_tier():
	for complexity in [0.0, 4.0, 9.99, 10.0, 24.99, 25.0, 49.99, 50.0, 500.0]:
		assert_true(RarityTier.TIERS.has(rarity.tier_from_complexity(complexity)))


func test_tier_from_complexity_is_common_below_the_common_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_COMMON_MAX - 0.01), "common")


func test_tier_from_complexity_is_uncommon_at_the_common_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_COMMON_MAX), "uncommon")


func test_tier_from_complexity_is_uncommon_below_the_uncommon_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_UNCOMMON_MAX - 0.01), "uncommon")


func test_tier_from_complexity_is_rare_at_the_uncommon_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_UNCOMMON_MAX), "rare")


func test_tier_from_complexity_is_rare_below_the_rare_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_RARE_MAX - 0.01), "rare")


func test_tier_from_complexity_is_legendary_at_the_rare_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_RARE_MAX), "legendary")


func test_tier_from_complexity_is_legendary_far_beyond_the_rare_bound():
	assert_eq(rarity.tier_from_complexity(RarityTier.COMPLEXITY_RARE_MAX * 100.0), "legendary")


func test_tier_from_complexity_never_decreases_as_complexity_rises():
	var tier_rank := {"common": 0, "uncommon": 1, "rare": 2, "legendary": 3}
	var previous_rank := 0
	for complexity in [0.0, 1.0, 5.0, 10.0, 20.0, 25.0, 40.0, 50.0, 100.0]:
		var rank: int = tier_rank[rarity.tier_from_complexity(complexity)]
		assert_true(rank >= previous_rank)
		previous_rank = rank
