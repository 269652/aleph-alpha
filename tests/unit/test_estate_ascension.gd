extends GutTest

## EstateAscension: docs/concept/village_estates.md mechanism 3 -- the
## gated ladder, and the half docs/concept/village_growth.md never had.
## That system's population is a ratchet: households only ever arrive. Here
## a household rises only where the CHARTER BUILDING for the next estate
## actually stands, and falls when the goods stop coming -- the bottom rung
## having nowhere to fall to, it leaves.
##
## Pure and static. The dwell counters are run-lengths the caller carries
## and this module advances, never persisted state of its own -- the same
## derived-over-persisted discipline village_growth.md's pillar 5 holds.

const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const ALL_CHARTERS := ["farmhouse", "sawmill", "blacksmith", "city_hall", "brewery", "warehouse"]


func _state(overrides: Dictionary) -> Dictionary:
	var state := {
		"estate": "kossaet",
		"subsistence": 1.0,
		"station": 1.0,
		"present_building_ids": ALL_CHARTERS,
		"good_run_days": EstateAscension.ASCENT_DWELL_DAYS,
		"short_run_days": 0.0,
	}
	state.merge(overrides, true)
	return state


# -- the charter gate, which is the whole of "gated growth" ---------------

## Every ascent names at least one real charter building, and the top rung
## names none because there is nowhere above it.
func test_every_ascent_but_the_last_is_gated_on_a_real_building():
	for estate in VillageEstates.ESTATE_IDS:
		var charters: Array = EstateAscension.charter_building_ids_for(estate)
		if VillageEstates.next_estate(estate) == "":
			assert_eq(charters, [], "%s is the top rung and needs no charter" % estate)
			continue
		assert_false(charters.is_empty(), "%s can rise with no building standing" % estate)


## You cannot be a husbandman where there is no farm.
func test_a_cottager_rises_only_where_a_farm_stands():
	assert_eq(EstateAscension.verdict(_state({"present_building_ids": ["sawmill", "city_hall"]})), EstateAscension.HOLD)
	assert_eq(EstateAscension.verdict(_state({"present_building_ids": ["farmhouse"]})), EstateAscension.ASCEND)


## A trade to be apprenticed into -- either workshop will do, which is why
## the gate is a list rather than one id.
func test_a_husbandman_rises_into_either_real_workshop():
	for workshop in ["sawmill", "blacksmith"]:
		assert_eq(
			EstateAscension.verdict(_state({"estate": "bauer", "present_building_ids": [workshop]})),
			EstateAscension.ASCEND,
			"a %s is no apprenticeship" % workshop
		)


func test_a_husbandman_with_no_workshop_at_all_holds():
	assert_eq(
		EstateAscension.verdict(_state({"estate": "bauer", "present_building_ids": ["farmhouse", "warehouse"]})),
		EstateAscension.HOLD
	)


## Civic rights are granted by a civic seat.
func test_a_craftsman_rises_only_where_the_civic_seat_stands():
	assert_eq(
		EstateAscension.verdict(_state({"estate": "handwerker", "present_building_ids": ["brewery"]})),
		EstateAscension.HOLD
	)
	assert_eq(
		EstateAscension.verdict(_state({"estate": "handwerker", "present_building_ids": ["city_hall"]})),
		EstateAscension.ASCEND
	)


func test_the_top_rung_has_nowhere_to_rise_to_however_well_provided():
	assert_eq(EstateAscension.verdict(_state({"estate": "buerger"})), EstateAscension.HOLD)


## The charter is a real BuildingCatalog building the growth ladder
## actually raises -- a gate on a building nothing ever builds is a gate
## nothing ever passes.
func test_every_charter_is_a_building_the_growth_ladder_really_raises():
	var VillageGrowth = load("res://src/emergence/village_growth.gd")
	for estate in VillageEstates.ESTATE_IDS:
		for charter in EstateAscension.charter_building_ids_for(estate):
			assert_true(
				VillageGrowth.LADDER_BUILDING_IDS.has(charter),
				"%s is gated on %s, which no village ever builds" % [estate, charter]
			)


# -- provision ------------------------------------------------------------

func test_a_household_short_of_its_own_subsistence_does_not_rise():
	assert_eq(EstateAscension.verdict(_state({"subsistence": 0.9})), EstateAscension.HOLD)


func test_a_household_below_its_station_does_not_rise():
	assert_eq(
		EstateAscension.verdict(_state({"station": EstateAscension.STATION_THRESHOLD - 0.01})),
		EstateAscension.HOLD
	)


func test_a_household_exactly_at_its_station_threshold_rises():
	assert_eq(
		EstateAscension.verdict(_state({"station": EstateAscension.STATION_THRESHOLD})),
		EstateAscension.ASCEND
	)


# -- dwell: a single good week does not make a burgher --------------------

func test_a_household_that_has_only_just_started_doing_well_holds():
	assert_eq(EstateAscension.verdict(_state({"good_run_days": 0.0})), EstateAscension.HOLD)
	assert_eq(
		EstateAscension.verdict(_state({"good_run_days": EstateAscension.ASCENT_DWELL_DAYS - 0.01})),
		EstateAscension.HOLD
	)


## Grounded rather than eyeballed: a household rises after holding its
## standard for one whole SEASON of the real world clock.
func test_the_ascent_dwell_is_one_real_season():
	assert_almost_eq(
		EstateAscension.ASCENT_DWELL_DAYS,
		SeasonCycle.DAYS_PER_YEAR / float(SeasonCycle.SEASONS.size()),
		0.0001
	)


## A village unmakes itself faster than it makes itself. That is what a
## famine is, and it is why the two dwells are not one constant.
func test_a_village_falls_faster_than_it_rises():
	assert_true(EstateAscension.DECLINE_DWELL_DAYS < EstateAscension.ASCENT_DWELL_DAYS)


