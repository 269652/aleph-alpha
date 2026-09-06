extends GutTest

## Karma/Luck (see docs/concept/karma_and_luck.md): Karma is a permanent
## ledger of named events; Luck is a bounded [-1, 1] lens on it that
## existing deterministic formulas (Taming.break_free_chance, OreYield.
## yields) read, never a new source of randomness.

const Karma = preload("res://src/gameplay/karma.gd")


# -- the events themselves are named, tested constants -----------------------

func test_worm_or_caterpillar_crush_costs_one_karma():
	assert_almost_eq(Karma.WORM_OR_CATERPILLAR_CRUSH_PENALTY, 1.0, 0.0001)


func test_abandoning_a_quest_costs_one_karma():
	assert_almost_eq(Karma.QUEST_ABANDON_PENALTY, 1.0, 0.0001)


func test_fulfilling_a_quest_earns_one_karma():
	assert_almost_eq(Karma.QUEST_FULFILLED_REWARD, 1.0, 0.0001)


# -- luck_for is bounded and centred -----------------------------------------

func test_zero_karma_is_neutral_luck():
	assert_almost_eq(Karma.luck_for(0.0), 0.0, 0.0001)


func test_good_karma_is_positive_luck():
	assert_gt(Karma.luck_for(5.0), 0.0)


func test_bad_karma_is_negative_luck():
	assert_lt(Karma.luck_for(-5.0), 0.0)


func test_luck_grows_monotonically_with_karma():
	assert_gt(Karma.luck_for(10.0), Karma.luck_for(5.0))
	assert_gt(Karma.luck_for(0.0), Karma.luck_for(-5.0))


## Bounded in both directions -- a lifetime of good deeds never produces a
## guaranteed roll, the "harder, never impossible" principle this doc
## deliberately echoes from Taming.AFFINITY_MAX_REDUCTION_FRACTION.
func test_luck_saturates_at_the_ceiling_in_both_directions():
	assert_almost_eq(Karma.luck_for(Karma.KARMA_CEILING), 1.0, 0.0001)
	assert_almost_eq(Karma.luck_for(Karma.KARMA_CEILING * 100.0), 1.0, 0.0001)
	assert_almost_eq(Karma.luck_for(-Karma.KARMA_CEILING), -1.0, 0.0001)
	assert_almost_eq(Karma.luck_for(-Karma.KARMA_CEILING * 100.0), -1.0, 0.0001)


func test_luck_is_never_more_extreme_than_one_in_either_direction():
	for karma in [-1000.0, -50.0, -15.0, -1.0, 0.0, 1.0, 15.0, 50.0, 1000.0]:
		var luck: float = Karma.luck_for(karma)
		assert_between(luck, -1.0, 1.0, "luck out of range for karma %.1f" % karma)
