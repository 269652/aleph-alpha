extends GutTest

const CropBreeding = preload("res://src/gameplay/crop_breeding.gd")

var breeding: CropBreeding


func before_each():
	breeding = CropBreeding.new()


func test_cross_pollinate_is_deterministic_for_the_same_three_inputs():
	var a: int = breeding.cross_pollinate(10, 20, 1)
	var b: int = breeding.cross_pollinate(10, 20, 1)
	assert_eq(a, b)


func test_cross_pollinate_different_child_roll_produces_different_child_seed():
	var a: int = breeding.cross_pollinate(10, 20, 1)
	var b: int = breeding.cross_pollinate(10, 20, 2)
	assert_ne(a, b)


func test_cross_pollinate_different_parent_pair_produces_different_child_seed():
	var a: int = breeding.cross_pollinate(10, 20, 1)
	var b: int = breeding.cross_pollinate(30, 40, 1)
	assert_ne(a, b)


func test_trait_rarity_score_is_deterministic_for_the_same_seed_value():
	var a: float = breeding.trait_rarity_score(555)
	var b: float = breeding.trait_rarity_score(555)
	assert_eq(a, b)


func test_trait_rarity_score_varies_across_different_seed_values():
	var scores := []
	for seed_value in [1, 2, 3, 4, 5]:
		scores.append(breeding.trait_rarity_score(seed_value))
	var all_identical := true
	for score in scores:
		if score != scores[0]:
			all_identical = false
			break
	assert_false(all_identical)


func test_trait_rarity_score_stays_within_0_to_1_across_many_sampled_seeds():
	for seed_value in range(200):
		var score: float = breeding.trait_rarity_score(seed_value)
		assert_between(score, 0.0, 1.0)


func test_is_rare_strain_true_when_score_meets_or_exceeds_threshold():
	var seed_value := 42
	var score: float = breeding.trait_rarity_score(seed_value)
	assert_true(breeding.is_rare_strain(seed_value, score))


func test_is_rare_strain_false_when_score_below_threshold():
	var seed_value := 42
	var score: float = breeding.trait_rarity_score(seed_value)
	assert_false(breeding.is_rare_strain(seed_value, score + 0.01))


func test_is_rare_strain_false_for_threshold_above_1():
	assert_false(breeding.is_rare_strain(42, 1.1))


func test_breeding_many_child_rolls_eventually_produces_a_rare_strain():
	var found_rare := false
	for child_roll in range(100):
		var child_seed: int = breeding.cross_pollinate(111, 222, child_roll)
		if breeding.is_rare_strain(child_seed, 0.8):
			found_rare = true
			break
	assert_true(found_rare)
