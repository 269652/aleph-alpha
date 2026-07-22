extends GutTest

const EraProgression = preload("res://src/gameplay/era_progression.gd")

var progression: EraProgression

const _EXPECTED_ERAS := ["medieval", "industrial_revolution", "ai_boom", "space_exploration"]


func before_each():
	progression = EraProgression.new()


func test_progress_zero_is_the_first_era():
	assert_eq(progression.current_era(0.0), _EXPECTED_ERAS[0])


func test_progress_past_first_threshold_advances_to_second_era():
	var first_threshold: float = progression.era_definitions()[0]["progress_required"]
	assert_eq(progression.current_era(first_threshold + 1.0), _EXPECTED_ERAS[1])


func test_progress_just_below_first_threshold_stays_in_first_era():
	var first_threshold: float = progression.era_definitions()[0]["progress_required"]
	assert_eq(progression.current_era(first_threshold - 1.0), _EXPECTED_ERAS[0])


func test_progress_past_all_thresholds_stays_at_final_era():
	var last_threshold: float = progression.era_definitions()[-1]["progress_required"]
	assert_eq(progression.current_era(last_threshold + 100000.0), _EXPECTED_ERAS[-1])


func test_era_index_returns_correct_position_for_each_known_era():
	for i in range(_EXPECTED_ERAS.size()):
		assert_eq(progression.era_index(_EXPECTED_ERAS[i]), i)


func test_era_index_returns_negative_one_for_unknown_name():
	assert_eq(progression.era_index("not_a_real_era"), -1)


func test_progress_to_next_era_is_positive_while_not_at_final_era():
	assert_gt(progression.progress_to_next_era(0.0), 0.0)


func test_progress_to_next_era_is_zero_once_at_final_era():
	var last_threshold: float = progression.era_definitions()[-1]["progress_required"]
	assert_eq(progression.progress_to_next_era(last_threshold + 1.0), 0.0)


func test_progress_to_next_era_shrinks_as_progress_approaches_threshold():
	var first_threshold: float = progression.era_definitions()[0]["progress_required"]
	var far_remaining: float = progression.progress_to_next_era(0.0)
	var near_remaining: float = progression.progress_to_next_era(first_threshold - 1.0)
	assert_gt(far_remaining, near_remaining)


func test_era_order_is_internally_consistent_with_strictly_increasing_thresholds():
	var defs: Array = progression.era_definitions()
	for i in range(1, defs.size()):
		assert_gt(float(defs[i]["progress_required"]), float(defs[i - 1]["progress_required"]),
			"expected threshold for '%s' to exceed '%s'" % [defs[i]["name"], defs[i - 1]["name"]])


func test_era_definitions_has_at_least_four_eras_matching_expected_names():
	var defs: Array = progression.era_definitions()
	assert_gte(defs.size(), 4)
	for i in range(_EXPECTED_ERAS.size()):
		assert_eq(defs[i]["name"], _EXPECTED_ERAS[i])


func test_current_era_at_exact_threshold_advances_to_next_era():
	var first_threshold: float = progression.era_definitions()[0]["progress_required"]
	assert_eq(progression.current_era(first_threshold), _EXPECTED_ERAS[1])


## --- current_era_with_boss_defeat (docs/concept/eras.md "Era transitions
## can be boss-gated", docs/concept/worldbosses.md "Era-gated bosses") ----

func test_boss_defeat_false_matches_plain_current_era():
	assert_eq(
		progression.current_era_with_boss_defeat(50.0, false),
		progression.current_era(50.0)
	)


func test_boss_defeat_true_advances_one_era_beyond_progress_alone():
	assert_eq(progression.current_era_with_boss_defeat(0.0, true), _EXPECTED_ERAS[1])


func test_boss_defeat_combines_with_progress_driven_era():
	var first_threshold: float = progression.era_definitions()[0]["progress_required"]
	assert_eq(
		progression.current_era_with_boss_defeat(first_threshold + 1.0, true),
		_EXPECTED_ERAS[2]
	)


func test_boss_defeat_at_final_era_stays_capped():
	var last_threshold: float = progression.era_definitions()[-1]["progress_required"]
	assert_eq(
		progression.current_era_with_boss_defeat(last_threshold + 100000.0, true),
		_EXPECTED_ERAS[-1]
	)
