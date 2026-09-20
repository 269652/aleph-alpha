extends GutTest

## VillageImmigration: docs/concept/village_growth.md mechanism 3 -- a
## village that is fed and has room attracts new households over time.
## Without this the ladder is a ladder nothing ever walks up
## (SettlementGenerator's population is a fixed 5). Same carry-the-fraction,
## whole-units-out shape SettlementGathering/SettlementGranary already use.

const VillageImmigration = preload("res://src/emergence/village_immigration.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")

## One simulated day, in real seconds -- the module's OWN day, so these
## tests go on measuring "a day of draw" whatever that day is worth. It used
## to be ConstructionCatchup.SECONDS_PER_DAY (3600), which is the offscreen
## catch-up's day and was never this module's to borrow.
const _DAY := VillageImmigration.SECONDS_PER_SIMULATED_DAY
const _WELL_FED := VillageImmigration.FED_THRESHOLD * 2.0


## `room` is kept in this helper's own signature, and dropped on the way
## through, only so the many call sites below still read as the cases they
## were written as. Frontage stopped being part of the gate on 2026-09-20 --
## see "a household moves into a house, not onto a promise" below.
func _arrivals(seconds: float, food: float, spare: int, _room: bool, ladder: float, carry: float) -> Dictionary:
	return VillageImmigration.arrivals(seconds, food, spare, ladder, carry)


func test_a_hungry_village_attracts_nobody_however_much_room_it_has():
	var out: Dictionary = _arrivals(_DAY * 30.0, VillageImmigration.FED_THRESHOLD - 0.01, 9, true, 1.0, 0.0)
	assert_eq(out["arrivals"], 0)


func test_a_village_with_no_room_at_all_attracts_nobody_however_rich():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED * 4.0, 0, false, 1.0, 0.0)
	assert_eq(out["arrivals"], 0)


## **Reversed 2026-09-20.** This used to read "a fed village with FRONTAGE
## to build on takes people in", on the reading that room to build is room
## enough. It is not: the allowance was handed out again on every settlement
## step, so a village with frontage took somebody in for ever whether or not
## the house the last arrival was promised ever got raised. Reported with
## eleven of twenty-one households under no roof at all. A fed village with
## a real EMPTY HOUSE takes people in; frontage is the ladder's business.
func test_a_fed_village_with_a_real_empty_house_takes_people_in():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 1, false, 0.0, 0.0)
	assert_gt(out["arrivals"], 0, "an empty house is room enough")


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
	assert_lte(int(out["arrivals"]), 2, "two spare roofs is two households, frontage or not")


func test_the_carry_never_banks_a_crowd_for_later():
	var out: Dictionary = _arrivals(_DAY * 365.0, _WELL_FED * 8.0, 0, true, 1.0, 0.0)
	assert_between(float(out["carry"]), 0.0, 1.0, "a year of demand must not bank as a queue")


## Same reversal as above: the one household this used to admit was the
## frontage allowance, and a village with no empty house now admits nobody
## however long it went unvisited. One empty roof is still one household.
func test_a_long_offline_stretch_never_dumps_a_whole_town_at_once():
	assert_eq(
		int(_arrivals(_DAY * 10000.0, _WELL_FED * 8.0, 0, true, 1.0, 0.0)["arrivals"]), 0,
		"no empty house is nobody, however long the absence"
	)
	assert_eq(
		int(_arrivals(_DAY * 10000.0, _WELL_FED * 8.0, 1, true, 1.0, 0.0)["arrivals"]), 1,
		"one empty roof is one household, however long the absence"
	)


# -- a village grows on the clock the player lives in ------------------------
# Asked directly: *"increase the village sizes from 5 houses to 10 initial
# and then it should GROW BY ITSELF"*. It did, and nobody could ever see it.
#
# Measured before this: arrivals were counted in ConstructionCatchup's own
# day (3600 real seconds -- the deliberately conservative rate for
# integrating an UNLOADED chunk's vegetation and herds over an absence), so
# a bare just-fed village drew one household every 6 hours 40 minutes of
# real play, and a full larder under a full ladder still took 2 hours 13.
# Immigration only runs while the chunk is LOADED, so that is two hours of
# standing next to a village to watch one person move in.

