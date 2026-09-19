extends GutTest

## EstateConsumption: docs/concept/village_estates.md mechanism 2 -- the
## single change everything else in that doc hangs off. A need is a FLOW,
## not a reading: the goods a household needs actually LEAVE the market,
## and the same unit cannot satisfy two households.
##
## Pure and static. Fractions carry the same whole-units-out way
## SettlementGathering/VillageImmigration already do, so a short step loses
## nothing; the draw never goes into debt and never partially refuses -- a
## village with half the firewood burns half the firewood and is half warm.

const EstateConsumption = preload("res://src/emergence/estate_consumption.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")

const FOOD := VillageEstates.FOOD_KIND_TOKEN
const FUEL := VillageEstates.FUEL_ITEM_ID


func _one_day(counts: Dictionary, season: String = "spring") -> Dictionary:
	return EstateConsumption.demand_for(counts, 1.0, season)


func test_a_village_with_nobody_in_it_demands_nothing():
	assert_eq(_one_day({}), {})
	assert_eq(_one_day({"kossaet": 0}), {})


func test_one_household_for_one_day_demands_exactly_its_own_basket():
	var demand: Dictionary = _one_day({"kossaet": 1})
	assert_almost_eq(float(demand[FOOD]), VillageEstates.subsistence_basket("kossaet")[FOOD], 0.0001)
	assert_almost_eq(
		float(demand["herb"]), VillageEstates.station_basket("kossaet")["herb"], 0.0001
	)


## The same unit cannot feed two households -- pillar 1 in one assertion.
func test_demand_scales_with_the_number_of_households():
	var one: Dictionary = _one_day({"bauer": 1})
	var four: Dictionary = _one_day({"bauer": 4})
	assert_almost_eq(float(four[FOOD]), float(one[FOOD]) * 4.0, 0.0001)


func test_demand_scales_with_the_days_elapsed():
	var one_day: Dictionary = EstateConsumption.demand_for({"bauer": 2}, 1.0, "spring")
	var three_days: Dictionary = EstateConsumption.demand_for({"bauer": 2}, 3.0, "spring")
	assert_almost_eq(float(three_days[FUEL]), float(one_day[FUEL]) * 3.0, 0.0001)


func test_a_span_of_no_time_at_all_demands_nothing():
	assert_eq(EstateConsumption.demand_for({"buerger": 5}, 0.0, "winter"), {})
	assert_eq(EstateConsumption.demand_for({"buerger": 5}, -3.0, "winter"), {})


## Mixed estates share the goods they have in common and each brings its
## own -- a village is a mix, not a tier.
func test_a_mixed_village_sums_the_goods_its_estates_share():
	var mixed: Dictionary = _one_day({"kossaet": 1, "buerger": 1})
	var expected: float = (
		float(VillageEstates.subsistence_basket("kossaet")[FOOD])
		+ float(VillageEstates.subsistence_basket("buerger")[FOOD])
	)
	assert_almost_eq(float(mixed[FOOD]), expected, 0.0001)
	assert_true(mixed.has("herb"), "the cottager's own station good went missing")
	assert_true(mixed.has("beer"), "the burgher's own station good went missing")


## The seasonal term reaches the real village draw, not just the table.
func test_a_village_draws_strictly_more_fuel_in_winter_than_in_summer():
	var winter: Dictionary = EstateConsumption.demand_for({"bauer": 3}, 1.0, "winter")
	var summer: Dictionary = EstateConsumption.demand_for({"bauer": 3}, 1.0, "summer")
	assert_true(float(winter[FUEL]) > float(summer[FUEL]))
	assert_almost_eq(float(winter[FOOD]), float(summer[FOOD]), 0.0001, "food moved with the season")


func test_an_unknown_estate_in_the_census_demands_nothing_rather_than_crashing():
	assert_eq(_one_day({"emperor": 10}), {})


# -- the draw ------------------------------------------------------------

func test_a_full_store_covers_the_whole_draw_and_every_good_is_satisfied():
	var result: Dictionary = EstateConsumption.draw({FUEL: 2.0, "herb": 1.0}, {"wood": 50.0, "herb": 9.0}, [])
	assert_almost_eq(float(result["satisfaction"][FUEL]), 1.0, 0.0001)
	assert_almost_eq(float(result["satisfaction"]["herb"]), 1.0, 0.0001)
	assert_almost_eq(float(result["stock"]["wood"]), 48.0, 0.0001)
	assert_almost_eq(float(result["stock"]["herb"]), 8.0, 0.0001)


## Half the firewood, half warm -- it does not refuse and it does not go
## into debt.
func test_a_half_stocked_store_covers_half_the_draw_and_says_so():
	var result: Dictionary = EstateConsumption.draw({FUEL: 4.0}, {"wood": 2.0}, [])
	assert_almost_eq(float(result["satisfaction"][FUEL]), 0.5, 0.0001)
	assert_almost_eq(float(result["taken"][FUEL]), 2.0, 0.0001)
	assert_almost_eq(float(result["stock"].get("wood", 0.0)), 0.0, 0.0001)


