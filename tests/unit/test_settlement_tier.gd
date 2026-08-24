extends GutTest

## SettlementTier: a settlement's town/city classification and what it
## specializes in, both derived from real flows (see
## docs/emergence/04-settlements-cities-infrastructure.md "City threshold"/
## "Specialization").

const SettlementTier = preload("res://src/emergence/settlement_tier.gd")


# -- tier_for requires ALL dimensions, never population alone ---------------

func test_an_empty_settlement_is_a_hamlet():
	assert_eq(SettlementTier.tier_for(0, 0, 0), SettlementTier.HAMLET)


## The doc's own explicit point: population alone is never enough.
func test_high_population_alone_stays_a_hamlet():
	assert_eq(SettlementTier.tier_for(50, 0, 0), SettlementTier.HAMLET)


func test_crossing_all_three_town_thresholds_becomes_a_town():
	assert_eq(
		SettlementTier.tier_for(
			SettlementTier.TOWN_HOUSEHOLDS,
			SettlementTier.TOWN_INSTITUTIONS,
			SettlementTier.TOWN_PRODUCTION_DIVERSITY,
		),
		SettlementTier.TOWN,
	)


func test_missing_one_town_dimension_stays_a_hamlet():
	assert_eq(
		SettlementTier.tier_for(SettlementTier.TOWN_HOUSEHOLDS, SettlementTier.TOWN_INSTITUTIONS, 0),
		SettlementTier.HAMLET,
	)


func test_crossing_all_three_city_thresholds_becomes_a_city():
	assert_eq(
		SettlementTier.tier_for(
			SettlementTier.CITY_HOUSEHOLDS,
			SettlementTier.CITY_INSTITUTIONS,
			SettlementTier.CITY_PRODUCTION_DIVERSITY,
		),
		SettlementTier.CITY,
	)


func test_missing_one_city_dimension_stays_a_town():
	assert_eq(
		SettlementTier.tier_for(
			SettlementTier.CITY_HOUSEHOLDS, SettlementTier.CITY_INSTITUTIONS, SettlementTier.TOWN_PRODUCTION_DIVERSITY
		),
		SettlementTier.TOWN,
	)


func test_every_documented_tier_exists():
	var expected := ["hamlet", "town", "city"]
	for tier in expected:
		assert_true(SettlementTier.TIERS.has(tier), "missing tier: %s" % tier)


# -- specialization_for is derived from real production flows ---------------

func test_specialization_of_no_production_is_empty_string():
	assert_eq(SettlementTier.specialization_for({}), "")


func test_dominant_recipe_determines_specialization():
	var counts := {"cooked_meat": 5, "stone_pickaxe": 2}
	assert_eq(SettlementTier.specialization_for(counts), "hunting center")


## A tie breaks toward whichever recipe id sorts first, deterministically --
## not Dictionary iteration order.
func test_a_tie_breaks_toward_the_alphabetically_first_recipe():
	var counts := {"stone_pickaxe": 3, "cooked_meat": 3}
	assert_eq(SettlementTier.specialization_for(counts), "hunting center")


func test_an_unmapped_dominant_recipe_returns_empty_string():
	assert_eq(SettlementTier.specialization_for({"unknown_recipe": 5}), "")
