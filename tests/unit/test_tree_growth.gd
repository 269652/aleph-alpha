extends GutTest

## TreeGrowth: a tree's seven stages from seedling to full maturity.
##
## Trees previously popped into existence at full size. Growth gives the
## forest a visible age structure -- saplings under mature canopies -- and
## gives tree spread (see TreeSpread) a consequence you can watch rather
## than only read about in a population count.

const TreeGrowth = preload("res://src/gameplay/tree_growth.gd")

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