# -- descent and exodus ---------------------------------------------------

func test_a_household_starved_for_long_enough_loses_its_standing():
	var state := _state({
		"estate": "handwerker",
		"subsistence": 0.0,
		"short_run_days": EstateAscension.DECLINE_DWELL_DAYS,
	})
	assert_eq(EstateAscension.verdict(state), EstateAscension.DESCEND)


func test_a_bad_week_is_not_yet_a_descent():
	var state := _state({
		"estate": "handwerker",
		"subsistence": 0.0,
		"short_run_days": EstateAscension.DECLINE_DWELL_DAYS - 0.01,
	})
	assert_eq(EstateAscension.verdict(state), EstateAscension.HOLD)


## Merely below full is not starving: the floor is what going short
## actually means, and a household a little short of a full ration keeps
## its standing.
func test_a_household_a_little_short_keeps_its_standing():
	var state := _state({
		"estate": "handwerker",
		"subsistence": EstateAscension.SUBSISTENCE_FLOOR,
		"short_run_days": EstateAscension.DECLINE_DWELL_DAYS * 10.0,
	})
	assert_eq(EstateAscension.verdict(state), EstateAscension.HOLD)


## Starvation outranks a full station: a household cannot be rising and
## falling at once, and which way it goes is never in doubt.
func test_starvation_outranks_every_claim_to_rise():
	var state := _state({
		"estate": "bauer",
		"subsistence": 0.0,
		"station": 1.0,
		"good_run_days": EstateAscension.ASCENT_DWELL_DAYS * 10.0,
		"short_run_days": EstateAscension.DECLINE_DWELL_DAYS,
	})
	assert_eq(EstateAscension.verdict(state), EstateAscension.DESCEND)


## The bottom rung has nowhere to descend to, so a descent there is the
## household leaving the village altogether -- the departure path
## village_growth.md's immigration never had.
func test_the_bottom_rung_descending_is_the_household_leaving():
	assert_true(EstateAscension.is_exodus(VillageEstates.ESTATE_IDS[0]))
	for estate in VillageEstates.ESTATE_IDS.slice(1):
		assert_false(EstateAscension.is_exodus(estate), "%s has somewhere to fall to" % estate)


func test_a_descent_that_is_not_an_exodus_lands_on_the_rung_below():
	assert_eq(EstateAscension.resolve("handwerker", EstateAscension.DESCEND), "bauer")
	assert_eq(EstateAscension.resolve("kossaet", EstateAscension.ASCEND), "bauer")
	assert_eq(EstateAscension.resolve("bauer", EstateAscension.HOLD), "bauer")


## An exodus resolves to no estate at all -- the caller reads that as the
## household leaving rather than as a fifth rung.
func test_an_exodus_resolves_to_no_estate():
	assert_eq(EstateAscension.resolve("kossaet", EstateAscension.DESCEND), "")


# -- the run-lengths the verdict is read against --------------------------

func test_a_good_span_lengthens_the_good_run_and_clears_the_short_one():
	var runs: Dictionary = EstateAscension.advanced_runs("bauer", 1.0, 1.0, 3.0, 5.0, 2.0)
	assert_almost_eq(float(runs["good_run_days"]), 5.0, 0.0001)
	assert_almost_eq(float(runs["short_run_days"]), 0.0, 0.0001)


func test_a_starving_span_lengthens_the_short_run_and_clears_the_good_one():
	var runs: Dictionary = EstateAscension.advanced_runs("bauer", 0.0, 0.0, 9.0, 1.0, 2.0)
	assert_almost_eq(float(runs["good_run_days"]), 0.0, 0.0001)
	assert_almost_eq(float(runs["short_run_days"]), 3.0, 0.0001)


## Fed but unstationed is neither: the household is in no danger and has no
## claim, so BOTH runs are clear.
func test_a_fed_but_unstationed_span_clears_both_runs():
	var runs: Dictionary = EstateAscension.advanced_runs("bauer", 1.0, 0.0, 9.0, 9.0, 2.0)
	assert_almost_eq(float(runs["good_run_days"]), 0.0, 0.0001)
	assert_almost_eq(float(runs["short_run_days"]), 0.0, 0.0001)


## Runs accumulate across short steps exactly as one long step would, so a
## village assessed often is not held back against one assessed rarely.
func test_many_short_spans_accumulate_to_the_same_run_as_one_long_one():
	var short_steps := 0.0
	for _i in 10:
		short_steps = float(EstateAscension.advanced_runs("bauer", 1.0, 1.0, short_steps, 0.0, 0.5)["good_run_days"])
	var one_long: float = float(EstateAscension.advanced_runs("bauer", 1.0, 1.0, 0.0, 0.0, 5.0)["good_run_days"])
	assert_almost_eq(short_steps, one_long, 0.0001)


func test_a_span_of_no_time_moves_no_run():
	var runs: Dictionary = EstateAscension.advanced_runs("bauer", 1.0, 1.0, 4.0, 2.0, 0.0)
	assert_almost_eq(float(runs["good_run_days"]), 4.0, 0.0001)
	assert_almost_eq(float(runs["short_run_days"]), 2.0, 0.0001)


## The top rung can never bank a good run it has no use for -- otherwise
## every burgher in the world carries an ever-growing counter nothing ever
## reads.
func test_the_top_rung_banks_no_good_run():
	var runs: Dictionary = EstateAscension.advanced_runs("buerger", 1.0, 1.0, 0.0, 0.0, 30.0)
	assert_almost_eq(float(runs["good_run_days"]), 0.0, 0.0001)
