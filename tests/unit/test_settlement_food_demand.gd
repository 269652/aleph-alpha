extends GutTest

## SettlementFoodDemand: how many of a village's founders have to feed it, and
## which trade the land feeds it with.
##
## Asked for directly: "Make it driven by demand". What that replaced was a
## hardcoded "if nobody in this roster farms, make the last one a farmer" --
## one producer, always, whatever the village's size or its land.
##
## It could only be written once both halves of the food model had been
## measured against each other (docs/concept/settlement_food_calibration.md):
## demand was 3.33x overstated, and the three trades' supply figures were
## four orders of magnitude apart because one rate was applied to a density
## and to two headcounts alike.

const SettlementFoodDemand = preload("res://src/emergence/settlement_food_demand.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")


## A region with controllable readings, the same shape SettlementGranary.
## SeededRegion already offers.
func _region(vegetation: float, herbivores: float, fish: float):
	var region = SettlementGranary.SeededRegion.new()
	region.vegetation_density = vegetation
	region.herbivore_population = herbivores
	region.fish_population = fish
	return region


# -- how many ---------------------------------------------------------------


## The count is the village's own draw over what one producer's real work
## brings in -- never a fixed number.
func test_the_count_is_the_villages_own_draw_over_what_one_producer_yields():
	for households in [1, 5, 12, 40]:
		var draw: int = SettlementGranary.subsistence_draw(households)
		var per_producer: float = SettlementFoodDemand.yield_per_producer_per_assessment()
		assert_eq(
			SettlementFoodDemand.producers_needed(households),
			int(ceil(float(draw) / per_producer)),
			"%d households" % households
		)


## A founding village of five needs THREE: its draw is six food units an
## assessment and a real field, worked from a cottage a street away for the
## work blocks of a real day, brings in two and a half
## (docs/concept/village_economy_balance.md mechanism 6). It used to say
## one, sized against a stub-world field nobody ever walked home from --
## and a real village of ten with three fields ate its shelves to zero.
func test_a_founding_village_of_five_needs_three_food_producers():
	assert_eq(
		SettlementFoodDemand.producers_needed(5),
		int(ceil(float(SettlementGranary.subsistence_draw(5)) / SettlementFoodDemand.yield_per_producer_per_assessment()))
	)
	assert_eq(SettlementFoodDemand.producers_needed(5), 3)


## ...and a village that grows past what one field feeds needs a second,
## which is the whole point of making it demand-driven.
func test_a_village_that_outgrows_one_field_needs_another():
	var one_feeds: int = SettlementFoodDemand.households_fed_per_producer()
	assert_gt(one_feeds, 0, "precondition: one field really does feed somebody")
	assert_eq(SettlementFoodDemand.producers_needed(one_feeds), 1)
	assert_eq(SettlementFoodDemand.producers_needed(one_feeds + 1), 2)


func test_a_village_with_nobody_in_it_needs_nobody_to_feed_it():
	assert_eq(SettlementFoodDemand.producers_needed(0), 0)
	assert_eq(SettlementFoodDemand.producers_needed(-3), 0)


## What one producer brings in is a REAL FIELD'S day, on the assessment
## clock: VillageFarm.FIELD_YIELD_PER_LIVED_DAY over the assessments in the
## day the farmer's own schedule runs on.
func test_one_producer_is_measured_by_what_a_real_field_yields_in_a_day():
	assert_almost_eq(
		SettlementFoodDemand.yield_per_producer_per_assessment(),
		VillageFarm.FIELD_YIELD_PER_LIVED_DAY
		/ (VillageFarm.SECONDS_PER_LIVED_DAY / SettlementState.ASSESSMENT_SECONDS),
		0.001
	)


## And it is still REAL WORK, not the ambient drip: at 0.22 food an
## assessment against a draw of 6, no amount of foraging feeds five
## households -- which is correct, and is why a village farms.
func test_one_producer_is_measured_by_real_work_not_by_foraging():
	var drip: float = (
		NpcProduction.new().yield_per_second("farmer", _region(0.3, 0.0, 0.0), Vector2.ZERO)
		* SettlementState.ASSESSMENT_SECONDS
	)
	assert_gt(SettlementFoodDemand.yield_per_producer_per_assessment(), drip * 4.0)


# -- the real field's day, pinned ------------------------------------------
#
# MEASURED (tools/probe_village_economy.gd, tools/probe_field_timeline.gd,
# a real village east of Berlin): three six-bed fields harvested 299 units
# in 20 lived days, and 163 in 10 -- five a field a day, against the 18.5 a
# day the stub-world measurement behind FIELD_YIELD_PER_WORK_BLOCK works
# out to. The stub's farmer never walks home: a real one works the day's
# two work blocks, commutes from a cottage a street away at walking pace,
# fetches water, and leaves beds empty for most of the day.

## A real field yields less per day than a field worked without ever
## leaving it -- the commute and the well are real.
func test_a_real_field_yields_less_per_day_than_the_stubs_field_that_nobody_walks_home_from():
	var continuous_day: float = (
		VillageFarm.FIELD_YIELD_PER_WORK_BLOCK / VillageFarm.WORK_BLOCK_SECONDS
		* VillageFarm.SECONDS_PER_LIVED_DAY
	)
	assert_lt(VillageFarm.FIELD_YIELD_PER_LIVED_DAY, continuous_day)


