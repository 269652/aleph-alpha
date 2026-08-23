extends GutTest

## HeroDna (see docs/concept/dna.md): a rolled genome that drives both the
## character's visual phenotype (HeroAppearance, unchanged -- same seed
## already drives that) and a soft per-archetype RESONANCE profile plus
## small stat modifiers. Reported ask: "you can randomize the base DNA of
## your character which influences stats/visuals ... slight chance of
## spawning a rare (better) character DNA which e.g. has excellent magic att
## but no defense or so ... rare DNA should still be balanced and not break
## the system ... but it should still be a 'awesome, nice' moment to get
## one." Follow-up: "add legendary dna which is just better in most stats so
## a real win" -- legendary is deliberately NOT balanced like common/rare;
## it's a genuine, rare (3%) power jackpot.

const HeroDna = preload("res://src/gameplay/hero_dna.gd")
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")

var dna: HeroDna


func before_each():
	dna = HeroDna.new()


func test_roll_is_deterministic_for_the_same_seed():
	assert_eq(dna.roll(12345), dna.roll(12345))


func test_two_different_seeds_usually_roll_differently():
	var distinct_rarities := {}
	var distinct_traits := {}
	for seed_value in 40:
		var genome := dna.roll(seed_value)
		distinct_rarities[genome.rarity] = true
		distinct_traits[genome.trait_name] = true
	assert_gt(distinct_rarities.size(), 1, "40 rolls should not all land the same rarity")
	assert_gt(distinct_traits.size(), 1, "40 rolls should not all roll the same trait")


func test_every_roll_has_a_resonance_score_for_every_archetype():
	var genome := dna.roll(7)
	for archetype in ClassArchetype.new().archetype_names():
		assert_true(genome.resonance.has(archetype), archetype)
		assert_between(genome.resonance[archetype], 0.0, 1.0, archetype)


## The balancing invariant for COMMON and RARE: however concentrated the
## stat swing is, its buffs and deficits must cancel out to net-zero raw
## power. This is what lets rarity increase EXCITEMENT for those two tiers
## (a bigger, more dramatic swing) without increasing raw POWER -- see
## HeroDna's own doc comment. LEGENDARY is deliberately exempt (see below).
func test_common_and_rare_stat_modifiers_always_net_to_zero_raw_power():
	var checked_common := false
	var checked_rare := false
	for seed_value in 200:
		var genome := dna.roll(seed_value)
		if genome.rarity == HeroDna.RARITY_LEGENDARY:
			continue
		checked_common = checked_common or genome.rarity == HeroDna.RARITY_COMMON
		checked_rare = checked_rare or genome.rarity == HeroDna.RARITY_RARE
		var total := 0.0
		for key in genome.stat_modifiers:
			total += genome.stat_modifiers[key]
		assert_almost_eq(total, 0.0, 0.01, "seed %d (%s)" % [seed_value, genome.rarity])
	assert_true(checked_common and checked_rare, "precondition: both tiers appeared in the sample")


## The follow-up's core requirement: legendary is a genuine, no-catch power
## jackpot -- net POSITIVE raw power, every stat modifier >= 0 (no downside
## at all, unlike common/rare's balanced swing), and MOST stats (at least 3
## of the 4) actually improved, not just one.
func test_legendary_rolls_are_a_real_net_positive_win_across_most_stats():
	var checked_any := false
	for seed_value in 400:
		var genome := dna.roll(seed_value)
		if genome.rarity != HeroDna.RARITY_LEGENDARY:
			continue
		checked_any = true
		var total := 0.0
		var improved_count := 0
		for key in genome.stat_modifiers:
			var value: float = genome.stat_modifiers[key]
			assert_gte(value, 0.0, "legendary DNA must never reduce a stat (seed %d, %s)" % [seed_value, key])
			total += value
			if value > 0.0:
				improved_count += 1
		assert_gt(total, 0.0, "seed %d" % seed_value)
		assert_gte(improved_count, 3, "seed %d should improve most (3+) stats" % seed_value)
	assert_true(checked_any, "precondition: at least one legendary roll appeared in the sample")


