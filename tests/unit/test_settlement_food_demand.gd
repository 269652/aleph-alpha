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


## A founding village of five needs exactly one: its draw is six food units
## an assessment and a real worked field brings in about seven and a half.
## The old rule's answer, for the first time for a reason.
func test_a_founding_village_of_five_needs_one_food_producer():
	assert_eq(SettlementFoodDemand.producers_needed(5), 1)


## ...and a village that grows past what one field feeds needs a second,
## which is the whole point of making it demand-driven.
func test_a_village_that_outgrows_one_field_needs_another():
	var one_feeds: int = SettlementFoodDemand.households_fed_per_producer()
	assert_gt(one_feeds, 5, "precondition: one field really does feed more than a founding roster")
	assert_eq(SettlementFoodDemand.producers_needed(one_feeds), 1)
	assert_eq(SettlementFoodDemand.producers_needed(one_feeds + 1), 2)


func test_a_village_with_nobody_in_it_needs_nobody_to_feed_it():
	assert_eq(SettlementFoodDemand.producers_needed(0), 0)
	assert_eq(SettlementFoodDemand.producers_needed(-3), 0)


## What one producer brings in is REAL WORK, not the ambient drip. At 0.22
## food per assessment against a draw of 6, no amount of foraging feeds five
## households -- which is correct, and is why a village farms.
func test_one_producer_is_measured_by_real_work_not_by_foraging():
	assert_almost_eq(
		SettlementFoodDemand.yield_per_producer_per_assessment(),
		VillageFarm.FIELD_YIELD_PER_WORK_BLOCK
		/ VillageFarm.WORK_BLOCK_SECONDS * SettlementState.ASSESSMENT_SECONDS,
		0.001
	)


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