## But a field is still worth raising: it feeds at least one household's
## day of meals, so a farmhouse is never a building for nobody.
func test_a_real_field_still_feeds_at_least_one_household():
	assert_gt(
		VillageFarm.FIELD_YIELD_PER_LIVED_DAY,
		SettlementState.FOOD_PER_HOUSEHOLD * VillageFarm.SECONDS_PER_LIVED_DAY / SettlementState.ASSESSMENT_SECONDS
	)
	assert_gt(SettlementFoodDemand.households_fed_per_producer(), 0)


## The day the yield is measured over is the farmer's own: the clock their
## schedule turns on, and the one every other lived-day reading shares.
func test_the_fields_day_is_the_farmers_own_clock():
	var NpcMarker = load("res://src/rendering/npc_marker.gd")
	assert_almost_eq(VillageFarm.SECONDS_PER_LIVED_DAY, NpcMarker.SECONDS_PER_SIMULATED_DAY, 0.001)
	assert_almost_eq(VillageFarm.SECONDS_PER_LIVED_DAY, MerchantVisit.SECONDS_PER_DAY, 0.001)


# -- which trade ------------------------------------------------------------


## Land with real water feeds a village with fish, and the fisher digs and
## stocks a pond (docs/concept/village_ponds.md) -- which is what a player
## asked to see.
func test_land_with_real_water_is_worked_by_a_fisher():
	assert_eq(SettlementFoodDemand.trade_for(_region(0.15, 0.9, 800.0)), "fisher")


## Ordinary grassland is farmed. A hunter never wins: measured, a whole
## chunk supports about one deer, so hunting is a supplement and never a
## village's staple (see the concept doc's own honest gap about
## HERBIVORES_PER_VEGETATION_UNIT).
func test_ordinary_grassland_is_worked_by_a_farmer():
	assert_eq(SettlementFoodDemand.trade_for(_region(0.15, 0.9, 0.0)), "farmer")
	assert_eq(SettlementFoodDemand.trade_for(_region(0.15, 5.0, 0.0)), "farmer")


## A trade nobody can work is never chosen: land with nothing standing on it
## gets the trade that at least raises a farmhouse, rather than a fisher with
## no water.
func test_barren_land_still_gets_somebody_who_works_the_ground():
	assert_eq(SettlementFoodDemand.trade_for(_region(0.0, 0.0, 0.0)), "farmer")
	assert_eq(SettlementFoodDemand.trade_for(null), "farmer")


## Every trade this can name really is one a villager can be, and one that
## really feeds a village.
func test_every_trade_it_names_is_a_real_food_producing_occupation():
	var NpcIdentity = load("res://src/world/npc_identity.gd")
	for region in [_region(0.15, 0.9, 800.0), _region(0.15, 0.9, 0.0), null]:
		var trade: String = SettlementFoodDemand.trade_for(region)
		assert_true(NpcIdentity.OCCUPATIONS.has(trade), trade)
		assert_true(SettlementFoodDemand.FOOD_TRADES.has(trade), trade)


## The trades that count as feeding a village are the ones that really do:
## a farmer and a herbalist work a field, a fisher works a pond, a hunter
## takes real game.
func test_the_food_trades_are_the_ones_that_really_feed_a_village():
	assert_true(SettlementFoodDemand.FOOD_TRADES.has("farmer"))
	assert_true(SettlementFoodDemand.FOOD_TRADES.has("herbalist"))
	assert_true(SettlementFoodDemand.FOOD_TRADES.has("fisher"))
	assert_false(SettlementFoodDemand.FOOD_TRADES.has("blacksmith"))
	for trade in SettlementFoodDemand.FOOD_TRADES:
		assert_true(
			VillageFarm.crop_for(trade) != "" or trade in ["fisher", "hunter"],
			"%s has to have somewhere to actually produce food" % trade
		)


## A trade only counts toward the demand if it can really MEET it.
##
## MEASURED on real villages after the rule first landed
## (tools/probe_village_contents.gd): the village at (657,145) rolled a
## hunter and a fisher, was therefore read as fed, and its farmhouse stood
## with `wanted_by=0` -- nobody to work it. A hunter brings in about 0.02
## food units an assessment against a draw of 6 (see the concept doc's own
## measured table and its honest gap about HERBIVORES_PER_VEGETATION_UNIT:
## a whole chunk supports roughly one deer). Counting one as a producer
## while sizing the roster against a FARMHOUSE's yield says a village is fed
## when it is not -- and brings back the "No Farmhouses" report this whole
## line of work started from.
##
## So the trades that count are the ones with a real workplace that really
## yields: a farmer and a herbalist work a field their farmhouse owns, a
## fisher works a pond they dug. Hunting stays a real occupation and a real
## way to eat; it is simply not what a village is founded on.
func test_a_trade_only_counts_if_it_can_really_meet_the_demand_it_is_sized_against():
	assert_false(
		SettlementFoodDemand.FOOD_TRADES.has("hunter"),
		"a hunter yields ~0.02 an assessment against a draw of 6 -- counting one says a village is fed when it is not"
	)
	for trade in SettlementFoodDemand.FOOD_TRADES:
		assert_true(
			VillageFarm.crop_for(trade) != "" or trade == "fisher",
			"%s has to have a real workplace the village raises" % trade
		)


## ...and the land still never picks it either, for the same reason.
func test_the_land_never_picks_a_trade_that_cannot_feed_the_village():
	for fish in [0.0, 800.0]:
		assert_ne(SettlementFoodDemand.trade_for(_region(0.15, 50.0, fish)), "hunter")