## Rarity distribution: common should dominate (dna.md: rare/legendary DNA
## is meant to be a genuinely rare, exciting moment, not a coin flip).
func test_common_is_the_overwhelming_majority_of_rolls():
	var counts := {HeroDna.RARITY_COMMON: 0, HeroDna.RARITY_RARE: 0, HeroDna.RARITY_LEGENDARY: 0}
	for seed_value in 2000:
		counts[dna.roll(seed_value).rarity] += 1
	assert_gt(counts[HeroDna.RARITY_COMMON], 1400, "common should be the large majority")
	assert_lt(counts[HeroDna.RARITY_LEGENDARY], counts[HeroDna.RARITY_RARE], "legendary must stay rarer than rare")
	assert_gt(counts[HeroDna.RARITY_LEGENDARY], 0, "legendary should still be reachable across 2000 rolls")


## Rare still swings harder than common (both balanced); legendary's total
## power (sum, since it has no deficit side) beats rare's raw swing budget --
## the actual "real win" the follow-up asked for.
func test_rarer_rolls_are_more_dramatic_than_common_ones():
	var common_spread := _max_stat_spread_for_rarity(HeroDna.RARITY_COMMON)
	var rare_spread := _max_stat_spread_for_rarity(HeroDna.RARITY_RARE)
	var legendary_total := _max_total_power_for_rarity(HeroDna.RARITY_LEGENDARY)
	assert_gt(rare_spread, common_spread)
	assert_gt(legendary_total, rare_spread)


func _max_stat_spread_for_rarity(rarity: String) -> float:
	var best := 0.0
	for seed_value in 400:
		var genome := dna.roll(seed_value)
		if genome.rarity != rarity:
			continue
		var values: Array = genome.stat_modifiers.values()
		var spread: float = values.max() - values.min()
		best = maxf(best, spread)
	return best


func _max_total_power_for_rarity(rarity: String) -> float:
	var best := 0.0
	for seed_value in 400:
		var genome := dna.roll(seed_value)
		if genome.rarity != rarity:
			continue
		var total := 0.0
		for key in genome.stat_modifiers:
			total += genome.stat_modifiers[key]
		best = maxf(best, total)
	return best


## A common roll shouldn't come with a flashy trait name -- only rare and
## legendary genomes are the "excellent X but no Y"/"real win" moment.
func test_only_rare_and_legendary_rolls_get_a_named_trait():
	for seed_value in 300:
		var genome := dna.roll(seed_value)
		if genome.rarity == HeroDna.RARITY_COMMON:
			assert_eq(genome.trait_name, "", "seed %d" % seed_value)
		else:
			assert_ne(genome.trait_name, "", "seed %d (%s)" % [seed_value, genome.rarity])


# -- reroll budget: 3-5 free, then a real 24h real-world wait -------------
#
# dna.md: "reroll character generation a few times (3-5) then they need to
# buy premium credits". Follow-up, replacing/tightening that: "rerolls
# should reset every 24h real world hours so you have to wait a whole day
# if your rerolls are empty forcing the player to make wise choices". The
# premium-credits bypass stays as a hook (can_reroll's has_premium) since no
# real payment flow exists yet, but the FREE path is now real-world-time
# gated rather than session-scoped.

func test_free_rerolls_are_allowed_up_to_the_limit_within_the_same_day():
	for used in HeroDna.MAX_FREE_REROLLS:
		assert_true(dna.can_reroll(used, 0.0, false), "used=%d" % used)


func test_free_rerolls_run_out_at_the_limit_within_the_same_day():
	assert_false(dna.can_reroll(HeroDna.MAX_FREE_REROLLS, 0.0, false))
	# Even most of a day later, still blocked -- must be a FULL day.
	assert_false(dna.can_reroll(HeroDna.MAX_FREE_REROLLS, HeroDna.RESET_INTERVAL_SECONDS - 1.0, false))


func test_a_full_real_world_day_refreshes_the_reroll_budget_even_with_none_used():
	assert_true(dna.can_reroll(HeroDna.MAX_FREE_REROLLS, HeroDna.RESET_INTERVAL_SECONDS, false))
	assert_true(dna.can_reroll(HeroDna.MAX_FREE_REROLLS, HeroDna.RESET_INTERVAL_SECONDS * 3.0, false))


func test_premium_bypasses_the_reroll_limit_regardless_of_time():
	assert_true(dna.can_reroll(HeroDna.MAX_FREE_REROLLS, 0.0, true))
	assert_true(dna.can_reroll(HeroDna.MAX_FREE_REROLLS + 50, 0.0, true))


func test_reroll_budget_has_reset_matches_can_reroll_at_the_boundary():
	assert_false(dna.reroll_budget_has_reset(HeroDna.RESET_INTERVAL_SECONDS - 0.01))
	assert_true(dna.reroll_budget_has_reset(HeroDna.RESET_INTERVAL_SECONDS))
