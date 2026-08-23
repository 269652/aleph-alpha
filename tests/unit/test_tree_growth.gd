extends GutTest

## TreeGrowth: a tree's seven stages from seedling to full maturity.
##
## Trees previously popped into existence at full size. Growth gives the
## forest a visible age structure -- saplings under mature canopies -- and
## gives tree spread (see TreeSpread) a consequence you can watch rather
## than only read about in a population count.

const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

var growth: TreeGrowth


func before_each():
	growth = TreeGrowth.new()


func test_there_are_seven_stages():
	assert_eq(TreeGrowth.STAGE_COUNT, 7)


func test_a_just_planted_tree_is_a_seedling():
	assert_eq(growth.stage_at(0.0), 0)


func test_a_long_lived_tree_reaches_the_final_stage():
	assert_eq(growth.stage_at(TreeGrowth.MATURITY_SECONDS * 5.0), TreeGrowth.STAGE_COUNT - 1)


func test_stages_advance_monotonically_with_age():
	var previous := -1
	for i in 60:
		var age := TreeGrowth.MATURITY_SECONDS * float(i) / 40.0
		var stage := growth.stage_at(age)
		assert_gte(stage, previous, "a tree must never shrink as it ages")
		previous = stage


func test_every_stage_is_reachable():
	var seen := {}
	for i in 400:
		seen[growth.stage_at(TreeGrowth.MATURITY_SECONDS * float(i) / 200.0)] = true
	assert_eq(seen.size(), TreeGrowth.STAGE_COUNT, "every stage should occur as a tree ages")


## Scale is what the renderer actually draws with, so it must grow with the
## stage and finish at exactly full size.
func test_scale_grows_from_a_small_seedling_to_full_size():
	var seedling := growth.scale_for_stage(0)
	assert_between(seedling, 0.1, 0.4, "a seedling should be visibly tiny")
	assert_almost_eq(growth.scale_for_stage(TreeGrowth.STAGE_COUNT - 1), 1.0, 0.001)
	for stage in range(1, TreeGrowth.STAGE_COUNT):
		assert_gt(
			growth.scale_for_stage(stage), growth.scale_for_stage(stage - 1),
			"stage %d should be bigger than stage %d" % [stage, stage - 1]
		)


func test_scale_clamps_for_out_of_range_stages():
	assert_almost_eq(growth.scale_for_stage(-5), growth.scale_for_stage(0), 0.001)
	assert_almost_eq(growth.scale_for_stage(99), growth.scale_for_stage(TreeGrowth.STAGE_COUNT - 1), 0.001)


## Only a grown tree should bear fruit or be worth felling -- a seedling
## isn't a timber source.
func test_only_mature_stages_are_productive():
	assert_false(growth.is_productive(0), "a seedling bears nothing")
	assert_true(growth.is_productive(TreeGrowth.STAGE_COUNT - 1), "a full tree is productive")


func test_is_deterministic():
	assert_eq(growth.stage_at(123.4), growth.stage_at(123.4))


## Callers pass INF to mean "this has always been here" (map-generated
## forest). int(INF) collapses rather than clamping, which silently turned
## every mature forest tree into a seedling.
func test_an_infinite_age_is_fully_mature():
	assert_eq(growth.stage_at(INF), TreeGrowth.STAGE_COUNT - 1)
	assert_almost_eq(growth.scale_at(INF), 1.0, 0.001)


# -- a tree takes years ------------------------------------------------------

## A sapling becomes a young tree in a YEAR, and takes two more to mature.
##
## MATURITY_SECONDS was 600 simulated seconds against a year of 691,200 -- less
## than a tenth of a percent of a year -- so a tree went from nothing to
## full-grown inside a single season, which is exactly what was reported once
## /ecotest made a year watchable. The comment justified it as "roughly ten
## simulated ecosystem days", a different clock from the one the seasons run
## on.
func test_a_sapling_takes_a_year_to_become_a_young_tree():
	var growth := TreeGrowth.new()
	assert_almost_eq(
		TreeGrowth.YOUNG_SECONDS / SeasonCycle.SECONDS_PER_YEAR, 1.0, 0.05,
		"a sapling should take about a year to become a young tree"
	)
	assert_false(growth.is_productive(growth.stage_at(TreeGrowth.YOUNG_SECONDS * 0.5)))


func test_a_young_tree_takes_two_more_years_to_mature():
	assert_almost_eq(
		(TreeGrowth.MATURITY_SECONDS - TreeGrowth.YOUNG_SECONDS)
			/ SeasonCycle.SECONDS_PER_YEAR,
		2.0,
		0.05,
		"a young tree should take about two more years to mature"
	)


func test_a_tree_is_not_mature_within_one_season():
	var growth := TreeGrowth.new()
	var one_season := SeasonCycle.SECONDS_PER_YEAR / float(SeasonCycle.SEASONS.size())
	assert_lt(
		growth.scale_at(one_season), 1.0,
		"a tree should not be full-grown after a single season"
	)


# -- it grows the whole way --------------------------------------------------

## The stem thickens and the crown fills out GRADUALLY, rather than the tree
## popping between a few sizes.
func test_a_tree_grows_smoothly_rather_than_in_jumps():
	var growth := TreeGrowth.new()
	var sizes := {}
	for step in 60:
		sizes[snappedf(growth.scale_at(float(step) / 59.0 * TreeGrowth.MATURITY_SECONDS), 0.01)] = true
	assert_gt(sizes.size(), 10, "growth reads as %d jumps, not a curve" % sizes.size())


func test_a_tree_never_shrinks_as_it_ages():
	var growth := TreeGrowth.new()
	var previous := 0.0
	for step in 100:
		var scale := growth.scale_at(float(step) / 99.0 * TreeGrowth.MATURITY_SECONDS)
		assert_gte(scale, previous)
		previous = scale


## It is a seedling for a good while, not for an instant.
func test_a_seedling_stays_small_for_a_real_stretch():
	var growth := TreeGrowth.new()
	var a_month := SeasonCycle.SECONDS_PER_YEAR / 12.0
	assert_lt(
		growth.scale_at(a_month), 0.5,
		"a month-old seedling should still be visibly a seedling"
	)


## Bearing fruit waits until the tree is actually a tree -- a sapling is not a
## harvest.
func test_a_tree_does_not_bear_in_its_first_year():
	var growth := TreeGrowth.new()
	assert_false(
		growth.is_productive(growth.stage_at(SeasonCycle.SECONDS_PER_YEAR * 0.9)),
		"a tree under a year old should not be bearing"
	)
