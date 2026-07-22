extends GutTest

const TreeSpread = preload("res://src/gameplay/tree_spread.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

var spread := TreeSpread.new()


func test_no_saplings_from_an_empty_tree_list():
	var saplings := spread.propose_saplings([], [], 1, 5)
	assert_eq(saplings.size(), 0)


func test_proposes_up_to_count_saplings():
	var trees := [Vector2(0, 0), Vector2(200, 200), Vector2(400, 0)]
	var saplings := spread.propose_saplings(trees, [], 1, 3)
	assert_lte(saplings.size(), 3)


func test_each_sapling_lands_within_its_parent_trees_spread_radius():
	var trees := [Vector2(500, 500)]
	var saplings := spread.propose_saplings(trees, [], 1, 10)
	var genome := TreeGenome.new(hash("%d_%d" % [500, 500]))
	for sapling in saplings:
		assert_lte(trees[0].distance_to(sapling.position), genome.spread_radius)


func test_saplings_keep_minimum_spacing_from_existing_trees():
	var trees := [Vector2(500, 500)]
	var existing := [Vector2(502, 500)]  # right on top of a likely sapling spot
	var saplings := spread.propose_saplings(trees, existing, 1, 20)
	for sapling in saplings:
		for existing_position in existing:
			assert_gte(sapling.position.distance_to(existing_position), TreeSpread.MIN_TREE_SPACING)


func test_a_saplings_genome_is_a_mutated_child_of_its_parents_genome():
	var trees := [Vector2(500, 500)]
	var saplings := spread.propose_saplings(trees, [], 1, 10)
	var parent_genome := TreeGenome.new(hash("%d_%d" % [500, 500]))
	assert_gt(saplings.size(), 0)
	for sapling in saplings:
		assert_ne(sapling.genome_seed, parent_genome.seed_value)


func test_is_deterministic_for_the_same_tick():
	var trees := [Vector2(500, 500), Vector2(700, 300)]
	var a := spread.propose_saplings(trees, [], 5, 6)
	var b := spread.propose_saplings(trees, [], 5, 6)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].position, b[i].position)
		assert_eq(a[i].genome_seed, b[i].genome_seed)
