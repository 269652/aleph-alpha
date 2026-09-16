extends GutTest

## VillageImmigration: docs/concept/village_growth.md mechanism 3 -- a
## village that is fed and has room attracts new households over time.
## Without this the ladder is a ladder nothing ever walks up
## (SettlementGenerator's population is a fixed 5). Same carry-the-fraction,
## whole-units-out shape SettlementGathering/SettlementGranary already use.

const VillageImmigration = preload("res://src/emergence/village_immigration.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

const _DAY := ConstructionCatchup.SECONDS_PER_DAY
const _WELL_FED := VillageImmigration.FED_THRESHOLD * 2.0


func _arrivals(seconds: float, food: float, spare: int, room: bool, ladder: float, carry: float) -> Dictionary:
	return VillageImmigration.arrivals(seconds, food, spare, room, ladder, carry)


func test_a_hungry_village_attracts_nobody_however_much_room_it_has():
	var out: Dictionary = _arrivals(_DAY * 30.0, VillageImmigration.FED_THRESHOLD - 0.01, 9, true, 1.0, 0.0)
	assert_eq(out["arrivals"], 0)


func test_a_village_with_no_room_at_all_attracts_nobody_however_rich():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED * 4.0, 0, false, 1.0, 0.0)
	assert_eq(out["arrivals"], 0)


func test_a_fed_village_with_frontage_to_build_on_takes_people_in():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 0, true, 0.0, 0.0)
	assert_gt(out["arrivals"], 0, "room to build is room enough")


func test_a_fed_village_with_a_spare_roof_takes_people_in():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 2, false, 0.0, 0.0)
	assert_gt(out["arrivals"], 0)


## The gates are what stop arrivals, never the clock: no time, no arrivals.
func test_no_elapsed_time_means_no_arrivals_and_an_untouched_carry():
	var out: Dictionary = _arrivals(0.0, _WELL_FED, 5, true, 1.0, 0.4)
	assert_eq(out["arrivals"], 0)
	assert_almost_eq(float(out["carry"]), 0.4, 0.0001)


func test_a_blocked_village_keeps_its_carry_rather_than_losing_it():
	var out: Dictionary = _arrivals(_DAY, VillageImmigration.FED_THRESHOLD - 1.0, 5, true, 1.0, 0.9)
	assert_almost_eq(float(out["carry"]), 0.9, 0.0001)


func test_the_sub_unit_remainder_is_carried_into_the_next_step():
	var step: float = _DAY * 0.5
	var carry := 0.0
	var total := 0
	for i in 20:
		var out: Dictionary = _arrivals(step, _WELL_FED, 9, true, 0.0, carry)
		total += int(out["arrivals"])
		carry = float(out["carry"])
		assert_between(carry, 0.0, 1.0, "the carry is always a real fraction")
	var one_shot: Dictionary = _arrivals(step * 20.0, _WELL_FED, 9, true, 0.0, 0.0)
	assert_eq(total, int(one_shot["arrivals"]), "twenty short steps must arrive at the same count as one long one")


# -- what makes a village attractive --------------------------------------

func test_a_village_with_a_full_larder_draws_faster_than_a_barely_fed_one():
	var barely: Dictionary = _arrivals(_DAY * 100.0, VillageImmigration.FED_THRESHOLD, 99, true, 0.0, 0.0)
	var full: Dictionary = _arrivals(_DAY * 100.0, _WELL_FED * 4.0, 99, true, 0.0, 0.0)
	assert_gt(int(full["arrivals"]), int(barely["arrivals"]))


func test_a_village_with_its_ladder_up_draws_faster_than_a_bare_hamlet():
	var bare: Dictionary = _arrivals(_DAY * 100.0, _WELL_FED, 99, true, 0.0, 0.0)
	var built: Dictionary = _arrivals(_DAY * 100.0, _WELL_FED, 99, true, 1.0, 0.0)
	assert_gt(int(built["arrivals"]), int(bare["arrivals"]))


## Nobody moves into a village whose larder has not reached the threshold,
## and the threshold must sit below what the wellbeing model calls a full
## larder -- a village has to be somewhat comfortable before it grows, not
## perfectly provisioned.
func test_the_fed_threshold_sits_below_a_full_larder():
	assert_gt(VillageImmigration.FED_THRESHOLD, 0.0)
	assert_lt(VillageImmigration.FED_THRESHOLD, HouseholdWellbeing.FOOD_STOCK_PER_HOUSEHOLD_TARGET)


# -- the cap: more people than there is room for simply go elsewhere ------

func test_arrivals_never_exceed_the_room_the_village_actually_has():
	var out: Dictionary = _arrivals(_DAY * 365.0, _WELL_FED * 8.0, 2, true, 1.0, 0.0)
	assert_lte(int(out["arrivals"]), 3, "two spare roofs plus one plot to build on is three households")


func test_the_carry_never_banks_a_crowd_for_later():
	var out: Dictionary = _arrivals(_DAY * 365.0, _WELL_FED * 8.0, 0, true, 1.0, 0.0)
	assert_between(float(out["carry"]), 0.0, 1.0, "a year of demand must not bank as a queue")


func test_a_long_offline_stretch_never_dumps_a_whole_town_at_once():
	var out: Dictionary = _arrivals(_DAY * 10000.0, _WELL_FED * 8.0, 0, true, 1.0, 0.0)
	assert_eq(int(out["arrivals"]), 1, "room for one plot is one household, however long the absence")
