extends GutTest

const DnaCrossover = preload("res://src/gameplay/dna_crossover.gd")

var crossover: DnaCrossover
var parent_a: Dictionary
var parent_b: Dictionary


func before_each():
	crossover = DnaCrossover.new()
	parent_a = {"strength": 10.0, "agility": 4.0, "vision": 20.0}
	parent_b = {"strength": 6.0, "agility": 8.0, "stealth": 5.0}


func test_child_has_exactly_the_intersection_of_both_parents_trait_keys():
	var child := crossover.crossover(parent_a, parent_b, 1)
	assert_eq(child.keys().size(), 2)
	assert_true(child.has("strength"))
	assert_true(child.has("agility"))


func test_trait_key_present_in_only_one_parent_is_excluded_from_child():
	var child := crossover.crossover(parent_a, parent_b, 1)
	assert_false(child.has("vision"))
	assert_false(child.has("stealth"))


func test_crossover_with_no_shared_keys_produces_an_empty_child():
	var child := crossover.crossover({"vision": 20.0}, {"stealth": 5.0}, 1)
	assert_eq(child, {})


func test_crossover_is_deterministic_for_the_same_parents_and_seed():
	var child_1 := crossover.crossover(parent_a, parent_b, 99)
	var child_2 := crossover.crossover(parent_a, parent_b, 99)
	assert_eq(child_1, child_2)


func test_different_child_seed_produces_a_different_child():
	var child_1 := crossover.crossover(parent_a, parent_b, 1)
	var child_2 := crossover.crossover(parent_a, parent_b, 2)
	var any_differs := false
	for trait_name in child_1.keys():
		if child_1[trait_name] != child_2[trait_name]:
			any_differs = true
	assert_true(any_differs)


func test_each_child_trait_value_is_reasonably_close_to_one_parent():
	for seed_value in range(30):
		var child: Dictionary = crossover.crossover(parent_a, parent_b, seed_value)
		for trait_name in child.keys():
			var tolerance: float = maxf(
				DnaCrossover.MUTATION_AMOUNT * absf(parent_a[trait_name] - parent_b[trait_name]),
				DnaCrossover.MUTATION_FLOOR
			)
			var distance_to_a: float = absf(child[trait_name] - parent_a[trait_name])
			var distance_to_b: float = absf(child[trait_name] - parent_b[trait_name])
			assert_true(
				distance_to_a <= tolerance or distance_to_b <= tolerance,
				"trait %s child value %f not within tolerance of either parent" % [trait_name, child[trait_name]]
			)


func test_across_many_seeds_child_sometimes_leans_toward_each_parent():
	var wide_a := {"size": 0.0}
	var wide_b := {"size": 100.0}
	var leans_a := false
	var leans_b := false
	for seed_value in range(200):
		var child: Dictionary = crossover.crossover(wide_a, wide_b, seed_value)
		var size_value: float = child["size"]
		if size_value < 50.0:
			leans_a = true
		else:
			leans_b = true
	assert_true(leans_a, "expected at least one seed to inherit close to parent A")
	assert_true(leans_b, "expected at least one seed to inherit close to parent B")


func test_child_is_not_identical_to_either_parent():
	var wide_a := {"size": 0.0}
	var wide_b := {"size": 100.0}
	var found_mutated := false
	for seed_value in range(50):
		var child: Dictionary = crossover.crossover(wide_a, wide_b, seed_value)
		if child["size"] != wide_a["size"] and child["size"] != wide_b["size"]:
			found_mutated = true
	assert_true(found_mutated, "expected the mutation nudge to move the child away from both parents at least once")


func test_child_only_contains_shared_keys_even_when_parent_a_has_extra_keys():
	var a_with_extra := {"strength": 10.0, "extra_only_a": 3.0}
	var b_normal := {"strength": 6.0}
	var child := crossover.crossover(a_with_extra, b_normal, 5)
	assert_false(child.has("extra_only_a"))
	assert_true(child.has("strength"))


func test_child_only_contains_shared_keys_even_when_parent_b_has_extra_keys():
	var a_normal := {"strength": 10.0}
	var b_with_extra := {"strength": 6.0, "extra_only_b": 3.0}
	var child := crossover.crossover(a_normal, b_with_extra, 5)
	assert_false(child.has("extra_only_b"))
	assert_true(child.has("strength"))


func test_empty_parent_dictionaries_produce_an_empty_child():
	var child := crossover.crossover({}, {}, 1)
	assert_eq(child, {})
