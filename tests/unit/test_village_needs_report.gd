extends GutTest

## VillageNeedsReport: every need a village's estates really ask for, what
## they actually got, and which building would answer it
## (docs/concept/village_estates.md mechanism 8).
##
## Asked directly: *"there should be sth. like a graph with every needs that
## can be resolved"*. Every part of that already existed and none of it was
## visible: the estates name the basket, the draw reports satisfaction, and
## the assembly knows the remedy. This is the one place that puts them next
## to each other.
##
## It READS and never computes -- a readout that worked satisfaction or the
## remedy out for itself could disagree with the village it describes.

const VillageNeedsReport = preload("res://src/emergence/village_needs_report.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const VillageAssembly = preload("res://src/emergence/village_assembly.gd")


func _state(extras: Dictionary = {}) -> Dictionary:
	var state := {
		"estate_counts": {"kossaet": 6},
		"household_count": 6,
		"housed_count": 6,
		"present_building_ids": [],
		"building_counts": {},
		"satisfaction": {},
	}
	for key in extras:
		state[key] = extras[key]
	return state


# -- every need is a row ----------------------------------------------------


func test_every_good_the_estates_here_ask_for_is_a_row():
	var rows: Array = VillageNeedsReport.rows_for(_state())
	var seen := {}
	for row in rows:
		seen[row["good"]] = true
	for good in VillageEstates.basket_goods("kossaet"):
		assert_true(seen.has(good), "%s is asked for here and is not in the report" % good)


## A village nobody lives in asks for nothing.
func test_an_empty_village_reports_nothing():
	assert_eq(VillageNeedsReport.rows_for(_state({"estate_counts": {}, "household_count": 0})), [])


## Only the estates really present: a village of cottagers is not reported
## as short of a burgher's luxuries.
func test_a_good_no_estate_here_asks_for_is_not_a_row():
	var rows: Array = VillageNeedsReport.rows_for(_state())
	var kossaet_goods: Array = VillageEstates.basket_goods("kossaet")
	for row in rows:
		assert_true(
			kossaet_goods.has(row["good"]),
			"%s is nobody here's need" % row["good"]
		)


func test_a_row_names_which_estates_ask_for_it():
	var rows: Array = VillageNeedsReport.rows_for(_state({
		"estate_counts": {"kossaet": 4, "buerger": 1},
		"household_count": 5,
		"housed_count": 5,
	}))
	for row in rows:
		assert_gt(Array(row["estates"]).size(), 0, "%s is asked for by nobody" % row["good"])
		for estate in row["estates"]:
			assert_true(
				VillageEstates.basket_goods(estate).has(row["good"]),
				"%s does not ask for %s" % [estate, row["good"]]
			)


# -- it reads rather than computes ------------------------------------------


func test_satisfaction_is_the_draws_own_reading_and_not_a_second_one():
	var rows: Array = VillageNeedsReport.rows_for(_state({
		"satisfaction": {VillageEstates.FUEL_ITEM_ID: 0.25},
	}))
	for row in rows:
		if row["good"] == VillageEstates.FUEL_ITEM_ID:
			assert_almost_eq(float(row["satisfaction"]), 0.25, 0.001)
			return
	fail_test("fuel was not reported at all")


## A good the draw has never reported reads as fully supplied, not as zero:
## a village that has not been assessed is not a starving one.
func test_a_good_never_assessed_is_not_reported_as_starving():
	for row in VillageNeedsReport.rows_for(_state()):
		assert_almost_eq(float(row["satisfaction"]), 1.0, 0.001)


func test_the_remedy_is_the_assemblys_own_answer():
	var rows: Array = VillageNeedsReport.rows_for(_state())
	for row in rows:
		if row["good"] == VillageEstates.FUEL_ITEM_ID:
			assert_eq(row["remedy"], VillageAssembly.REMEDY_BY_GOOD[VillageEstates.FUEL_ITEM_ID])
			assert_true(row["resolvable"])
			return
	fail_test("fuel was not reported at all")


## Rule 2: a need nothing can build is still a row, and says so.
##
## Asked of a village with a BURGHER in it: a cottager's whole basket is
## food and fuel, and both of those really do have a building. The goods no
## ladder makes -- candles, leather, honey -- are the ones the top of the
## order asks for.
func test_a_need_nothing_can_build_is_still_a_row_that_says_so():
	var rows: Array = VillageNeedsReport.rows_for(_state({
		"estate_counts": {"kossaet": 5, "buerger": 1},
		"household_count": 6,
		"housed_count": 6,
	}))
	var unbuildable := 0
	for row in rows:
		if not row["resolvable"]:
			assert_eq(row["remedy"], "", "%s claims a remedy while saying it has none" % row["good"])
			unbuildable += 1
	assert_gt(unbuildable, 0, "the premise: a burgher's basket holds something no ladder makes")


## And food on fishing land is exactly that case -- a fisher's works is
## their own house (mechanism 7), so there is no building to point at.
func test_food_on_fishing_land_reports_no_building_to_raise():
	var rows: Array = VillageNeedsReport.rows_for(_state({"food_trade": "fisher"}))
	for row in rows:
		if row["good"] == VillageEstates.FOOD_KIND_TOKEN:
			assert_false(row["resolvable"], "a fishing village has no farmstead to raise")
			return
	fail_test("food was not reported at all")


func test_food_on_farming_land_points_at_the_farmstead():
	var rows: Array = VillageNeedsReport.rows_for(_state({"food_trade": "farmer"}))
	for row in rows:
		if row["good"] == VillageEstates.FOOD_KIND_TOKEN:
			assert_eq(row["remedy"], "farmhouse")
			return
	fail_test("food was not reported at all")


# -- worst first, and the one the village is actually arguing about ---------


func test_the_worst_supplied_need_is_the_first_row():
	var goods: Array = VillageEstates.basket_goods("kossaet")
	assert_gte(goods.size(), 2, "the premise")
	var rows: Array = VillageNeedsReport.rows_for(_state({
		"satisfaction": {goods[1]: 0.1, goods[0]: 0.9},
	}))
	assert_eq(rows[0]["good"], goods[1])


func test_rows_never_climb_back_out_of_order():
	var rows: Array = VillageNeedsReport.rows_for(_state({
		"satisfaction": {VillageEstates.FUEL_ITEM_ID: 0.3},
	}))
	var previous := -1.0
	for row in rows:
		var level := float(row["satisfaction"])
		if previous >= 0.0:
			assert_lte(previous, level + 0.0001, "the report climbs back down")
		previous = level


## The row the assembly is about to act on is flagged, so a player can see
## the argument being settled rather than infer it.
func test_the_need_the_village_is_about_to_answer_is_flagged():
	var state := _state({
		"satisfaction": {VillageEstates.FUEL_ITEM_ID: 0.1},
		"estate_counts": {"kossaet": 6, "bauer": 2},
		"household_count": 8,
		"housed_count": 8,
	})
	var next_building: String = VillageAssembly.next_building(state)
	assert_ne(next_building, "", "the premise: this village really is about to build something")
	var flagged := 0
	for row in VillageNeedsReport.rows_for(state):
		if row["next"]:
			assert_eq(row["remedy"], next_building)
			flagged += 1
	assert_eq(flagged, 1, "exactly one need is the one being answered")


## Every row carries a name a readout can print without knowing item ids.
func test_every_row_carries_a_readable_label():
	for row in VillageNeedsReport.rows_for(_state()):
		assert_ne(String(row["label"]), "", "%s has no readable name" % row["good"])
