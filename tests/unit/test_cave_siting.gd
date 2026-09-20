extends GutTest

## CaveSiting: what kind of cave system, if any, lies under a given place
## (see docs/concept/underground.md). Composes the whole generation stack
## -- Lithology decides whether a cave can exist, CaveRecharge decides how
## water gets in, CavePattern decides what that carves.

const CaveSiting = preload("res://src/world/cave_siting.gd")
const CavePattern = preload("res://src/world/cave_pattern.gd")
const Lithology = preload("res://src/world/lithology.gd")

var siting: CaveSiting


func before_each():
	siting = CaveSiting.new()


func _pattern(x: int, channel: bool, seasonality: float, hydro: float, coast_km: float) -> String:
	return siting.pattern_at(x, 0, 0.5, channel, seasonality, hydro, coast_km)


# -- most of the planet has no cave under it -------------------------------

func test_every_result_is_a_known_pattern():
	for i in 300:
		var pattern := _pattern(i * Lithology.PROVINCE_TILES, i % 2 == 0, 0.3, 0.1, 400.0)
		assert_true(CavePattern.PATTERNS.has(pattern), "'%s' is not a known pattern" % pattern)


func test_most_of_the_planet_has_no_cave_system_at_all():
	# Soluble rock is 15.2% carbonate plus 1.3% evaporite; everything else
	# is rock that does not dissolve. A world where caves are everywhere
	# would be a world where finding one means nothing.
	var none := 0
	var total := 600
	for i in total:
		if _pattern(i * Lithology.PROVINCE_TILES, true, 0.3, 0.1, 400.0) == CavePattern.PATTERN_NONE:
			none += 1
	var share := float(none) / float(total)
	var expected := 1.0 - Lithology.GLOBAL_CARBONATE_SHARE - Lithology.EVAPORITE_SHARE
	assert_almost_eq(share, expected, 0.05)


func test_the_siting_is_deterministic():
	for i in 60:
		var x := i * 197
		assert_eq(
			_pattern(x, true, 0.4, 0.2, 300.0), _pattern(x, true, 0.4, 0.2, 300.0)
		)


func test_a_hypogenic_setting_over_soluble_rock_gives_a_ramiform_cave():
	var found := false
	for i in 400:
		var pattern := _pattern(i * Lithology.PROVINCE_TILES, false, 0.0, 1.0, 900.0)
		if pattern != CavePattern.PATTERN_NONE:
			assert_eq(pattern, CavePattern.PATTERN_RAMIFORM)
			found = true
	assert_true(found, "no soluble province found in the sweep")


# -- Palmer's surveyed branchwork share ------------------------------------
#
# These are the sweep's ASSUMPTIONS about how common each recharge setting
# is across real karst, stated out loud rather than buried: they are not
# measured figures, and the branchwork share below is only as good as
# they are. What IS measured is Palmer's own ~57%, which is what the
# generated mix has to reproduce -- so these assumptions plus
# Lithology.PERMEABLE_COVER_SHARE are jointly pinned by a real number
# rather than being free.
const SWEEP_HYPOGENIC_SHARE := 0.08
const SWEEP_COASTAL_SHARE := 0.10
const SWEEP_SINKING_CHANNEL_SHARE := 0.40
const SWEEP_STRONG_SEASONALITY_SHARE := 0.30

func test_the_generated_mix_reproduces_palmers_surveyed_branchwork_share():
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260917
	var counts := {}
	var cave_bearing := 0
	for i in 6000:
		var hypothermal := 1.0 if rng.randf() < SWEEP_HYPOGENIC_SHARE else 0.0
		var coast_km := 1.0 if rng.randf() < SWEEP_COASTAL_SHARE else 500.0
		var channel := rng.randf() < SWEEP_SINKING_CHANNEL_SHARE
		var seasonality := 1.0 if rng.randf() < SWEEP_STRONG_SEASONALITY_SHARE else 0.0
		var pattern := _pattern(i * Lithology.PROVINCE_TILES, channel, seasonality, hypothermal, coast_km)
		if pattern == CavePattern.PATTERN_NONE:
			continue
		cave_bearing += 1
		counts[pattern] = counts.get(pattern, 0) + 1
	assert_gt(cave_bearing, 500, "not enough cave-bearing provinces to measure a mix")
	var branchwork_share := float(counts.get(CavePattern.PATTERN_BRANCHWORK, 0)) / float(cave_bearing)
	assert_almost_eq(
		branchwork_share, CavePattern.PALMER_BRANCHWORK_SHARE, 0.06,
		"branchwork came out %.1f%% of caves against Palmer's surveyed %.1f%%" % [
			branchwork_share * 100.0, CavePattern.PALMER_BRANCHWORK_SHARE * 100.0
		]
	)


func test_branchwork_is_the_commonest_cave_a_player_will_find():
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := {}
	for i in 4000:
		var hydro := 1.0 if rng.randf() < SWEEP_HYPOGENIC_SHARE else 0.0
		var coast_km := 1.0 if rng.randf() < SWEEP_COASTAL_SHARE else 500.0
		var channel := rng.randf() < SWEEP_SINKING_CHANNEL_SHARE
		var seasonality := 1.0 if rng.randf() < SWEEP_STRONG_SEASONALITY_SHARE else 0.0
		var pattern := _pattern(i * Lithology.PROVINCE_TILES, channel, seasonality, hydro, coast_km)
		if pattern == CavePattern.PATTERN_NONE:
			continue
		counts[pattern] = counts.get(pattern, 0) + 1
	for pattern in counts:
		if pattern == CavePattern.PATTERN_BRANCHWORK:
			continue
		assert_gt(
			counts[CavePattern.PATTERN_BRANCHWORK], counts[pattern],
			"%s outnumbered branchwork" % pattern
		)
