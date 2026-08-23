extends GutTest

const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

var genome: TreeGenome


func before_each():
	genome = TreeGenome.new(42)


func test_traits_are_within_expected_ranges():
	assert_between(genome.fruit_yield, 0.0, 1.0)
	assert_between(genome.species_bias, 0.0, 1.0)
	assert_between(genome.spread_radius, TreeGenome.MIN_SPREAD_RADIUS, TreeGenome.MAX_SPREAD_RADIUS)
	assert_between(genome.maturity_time, TreeGenome.MIN_MATURITY_TIME, TreeGenome.MAX_MATURITY_TIME)


func test_is_deterministic_for_the_same_seed():
	var a := TreeGenome.new(123)
	var b := TreeGenome.new(123)
	assert_eq(a.fruit_yield, b.fruit_yield)
	assert_eq(a.species_bias, b.species_bias)
	assert_eq(a.spread_radius, b.spread_radius)
	assert_eq(a.maturity_time, b.maturity_time)


func test_different_seeds_produce_different_traits():
	var a := TreeGenome.new(1)
	var b := TreeGenome.new(2)
	var any_differs := (
		a.fruit_yield != b.fruit_yield
		or a.species_bias != b.species_bias
		or a.spread_radius != b.spread_radius
		or a.maturity_time != b.maturity_time
	)
	assert_true(any_differs)


func test_mutate_returns_a_genome_with_a_different_seed():
	var child: TreeGenome = genome.mutate(7)
	assert_ne(child.seed_value, genome.seed_value)


func test_mutated_traits_stay_close_to_the_parents_rather_than_random():
	var child: TreeGenome = genome.mutate(7)
	assert_almost_eq(child.fruit_yield, genome.fruit_yield, TreeGenome.MUTATION_AMOUNT * 1.5)
	assert_almost_eq(child.species_bias, genome.species_bias, TreeGenome.MUTATION_AMOUNT * 1.5)


func test_mutated_traits_still_stay_within_valid_ranges():
	for i in 20:
		var child: TreeGenome = genome.mutate(i)
		assert_between(child.fruit_yield, 0.0, 1.0)
		assert_between(child.species_bias, 0.0, 1.0)
		assert_between(child.spread_radius, TreeGenome.MIN_SPREAD_RADIUS, TreeGenome.MAX_SPREAD_RADIUS)
		assert_between(child.maturity_time, TreeGenome.MIN_MATURITY_TIME, TreeGenome.MAX_MATURITY_TIME)


## Bearing waits years, not seconds.
##
## maturity_time was 20-60 SECONDS against a year of 691,200 -- a second
## maturation clock disagreeing with TreeGrowth's by four orders of magnitude,
## so a sapling could seed the instant it was planted. Both are measured
## against the season cycle now.
func test_a_tree_cannot_bear_until_it_is_years_old():
	var SeasonCycle := load("res://src/world/season_cycle.gd")
	for seed_value in 200:
		var genome := TreeGenome.new(seed_value)
		assert_gt(
			genome.maturity_time, SeasonCycle.SECONDS_PER_YEAR,
			"a tree should not bear in its first year"
		)


## ...and roughly when TreeGrowth calls it grown, rather than on a clock of its
## own.
func test_bearing_age_agrees_with_the_growth_model():
	var TreeGrowth := load("res://src/gameplay/tree_growth.gd")
	var earliest := TreeGenome.MIN_MATURITY_TIME
	var latest := TreeGenome.MAX_MATURITY_TIME
	assert_lte(earliest, TreeGrowth.MATURITY_SECONDS * 1.5)
	assert_gte(latest, TreeGrowth.MATURITY_SECONDS * 0.8)