func test_a_village_grows_on_the_games_own_day_not_the_catchup_day():
	assert_eq(
		VillageImmigration.SECONDS_PER_SIMULATED_DAY, 60.0,
		"the day the ecosystem step, the settlement step, the day/night cycle and every colony already run on"
	)
	assert_ne(
		VillageImmigration.SECONDS_PER_SIMULATED_DAY, ConstructionCatchup.SECONDS_PER_DAY,
		"the premise: the offscreen catch-up day really is a different, longer thing"
	)


## The rate itself, read as the thing a player actually experiences: a
## comfortable village with its ladder up takes somebody in within a few
## minutes of being watched, not within hours.
func test_a_thriving_village_takes_somebody_in_within_minutes():
	var seconds := 0.0
	var carry := 0.0
	var arrived := 0
	while arrived == 0 and seconds < 3600.0:
		var result: Dictionary = VillageImmigration.arrivals(30.0, 8.0, 4, 1.0, carry)
		carry = result["carry"]
		arrived += int(result["arrivals"])
		seconds += 30.0
	assert_gt(arrived, 0, "a thriving village never took anybody in at all")
	assert_lt(seconds, 300.0, "a village the player is standing next to must visibly grow: %.0fs" % seconds)


## And not instantly either -- a village that gained a household every step
## would be a town by the time the player walked across it.
func test_a_village_does_not_take_somebody_in_every_step():
	assert_eq(
		int(VillageImmigration.arrivals(30.0, 8.0, 4, 1.0, 0.0)["arrivals"]), 0,
		"one settlement step is not a household"
	)


# -- a household moves into a house, not onto a promise ---------------------
#
# Reported live with the town panel in shot ("Population 21 (10 housed)"):
# *"The population is rising but no new houses are built.. NPCs should only
# move in when a new unoccupied house exists for them"*.
#
# village_growth.md's mechanism 3 has said so all along -- *"Gated on room:
# free_capacity <= 0 => no arrivals. A village with no spare roof takes
# nobody in, however rich"* -- but the code allowed one more than the spare
# roofs whenever the village still had FRONTAGE to build on. That allowance
# was meant as a cap and behaved as a standing invitation: it is granted
# again on every settlement step, whether or not the house promised by the
# last one was ever raised, so eleven households had piled up under no roof
# at all.


func test_a_village_with_frontage_but_no_empty_house_still_takes_nobody_in():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 0, true, 1.0, 0.0)
	assert_eq(
		out["arrivals"], 0,
		"somewhere to build is not somewhere to live -- a house has to stand first"
	)


## ...and the draw is not banked while they wait, either. Whoever would have
## come went somewhere else, which is what stops a long absence emptying a
## whole region onto one village the moment a house finally stands.
func test_the_draw_of_a_village_with_no_room_is_lost_rather_than_banked():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 0, true, 1.0, 0.0)
	assert_almost_eq(float(out["carry"]), 0.0, 0.0001)


## The other half: a real empty roof really does take somebody in. Without
## this the test above passes just as well against a village nobody can
## ever move to.
func test_a_real_empty_house_takes_somebody_in():
	var out: Dictionary = _arrivals(_DAY * 30.0, _WELL_FED, 1, false, 1.0, 0.0)
	assert_eq(out["arrivals"], 1, "an empty house is exactly what an arrival needs")


## Never more than the roofs that stand, however long the village went
## unvisited or however strong the draw.
func test_arrivals_never_outrun_the_empty_houses_that_stand():
	for spare in [0, 1, 2, 5]:
		var out: Dictionary = _arrivals(_DAY * 365.0, _WELL_FED, spare, true, 1.0, 0.0)
		assert_lte(
			int(out["arrivals"]), spare,
			"a year of draw put %d people into %d empty houses" % [int(out["arrivals"]), spare]
		)
