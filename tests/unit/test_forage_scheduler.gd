extends GutTest

const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TreeGenome = preload("res://src/gameplay/tree_genome.gd")

var scheduler: ForageScheduler


func before_each():
	scheduler = ForageScheduler.new()


func test_no_drops_when_there_are_no_trees():
	assert_eq(scheduler.drops([], 0, 3), [])


func test_returns_the_requested_number_of_drops():
	var trees := [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]
	assert_eq(scheduler.drops(trees, 0, 2).size(), 2)


func test_each_drop_uses_a_tree_position_and_a_forage_id():
	var trees := [Vector2(5, 5), Vector2(9, 9)]
	for drop in scheduler.drops(trees, 3, 4):
		assert_true(trees.has(drop.position), "drop should sit at a tree")
		assert_true(drop.id == "fruit" or drop.id == "nut")


func test_is_deterministic_for_the_same_tick():
	var trees := [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)]
	assert_eq(scheduler.drops(trees, 7, 3), scheduler.drops(trees, 7, 3))


func test_produces_both_fruit_and_nuts_across_many_trees():
	# Varied positions -> varied genomes -- over 30 distinct trees it's
	# vanishingly unlikely every one happens to share the same species lean.
	var trees: Array = []
	for i in 30:
		trees.append(Vector2(i * 37, i * 53))
	var seen := {}
	for drop in scheduler.drops(trees, 0, 30):
		seen[drop.id] = true
	assert_true(seen.has("fruit"))
	assert_true(seen.has("nut"))


func test_genome_for_returns_the_cached_instance_for_the_same_position():
	# A tree's genome is a pure, permanent function of its position -- it
	# never changes for a given tree -- so a second call for the same
	# position must return the SAME TreeGenome instance rather than
	# constructing a new one (this is the hot path in step_fruiting, called
	# once per second for every loaded tree).
	var position := Vector2(42, 99)
	var first := scheduler.genome_for(position)
	var second := scheduler.genome_for(position)
	assert_same(first, second, "genome_for should cache and reuse the TreeGenome for a given position")


func test_species_selection_leans_toward_the_trees_own_genome_bias():
	# DNA-driven: a tree's own species_bias should shape what it tends to
	# drop, not a flat coin flip independent of the tree.
	var position := Vector2(123, 456)
	var genome := TreeGenome.new(hash("%d_%d" % [123, 456]))
	var fruit_count := 0
	var total := 200
	for tick in total:
		var drop = scheduler.drops([position], tick, 1)[0]
		if drop.id == "fruit":
			fruit_count += 1
	var fruit_fraction := float(fruit_count) / total
	assert_almost_eq(fruit_fraction, genome.species_bias, 0.15)
