extends GutTest

const CozinessScore = preload("res://src/gameplay/coziness_score.gd")

var scorer: CozinessScore


func before_each():
	scorer = CozinessScore.new()


func test_single_item_score_equals_its_base_appeal():
	var score: float = scorer.total_score(["wooden_chair"])
	assert_almost_eq(score, 3.0, 0.001)


func test_multiple_items_different_themes_sum_without_coherence_bonus():
	# 1 rustic + 1 modern + 1 cozy -- no theme reaches the 3-item threshold.
	var score: float = scorer.total_score(["wooden_chair", "steel_lamp", "wool_rug"])
	assert_almost_eq(score, 3.0 + 3.0 + 3.0, 0.001)


func test_three_items_sharing_a_theme_trigger_coherence_bonus():
	var plain_sum: float = 3.0 + 6.0 + 4.0
	var score: float = scorer.total_score(["wooden_chair", "stone_hearth", "oak_table"])
	assert_true(score > plain_sum)


func test_coherence_bonus_is_exactly_twenty_percent_of_theme_subtotal():
	var theme_subtotal: float = 3.0 + 6.0 + 4.0
	var expected: float = theme_subtotal + theme_subtotal * 0.2
	var score: float = scorer.total_score(["wooden_chair", "stone_hearth", "oak_table"])
	assert_almost_eq(score, expected, 0.001)


func test_two_separate_theme_groups_each_qualify_for_their_own_bonus():
	var rustic_subtotal: float = 3.0 + 6.0 + 4.0
	var modern_subtotal: float = 3.0 + 4.0 + 2.0
	var expected: float = rustic_subtotal + rustic_subtotal * 0.2 + modern_subtotal + modern_subtotal * 0.2
	var score: float = scorer.total_score([
		"wooden_chair", "stone_hearth", "oak_table",
		"steel_lamp", "glass_shelf", "chrome_stool",
	])
	assert_almost_eq(score, expected, 0.001)


func test_unknown_furniture_id_contributes_zero_and_does_not_crash():
	var score: float = scorer.total_score(["not_a_real_item"])
	assert_almost_eq(score, 0.0, 0.001)


func test_unknown_furniture_id_mixed_with_known_ids_is_ignored():
	var score: float = scorer.total_score(["wooden_chair", "not_a_real_item"])
	assert_almost_eq(score, 3.0, 0.001)


func test_empty_array_scores_zero():
	var score: float = scorer.total_score([])
	assert_almost_eq(score, 0.0, 0.001)


func test_dominant_theme_identifies_most_represented_theme():
	var theme: String = scorer.dominant_theme(["wooden_chair", "stone_hearth", "steel_lamp"])
	assert_eq(theme, "rustic")


func test_dominant_theme_returns_empty_string_on_a_tie():
	var theme: String = scorer.dominant_theme(["wooden_chair", "steel_lamp"])
	assert_eq(theme, "")


func test_dominant_theme_returns_empty_string_for_empty_list():
	var theme: String = scorer.dominant_theme([])
	assert_eq(theme, "")


func test_dominant_theme_returns_empty_string_for_all_unknown_ids():
	var theme: String = scorer.dominant_theme(["not_a_real_item", "also_fake"])
	assert_eq(theme, "")


func test_dominant_theme_ignores_unknown_ids_when_counting():
	var theme: String = scorer.dominant_theme(["wooden_chair", "stone_hearth", "not_a_real_item"])
	assert_eq(theme, "rustic")
