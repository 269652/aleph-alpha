extends GutTest

const FactionReputation = preload("res://src/gameplay/faction_reputation.gd")

var faction_reputation: FactionReputation


func before_each():
	faction_reputation = FactionReputation.new()


func test_reputation_for_returns_zero_for_unknown_faction():
	assert_eq(faction_reputation.reputation_for("river_clan", {}), 0.0)


func test_reputation_for_returns_stored_value_for_known_faction():
	var reputation: Dictionary = {"river_clan": 42.0}
	assert_eq(faction_reputation.reputation_for("river_clan", reputation), 42.0)


func test_adjust_creates_new_faction_entry_starting_from_zero():
	var result: Dictionary = faction_reputation.adjust("river_clan", 10.0, {})
	assert_eq(result["river_clan"], 10.0)


func test_adjust_modifies_existing_factions_score_by_delta():
	var reputation: Dictionary = {"river_clan": 10.0}
	var result: Dictionary = faction_reputation.adjust("river_clan", 5.0, reputation)
	assert_eq(result["river_clan"], 15.0)


func test_adjust_does_not_mutate_callers_original_dictionary():
	var reputation: Dictionary = {"river_clan": 10.0}
	faction_reputation.adjust("river_clan", 5.0, reputation)
	assert_eq(reputation["river_clan"], 10.0)


func test_adjust_clamps_at_upper_bound():
	var reputation: Dictionary = {"river_clan": 95.0}
	var result: Dictionary = faction_reputation.adjust("river_clan", 50.0, reputation)
	assert_eq(result["river_clan"], 100.0)


func test_adjust_clamps_at_lower_bound():
	var reputation: Dictionary = {"river_clan": -95.0}
	var result: Dictionary = faction_reputation.adjust("river_clan", -50.0, reputation)
	assert_eq(result["river_clan"], -100.0)


func test_adjust_leaves_other_factions_untouched():
	var reputation: Dictionary = {"river_clan": 10.0, "hill_kin": 20.0}
	var result: Dictionary = faction_reputation.adjust("river_clan", 5.0, reputation)
	assert_eq(result["hill_kin"], 20.0)


func test_tier_for_hostile_at_lower_bound():
	assert_eq(faction_reputation.tier_for(-100.0), "hostile")


func test_tier_for_neutral_at_zero_threshold():
	assert_eq(faction_reputation.tier_for(0.0), "neutral")


func test_tier_for_friendly_at_threshold():
	assert_eq(faction_reputation.tier_for(25.0), "friendly")


func test_tier_for_honored_at_threshold():
	assert_eq(faction_reputation.tier_for(75.0), "honored")


func test_tier_for_just_below_neutral_threshold_is_still_hostile():
	assert_eq(faction_reputation.tier_for(-1.0), "hostile")


func test_tier_for_just_below_friendly_threshold_is_still_neutral():
	assert_eq(faction_reputation.tier_for(24.0), "neutral")


func test_tier_for_just_below_honored_threshold_is_still_friendly():
	assert_eq(faction_reputation.tier_for(74.0), "friendly")


func test_tier_for_is_monotonic_across_sampled_scores():
	var tier_rank: Dictionary = {"hostile": 0, "neutral": 1, "friendly": 2, "honored": 3}
	var samples: Array = [-100.0, -50.0, -1.0, 0.0, 10.0, 24.0, 25.0, 50.0, 74.0, 75.0, 90.0, 100.0]
	var previous_rank: int = -1
	for score in samples:
		var rank: int = tier_rank[faction_reputation.tier_for(score)]
		assert_gte(rank, previous_rank)
		previous_rank = rank
