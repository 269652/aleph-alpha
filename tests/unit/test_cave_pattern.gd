extends GutTest

## CavePattern.pattern_for: Palmer's solutional cave morphology (see
## docs/concept/underground.md "Palmer: how the water gets in decides what
## the cave looks like").
##
## Palmer 1991, GSA Bulletin 103. The central finding this file exists to
## encode is that pattern follows RECHARGE, not rock type -- so the same
## recharge mode must give the same pattern in limestone, dolomite and
## gypsum alike, and insoluble rock must give no cave at all.

const CavePattern = preload("res://src/world/cave_pattern.gd")
const CaveRecharge = preload("res://src/world/cave_recharge.gd")
const Lithology = preload("res://src/world/lithology.gd")

var pattern: CavePattern


func before_each():
	pattern = CavePattern.new()


# -- no soluble rock, no solutional cave -----------------------------------

func test_insoluble_rock_has_no_solutional_cave_whatever_the_recharge():
	for rock in [
		Lithology.ROCK_SANDSTONE, Lithology.ROCK_SHALE,
		Lithology.ROCK_GRANITE, Lithology.ROCK_GNEISS, Lithology.ROCK_BASALT,
	]:
		for mode in CaveRecharge.MODES:
			assert_eq(
				pattern.pattern_for(rock, mode), CavePattern.PATTERN_NONE,
				"%s under %s recharge must have no solutional cave" % [rock, mode]
			)


func test_an_unknown_rock_has_no_cave():
	assert_eq(
		pattern.pattern_for("not_a_real_rock", CaveRecharge.MODE_SINKHOLE),
		CavePattern.PATTERN_NONE
	)


func test_soluble_rock_always_gets_a_real_pattern():
	for rock in [Lithology.ROCK_LIMESTONE, Lithology.ROCK_DOLOMITE, Lithology.ROCK_GYPSUM]:
		for mode in CaveRecharge.MODES:
			var result: String = pattern.pattern_for(rock, mode)
			assert_true(CavePattern.PATTERNS.has(result), "'%s' is not a known pattern" % result)
			assert_ne(result, CavePattern.PATTERN_NONE, "%s/%s should have a cave" % [rock, mode])


# -- Palmer's central finding: recharge decides, rock type does not --------

func test_the_same_recharge_gives_the_same_pattern_in_every_soluble_rock():
	for mode in CaveRecharge.MODES:
		var in_limestone: String = pattern.pattern_for(Lithology.ROCK_LIMESTONE, mode)
		for rock in [Lithology.ROCK_DOLOMITE, Lithology.ROCK_GYPSUM]:
			assert_eq(
				pattern.pattern_for(rock, mode), in_limestone,
				(
					"pattern must follow recharge, not rock type (Palmer 1991) -- "
					+ "%s disagreed with limestone under %s recharge"
				) % [rock, mode]
			)


# -- each recharge mode maps to its real Palmer pattern --------------------

func test_sinkhole_recharge_makes_a_branchwork_cave():
	assert_eq(
		pattern.pattern_for(Lithology.ROCK_LIMESTONE, CaveRecharge.MODE_SINKHOLE),
		CavePattern.PATTERN_BRANCHWORK
	)


func test_diffuse_recharge_through_a_caprock_makes_a_network_maze():
	assert_eq(
		pattern.pattern_for(Lithology.ROCK_LIMESTONE, CaveRecharge.MODE_DIFFUSE),
		CavePattern.PATTERN_NETWORK_MAZE
	)


func test_floodwater_recharge_makes_an_anastomotic_maze():
	assert_eq(
		pattern.pattern_for(Lithology.ROCK_LIMESTONE, CaveRecharge.MODE_FLOODWATER),
		CavePattern.PATTERN_ANASTOMOTIC
	)


func test_hypogenic_recharge_makes_a_ramiform_cave():
	# Rising sulfidic water dissolving from below -- Carlsbad, Lechuguilla.
	assert_eq(
		pattern.pattern_for(Lithology.ROCK_LIMESTONE, CaveRecharge.MODE_HYPOGENIC),
		CavePattern.PATTERN_RAMIFORM
	)


func test_mixing_zone_recharge_makes_spongework():
	assert_eq(
		pattern.pattern_for(Lithology.ROCK_LIMESTONE, CaveRecharge.MODE_MIXING_ZONE),
		CavePattern.PATTERN_SPONGEWORK
	)


func test_every_recharge_mode_is_mapped():
	# A new recharge mode must not silently fall through to "no cave".
	for mode in CaveRecharge.MODES:
		assert_ne(
			pattern.pattern_for(Lithology.ROCK_LIMESTONE, mode), CavePattern.PATTERN_NONE,
			"recharge mode '%s' has no pattern mapped" % mode
		)


func test_the_five_patterns_are_all_distinct():
	var seen := {}
	for mode in CaveRecharge.MODES:
		var result: String = pattern.pattern_for(Lithology.ROCK_LIMESTONE, mode)
		assert_false(seen.has(result), "two recharge modes collapsed onto '%s'" % result)
		seen[result] = true


# -- Palmer's surveyed share -----------------------------------------------

func test_branchwork_is_the_surveyed_majority_of_solutional_caves():
	# Palmer's survey of mapped caves put branchwork at roughly 57%, with
	# the maze types making up most of the rest.
	assert_gt(
		CavePattern.PALMER_BRANCHWORK_SHARE, 0.5,
		"branchwork is the majority pattern in Palmer's own survey"
	)
	assert_lt(CavePattern.PALMER_BRANCHWORK_SHARE, 1.0)


func test_the_classification_is_pure():
	var first: String = pattern.pattern_for(Lithology.ROCK_GYPSUM, CaveRecharge.MODE_FLOODWATER)
	var second: String = pattern.pattern_for(Lithology.ROCK_GYPSUM, CaveRecharge.MODE_FLOODWATER)
	assert_eq(first, second)
