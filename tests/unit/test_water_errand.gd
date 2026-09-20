extends GutTest

## WaterErrand: docs/concept/village_water.md mechanism 2 -- the trip to the
## well as a state machine you can SEE.
##
## Pillar 2 is the whole point: what a villager is doing must be answerable
## by looking at them. They carry an empty bucket one way and a full one
## back, and that difference is the entire UI this feature needs. So the
## carried item is not decoration hung off the state -- it IS the state,
## and these tests treat it that way.

const WaterErrand = preload("res://src/emergence/water_errand.gd")
const HouseholdWater = preload("res://src/emergence/household_water.gd")


# -- the shape of the errand ------------------------------------------------

func test_a_villager_at_home_with_a_full_tank_is_not_on_an_errand():
	assert_false(WaterErrand.is_running(WaterErrand.AT_HOME))
	assert_eq(WaterErrand.begin_if_due(HouseholdWater.TANK_LITRES), WaterErrand.AT_HOME)


func test_a_low_tank_starts_the_errand():
	assert_eq(WaterErrand.begin_if_due(0.0), WaterErrand.TO_WELL)
	assert_true(WaterErrand.is_running(WaterErrand.TO_WELL))


func test_the_errand_runs_to_the_well_and_home_again():
	var state := WaterErrand.begin_if_due(0.0)
	assert_eq(state, WaterErrand.TO_WELL)
	state = WaterErrand.arrived(state)
	assert_eq(state, WaterErrand.DRAWING)
	state = WaterErrand.arrived(state)
	assert_eq(state, WaterErrand.TO_HOME)
	state = WaterErrand.arrived(state)
	assert_eq(state, WaterErrand.POURING)
	state = WaterErrand.arrived(state)
	assert_eq(state, WaterErrand.AT_HOME, "the errand has to end, or the bucket never gets put down")


func test_arriving_while_at_home_does_nothing():
	assert_eq(WaterErrand.arrived(WaterErrand.AT_HOME), WaterErrand.AT_HOME)


func test_an_unknown_state_falls_back_to_being_at_home_rather_than_stranding_anybody():
	assert_eq(WaterErrand.arrived("wandering_off"), WaterErrand.AT_HOME)
	assert_false(WaterErrand.is_running("wandering_off"))


func test_every_state_the_machine_can_reach_is_a_declared_one():
	var state := WaterErrand.begin_if_due(0.0)
	for step in 12:
		assert_true(WaterErrand.STATES.has(state), "reached '%s'" % state)
		state = WaterErrand.arrived(state)


func test_the_errand_always_terminates():
	var state := WaterErrand.begin_if_due(0.0)
	var steps := 0
	while WaterErrand.is_running(state) and steps < 20:
		state = WaterErrand.arrived(state)
		steps += 1
	assert_eq(state, WaterErrand.AT_HOME)
	assert_lt(steps, 20, "the errand never ends")


# -- what you can see -------------------------------------------------------

func test_nobody_at_home_is_carrying_a_bucket():
	assert_eq(WaterErrand.carried(WaterErrand.AT_HOME), "")


func test_the_bucket_goes_out_empty():
	assert_eq(WaterErrand.carried(WaterErrand.TO_WELL), WaterErrand.BUCKET_EMPTY)
	assert_eq(WaterErrand.carried(WaterErrand.DRAWING), WaterErrand.BUCKET_EMPTY)


func test_the_bucket_comes_back_full():
	assert_eq(WaterErrand.carried(WaterErrand.TO_HOME), WaterErrand.BUCKET_FULL)
	assert_eq(WaterErrand.carried(WaterErrand.POURING), WaterErrand.BUCKET_FULL)


## The claim pillar 2 rests on: the way out and the way back must not look
## alike, or the errand is invisible again and nothing has been fixed.
func test_the_way_there_and_the_way_back_never_look_the_same():
	assert_ne(
		WaterErrand.carried(WaterErrand.TO_WELL),
		WaterErrand.carried(WaterErrand.TO_HOME)
	)


func test_an_unknown_state_carries_nothing_rather_than_a_broken_sprite():
	assert_eq(WaterErrand.carried("wandering_off"), "")


func test_both_buckets_are_real_carryable_things():
	assert_ne(WaterErrand.BUCKET_EMPTY, "")
	assert_ne(WaterErrand.BUCKET_FULL, "")
	assert_ne(WaterErrand.BUCKET_EMPTY, WaterErrand.BUCKET_FULL)


# -- where the errand sends them --------------------------------------------

func test_the_outward_leg_heads_for_the_well():
	assert_eq(WaterErrand.location_tag_for(WaterErrand.TO_WELL), "well")
	assert_eq(WaterErrand.location_tag_for(WaterErrand.DRAWING), "well")


func test_the_homeward_leg_heads_home():
	assert_eq(WaterErrand.location_tag_for(WaterErrand.TO_HOME), "home")
	assert_eq(WaterErrand.location_tag_for(WaterErrand.POURING), "home")
	assert_eq(WaterErrand.location_tag_for(WaterErrand.AT_HOME), "home")


## An errand outranks a timetable, or the bucket gets abandoned halfway
## across the square when the day rolls over.
func test_a_villager_mid_errand_is_not_sent_somewhere_else_by_their_schedule():
	for state in WaterErrand.STATES:
		if state == WaterErrand.AT_HOME:
			continue
		assert_true(
			WaterErrand.overrides_schedule(state),
			"'%s' would let the day rollover take them off the errand" % state
		)
	assert_false(WaterErrand.overrides_schedule(WaterErrand.AT_HOME))


# -- what a completed errand does to the tank -------------------------------

func test_pouring_the_bucket_in_raises_the_tank_by_a_bucket():
	var before := HouseholdWater.TANK_LITRES * 0.2
	assert_almost_eq(
		WaterErrand.poured(before), HouseholdWater.poured_into(before, HouseholdWater.BUCKET_LITRES), 0.0001
	)


## A pail holds less than a household is short of, so one trip is often
## not enough -- and that is right, because fetching water meant going
## twice. What must be true is that it ENDS: the loop of "still due, go
## again" has to stop after a few trips rather than turning a villager
## into a permanent fixture at the well, which is the very crowd this
## feature exists to remove.
func test_fetching_until_the_household_is_supplied_takes_a_few_trips_and_then_stops():
	var level := 0.0
	var trips := 0
	while HouseholdWater.trip_is_due(level) and trips < 20:
		var state := WaterErrand.begin_if_due(level)
		assert_true(WaterErrand.is_running(state), "a dry household did not set out")
		while WaterErrand.is_running(state):
			state = WaterErrand.arrived(state)
		level = WaterErrand.poured(level)
		trips += 1
	assert_false(HouseholdWater.trip_is_due(level), "the household never got supplied")
	assert_lte(trips, 4, "%d trips in a row is living at the well" % trips)
	assert_gte(trips, 1)
