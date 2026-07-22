extends GutTest

const AnimalFitness = preload("res://src/world/animal_fitness.gd")

const _TRAIT_KEYS := ["strength", "agility", "coat_vibrancy"]

var fitness: AnimalFitness


func before_each():
	fitness = AnimalFitness.new()


func test_phenotype_for_is_deterministic_for_the_same_seed():
	var a: Dictionary = fitness.phenotype_for(42)
	var b: Dictionary = fitness.phenotype_for(42)
	assert_eq(a, b)


func test_phenotype_for_varies_across_different_seeds():
	var samples: Array[Dictionary] = []
	for seed_value in [1, 2, 3, 4, 5]:
		samples.append(fitness.phenotype_for(seed_value))
	var all_identical := true
	for sample in samples:
		if sample != samples[0]:
			all_identical = false
	assert_false(all_identical, "expected phenotype_for to vary across different seeds")


func test_phenotype_for_contains_every_documented_trait_key():
	var phenotype: Dictionary = fitness.phenotype_for(7)
	for trait_key in _TRAIT_KEYS:
		assert_true(phenotype.has(trait_key), "expected phenotype to have key '%s'" % trait_key)


func test_phenotype_for_traits_are_within_zero_one_range():
	for seed_value in [1, 2, 3, 4, 5, 100, 999]:
		var phenotype: Dictionary = fitness.phenotype_for(seed_value)
		for trait_key in _TRAIT_KEYS:
			assert_between(phenotype[trait_key], 0.0, 1.0, "expected trait '%s' to be in [0,1]" % trait_key)


func test_fitness_score_is_non_negative():
	for seed_value in [1, 2, 3, 4, 5]:
		var phenotype: Dictionary = fitness.phenotype_for(seed_value)
		assert_gte(fitness.fitness_score(phenotype), 0.0)


func test_fitness_score_increases_when_strength_increases():
	var low := {"strength": 0.1, "agility": 0.5, "coat_vibrancy": 0.5}
	var high := {"strength": 0.9, "agility": 0.5, "coat_vibrancy": 0.5}
	assert_gt(fitness.fitness_score(high), fitness.fitness_score(low))


func test_fitness_score_increases_when_agility_increases():
	var low := {"strength": 0.5, "agility": 0.1, "coat_vibrancy": 0.5}
	var high := {"strength": 0.5, "agility": 0.9, "coat_vibrancy": 0.5}
	assert_gt(fitness.fitness_score(high), fitness.fitness_score(low))


func test_fitness_score_increases_when_coat_vibrancy_increases():
	var low := {"strength": 0.5, "agility": 0.5, "coat_vibrancy": 0.1}
	var high := {"strength": 0.5, "agility": 0.5, "coat_vibrancy": 0.9}
	assert_gt(fitness.fitness_score(high), fitness.fitness_score(low))


func test_mate_attractiveness_is_symmetric():
	var a: Dictionary = fitness.phenotype_for(11)
	var b: Dictionary = fitness.phenotype_for(22)
	assert_almost_eq(fitness.mate_attractiveness(a, b), fitness.mate_attractiveness(b, a), 0.0001)


func test_mate_attractiveness_is_within_zero_one_range():
	for seed_pair in [[1, 2], [3, 4], [5, 6], [7, 8]]:
		var a: Dictionary = fitness.phenotype_for(seed_pair[0])
		var b: Dictionary = fitness.phenotype_for(seed_pair[1])
		assert_between(fitness.mate_attractiveness(a, b), 0.0, 1.0)


func test_mate_attractiveness_differs_for_different_pairs():
	var a: Dictionary = fitness.phenotype_for(1)
	var b: Dictionary = fitness.phenotype_for(2)
	var c: Dictionary = fitness.phenotype_for(3)
	var d: Dictionary = fitness.phenotype_for(4)
	var score_ab := fitness.mate_attractiveness(a, b)
	var score_cd := fitness.mate_attractiveness(c, d)
	assert_ne(score_ab, score_cd, "expected different phenotype pairs to score differently")
