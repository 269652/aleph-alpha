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