func test_an_empty_store_covers_nothing_and_stock_never_goes_negative():
	var result: Dictionary = EstateConsumption.draw({FUEL: 4.0}, {}, [])
	assert_almost_eq(float(result["satisfaction"][FUEL]), 0.0, 0.0001)
	assert_true(float(result["stock"].get("wood", 0.0)) >= 0.0)


func test_the_draw_never_touches_a_good_it_was_not_asked_for():
	var result: Dictionary = EstateConsumption.draw({FUEL: 1.0}, {"wood": 5.0, "stone": 9.0}, [])
	assert_almost_eq(float(result["stock"]["stone"]), 9.0, 0.0001)


func test_the_draw_leaves_the_callers_own_stock_dictionary_untouched():
	var stock := {"wood": 5.0}
	EstateConsumption.draw({FUEL: 2.0}, stock, [])
	assert_almost_eq(float(stock["wood"]), 5.0, 0.0001, "the draw mutated the caller's stock")


## `kind:food` is not an item id: it spends whatever real food the village
## actually has.
func test_the_food_token_is_satisfied_by_whatever_real_food_the_village_has():
	var result: Dictionary = EstateConsumption.draw(
		{FOOD: 3.0}, {"bread": 2.0, "cooked_fish": 4.0}, ["bread", "cooked_fish"]
	)
	assert_almost_eq(float(result["satisfaction"][FOOD]), 1.0, 0.0001)
	var left: float = float(result["stock"].get("bread", 0.0)) + float(result["stock"].get("cooked_fish", 0.0))
	assert_almost_eq(left, 3.0, 0.0001, "three meals were eaten out of six units of food")


## A glut is eaten down before a scarcity -- the most plentiful food goes
## first, so one rare good is not spent while a pile of another rots.
func test_the_most_plentiful_food_is_eaten_first():
	var result: Dictionary = EstateConsumption.draw(
		{FOOD: 2.0}, {"apple": 1.0, "bread": 8.0}, ["apple", "bread"]
	)
	assert_almost_eq(float(result["stock"]["apple"]), 1.0, 0.0001, "the last apple was eaten first")
	assert_almost_eq(float(result["stock"]["bread"]), 6.0, 0.0001)


## Deterministic: a tie between two equally stocked foods breaks on item
## id, never on Dictionary iteration order.
func test_a_tie_between_two_equally_stocked_foods_breaks_on_item_id():
	var result: Dictionary = EstateConsumption.draw({FOOD: 1.0}, {"bread": 2.0, "apple": 2.0}, ["bread", "apple"])
	assert_almost_eq(float(result["stock"]["apple"]), 1.0, 0.0001, "the tie did not break on id")
	assert_almost_eq(float(result["stock"]["bread"]), 2.0, 0.0001)


func test_a_village_with_food_in_store_but_none_of_it_listed_as_food_eats_nothing():
	var result: Dictionary = EstateConsumption.draw({FOOD: 2.0}, {"bread": 9.0}, [])
	assert_almost_eq(float(result["satisfaction"][FOOD]), 0.0, 0.0001)
	assert_almost_eq(float(result["stock"]["bread"]), 9.0, 0.0001)


# -- collapsing to an estate's own verdict -------------------------------

## The MINIMUM, not the mean: a household with all the bread in the world
## and no fuel is not eighty percent provided for, it is cold. That is what
## makes one missing good a real crisis, which is how an Anno supply chain
## actually fails.
func test_an_estates_satisfaction_is_its_worst_good_not_its_average():
	var satisfaction := {FOOD: 1.0, FUEL: 0.0}
	assert_almost_eq(
		EstateConsumption.subsistence_satisfaction("kossaet", satisfaction), 0.0, 0.0001
	)


func test_a_fully_supplied_estate_reads_fully_satisfied():
	var satisfaction := {FOOD: 1.0, FUEL: 1.0, "herb": 1.0}
	assert_almost_eq(
		EstateConsumption.subsistence_satisfaction("kossaet", satisfaction), 1.0, 0.0001
	)
	assert_almost_eq(EstateConsumption.station_satisfaction("kossaet", satisfaction), 1.0, 0.0001)


## Subsistence and station are read separately: a household can be fed and
## warm and still have no claim to rise.
func test_station_can_be_empty_while_subsistence_is_whole():
	var satisfaction := {FOOD: 1.0, FUEL: 1.0, "herb": 0.0}
	assert_almost_eq(
		EstateConsumption.subsistence_satisfaction("kossaet", satisfaction), 1.0, 0.0001
	)
	assert_almost_eq(EstateConsumption.station_satisfaction("kossaet", satisfaction), 0.0, 0.0001)


## A good the report says nothing about was not supplied -- the destitute
## default, the same reading HouseholdWellbeing already takes of a missing
## input.
func test_a_good_the_report_never_mentions_reads_as_unsupplied():
	assert_almost_eq(EstateConsumption.subsistence_satisfaction("bauer", {}), 0.0, 0.0001)


## An estate that claims no station at all is not thereby destitute: it has
## nothing to be short of, so it is satisfied. Without this a rung with an
## empty station basket could never ascend.
func test_an_estate_with_an_empty_station_basket_is_station_satisfied():
	assert_almost_eq(EstateConsumption.station_satisfaction("emperor", {}), 1.0, 0.0001)
