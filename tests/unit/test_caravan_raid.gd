extends GutTest

## CaravanRaid: per-trip raid-risk math for a real regional-trade caravan
## (see docs/concept/trade.md). Reuses RegionDifficulty's own existing
## distance-from-spawn danger tiers rather than inventing a second danger
## scale -- the same "reuse a real signal" discipline RegionalTrade already
## applies to shortage/surplus.

const CaravanRaid = preload("res://src/emergence/caravan_raid.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")


# -- raid_chance_for_tier: test-pinned, no real banditry statistic exists --

func test_easy_tier_is_never_raided():
	assert_eq(CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.EASY), 0.0)


func test_hard_tier_is_riskier_than_medium_tier():
	assert_gt(
		CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.HARD),
		CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.MEDIUM)
	)


func test_medium_tier_is_riskier_than_easy_tier():
	assert_gt(
		CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.MEDIUM),
		CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.EASY)
	)


# -- is_raided: a pure threshold check against one deterministic roll -----

func test_a_roll_below_the_chance_is_raided():
	assert_true(CaravanRaid.is_raided(RegionDifficulty.Tier.HARD, 0.0))


func test_a_roll_at_or_above_the_chance_is_not_raided():
	var chance: float = CaravanRaid.raid_chance_for_tier(RegionDifficulty.Tier.HARD)
	assert_false(CaravanRaid.is_raided(RegionDifficulty.Tier.HARD, chance))


func test_easy_tier_is_never_raided_even_on_the_lowest_possible_roll():
	assert_false(CaravanRaid.is_raided(RegionDifficulty.Tier.EASY, 0.0))


# -- roll_for: deterministic, hash-derived, no RandomNumberGenerator state -

func test_roll_for_is_deterministic_for_the_same_trip_identity():
	var a: float = CaravanRaid.roll_for("settlement:0_0", "settlement:1_0", "rock", 30.0, "raid_check")
	var b: float = CaravanRaid.roll_for("settlement:0_0", "settlement:1_0", "rock", 30.0, "raid_check")
	assert_eq(a, b)


func test_roll_for_stays_within_the_unit_range():
	var roll: float = CaravanRaid.roll_for("settlement:2_2", "settlement:3_2", "stick", 900.0, "raid_check")
	assert_true(roll >= 0.0 and roll < 1.0)


func test_roll_for_differs_by_salt_so_the_raid_check_and_fraction_are_independent():
	var check_roll: float = CaravanRaid.roll_for("settlement:0_0", "settlement:1_0", "rock", 30.0, "raid_check")
	var fraction_roll: float = CaravanRaid.roll_for("settlement:0_0", "settlement:1_0", "rock", 30.0, "raid_fraction")
	assert_ne(check_roll, fraction_roll)
