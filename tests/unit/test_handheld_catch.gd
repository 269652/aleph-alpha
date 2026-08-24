extends GutTest

## HandheldCatch (docs/concept/easter_eggs.md's "hidden retro handheld"
## entry): the catch/collection mechanic -- a "deterministic (seed-derived,
## not random) success chance based on a defeated creature's remaining
## health fraction" per this stage's own task, mirroring this project's
## other deterministic-from-seed systems (e.g. CreatureInfo's own
## `level = 1 + (absi(seed_value) % LEVEL_RANGE)`) rather than a dice roll.
##
## Deliberately NOT part of HandheldBattle -- a catch attempt is something
## HandheldBattleView offers the player INSTEAD of a battle move (passing
## HandheldBattle.MOVE_PASS in on that round), so the battle core never
## needs to know catching exists at all. This module only answers two pure
## questions: how likely is a catch at this remaining-health fraction, and
## did THIS specific (fraction, seed) combination succeed.
##
## catch_chance/attempt_catch never call randf() -- `seed_value` is a plain
## caller-supplied int (in real play, HandheldBattleView derives one from
## something that changes between attempts, e.g. a hash of the encounter's
## own species id and an attempt counter -- see that view's own doc comment
## for the exact derivation), so the exact same (fraction, seed_value) pair
## always produces the exact same outcome, reproducibly.
##
## BASE_CATCH_CHANCE/MAX_CATCH_BONUS are first-pass placeholders (no real
## playtesting data yet, the same situation as every other tuned constant in
## this doc's family) but pinned by direct exact-value assertions below,
## matching spell_cost.gd's MAG_EXP/SPAM_PENALTY discipline.

const HandheldCatch = preload("res://src/gameplay/handheld_catch.gd")

var catcher: HandheldCatch


func before_each():
	catcher = HandheldCatch.new()


## --- catch_chance ---


func test_catch_chance_at_full_health_is_the_base_chance():
	assert_almost_eq(catcher.catch_chance(1.0), HandheldCatch.BASE_CATCH_CHANCE, 0.0001)


func test_catch_chance_at_zero_remaining_health_is_base_plus_max_bonus():
	assert_almost_eq(
		catcher.catch_chance(0.0),
		HandheldCatch.BASE_CATCH_CHANCE + HandheldCatch.MAX_CATCH_BONUS,
		0.0001
	)


func test_catch_chance_at_half_health_is_the_midpoint():
	var expected := HandheldCatch.BASE_CATCH_CHANCE + HandheldCatch.MAX_CATCH_BONUS * 0.5
	assert_almost_eq(catcher.catch_chance(0.5), expected, 0.0001)


func test_catch_chance_rises_as_remaining_health_falls():
	assert_true(catcher.catch_chance(0.2) > catcher.catch_chance(0.8))


func test_catch_chance_is_clamped_to_one_even_past_zero_health():
	assert_almost_eq(catcher.catch_chance(-1.0), 1.0, 0.0001)


func test_catch_chance_never_exceeds_one():
	assert_true(catcher.catch_chance(0.0) <= 1.0)


## --- attempt_catch: deterministic given (fraction, seed) ---


func test_attempt_catch_is_deterministic_for_the_same_inputs():
	var a := catcher.attempt_catch(0.4, 12345)
	var b := catcher.attempt_catch(0.4, 12345)
	assert_eq(a, b)


func test_attempt_catch_can_succeed_with_a_favorable_seed_at_low_health():
	# seed_value 0 always produces the minimum possible seeded roll (0.0),
	# which succeeds against any positive catch chance.
	assert_true(catcher.attempt_catch(0.0, 0))


func test_attempt_catch_can_fail_with_an_unfavorable_seed_at_full_health():
	# A seed chosen so the seeded roll lands just above BASE_CATCH_CHANCE
	# fails at full health, where BASE_CATCH_CHANCE is the entire chance.
	var seed_value := 999
	assert_true(catcher._seeded_roll(seed_value) > HandheldCatch.BASE_CATCH_CHANCE)
	assert_false(catcher.attempt_catch(1.0, seed_value))


func test_attempt_catch_succeeds_at_zero_health_for_any_seed_under_the_max_chance():
	# catch_chance(0.0) is BASE_CATCH_CHANCE + MAX_CATCH_BONUS -- deliberately
	# NOT a guaranteed 1.0 even at the lowest possible health (a catch is
	# never a bare formality, no matter how weakened the target is) -- so
	# this only holds for seeds whose own roll lands under that ceiling.
	for seed_value in [0, 1, 250, 500, 750, 940]:
		assert_true(catcher.attempt_catch(0.0, seed_value), "seed %d" % seed_value)


## --- _seeded_roll: the deterministic, non-random "roll" ---


func test_seeded_roll_is_within_zero_and_one():
	for seed_value in [0, 1, 42, 999, 123456]:
		var roll := catcher._seeded_roll(seed_value)
		assert_true(roll >= 0.0 and roll < 1.0, "seed %d" % seed_value)


func test_seeded_roll_is_deterministic():
	assert_eq(catcher._seeded_roll(777), catcher._seeded_roll(777))


func test_seeded_roll_differs_across_most_seeds():
	# Not a claim of perfect uniqueness -- just that it isn't a constant
	# function collapsing every seed to the same roll.
	var rolls := {}
	for seed_value in range(20):
		rolls[catcher._seeded_roll(seed_value)] = true
	assert_true(rolls.size() > 1)
