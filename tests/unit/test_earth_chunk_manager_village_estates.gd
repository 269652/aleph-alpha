extends GutTest

## docs/concept/village_estates.md, wired into the live settlement step.
##
## Deliberately built WITHOUT loading a chunk: a settlement's founding, its
## households, its market and its purse are all event-graph and store state
## that EarthChunkManager keeps for unloaded settlements too (which is
## almost all of them, almost always). So this drives the real
## step_settlements against a real founded settlement in memory and checks
## what really moved, in seconds rather than in the minutes a terrain load
## costs.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const VillageWages = preload("res://src/world/village_wages.gd")
const EstateShortfall = preload("res://src/emergence/estate_shortfall.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const StaffedProduction = preload("res://src/emergence/staffed_production.gd")
const SettlementCharter = preload("res://src/emergence/settlement_charter.gd")
const SettlementTier = preload("res://src/emergence/settlement_tier.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")

const CHUNK := Vector2i(4242, 4242)

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _settlement_id: String


class FakeNpc:
	extends RefCounted
	var seed_value: int
	func _init(a_seed: int) -> void:
		seed_value = a_seed


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	_settlement_id = EntityRef.for_settlement(CHUNK)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Founds a settlement of `count` households in memory and returns their ids.
func _found(count: int) -> Array:
	var npcs: Array = []
	for i in count:
		npcs.append(FakeNpc.new(900_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return manager.household_ids_in_settlement(_settlement_id)


func _set_estates(household_ids: Array, estate: String) -> void:
	for household_id in household_ids:
		manager.household_store().get_household(household_id).estate = estate


func _market():
	return manager.market_store().market_for(_settlement_id)


func _step() -> void:
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)


## Keeps the larder and the woodpile deep enough that nobody starves out
## over a long run -- otherwise a test measuring a draw over four hundred
## assessments is really measuring an exodus, and the census it divides by
## changes underneath it.
func _keep_the_village_alive() -> void:
	_market().add_stock("bread", 9000)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 9000)
	_market().add_stock("herb", 9000)


# -- the census -----------------------------------------------------------

func test_a_freshly_founded_village_is_all_cottagers():
	var households := _found(4)
	var census: Dictionary = manager.estate_census_for_settlement(_settlement_id)
	assert_eq(int(census.get(VillageEstates.STARTING_ESTATE, 0)), households.size())


func test_a_settlement_nobody_founded_has_no_census():
	assert_eq(manager.estate_census_for_settlement(EntityRef.for_settlement(Vector2i(1, 1))), {})


# -- the goods really leave -----------------------------------------------

## Pillar 1 made live: the village's firewood is on the shelf at the start
## of the step and less of it is there at the end, because its households
## burned it.
func test_a_village_really_burns_the_firewood_on_its_own_shelf():
	_found(6)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 200)
	var before: int = _market().stock_of(VillageEstates.FUEL_ITEM_ID)
	_step()
	assert_true(
		_market().stock_of(VillageEstates.FUEL_ITEM_ID) < before,
		"a village of six households burned no firewood at all"
	)


func test_a_bigger_village_burns_strictly_more():
	_found(2)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 400)
	var small_before: int = _market().stock_of(VillageEstates.FUEL_ITEM_ID)
	_step()
	var small_burn: int = small_before - _market().stock_of(VillageEstates.FUEL_ITEM_ID)

	for i in 10:
		manager.admit_household(CHUNK)
	var big_before: int = _market().stock_of(VillageEstates.FUEL_ITEM_ID)
	_step()
	var big_burn: int = big_before - _market().stock_of(VillageEstates.FUEL_ITEM_ID)
	assert_true(big_burn > small_burn, "twelve households burned no more than two")


## And it reports what it could not supply, which is the number every other
## estate mechanism is read against.
func test_a_village_with_no_firewood_at_all_reports_its_fuel_unsupplied():
	_found(5)
	_step()
	var satisfaction: Dictionary = manager.estate_satisfaction_for_settlement(_settlement_id)
	assert_almost_eq(float(satisfaction.get(VillageEstates.FUEL_ITEM_ID, 1.0)), 0.0, 0.0001)


func test_a_well_stocked_village_reports_its_fuel_supplied():
	_found(5)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 500)
	_step()
	var satisfaction: Dictionary = manager.estate_satisfaction_for_settlement(_settlement_id)
	assert_almost_eq(float(satisfaction.get(VillageEstates.FUEL_ITEM_ID, 0.0)), 1.0, 0.0001)


## FOOD is deliberately NOT drawn here: SettlementGranary already eats a
## settlement's food on this same step, and a second draw would be the same
## meal eaten twice. What the estate layer reports for food is the village's
## own larder reading, so the two halves agree instead of competing.
func test_the_estate_layer_never_eats_the_food_the_granary_already_ate():
	_found(4)
	_market().add_stock("bread", 100)
	var before: int = _market().stock_of("bread")
	_step()
	var after: int = _market().stock_of("bread")
	var granary_draw: int = manager.granary_subsistence_draw_for(_settlement_id)
	assert_true(
		before - after <= granary_draw,
		"the estate layer ate bread the granary had already eaten"
	)


func test_food_satisfaction_is_still_reported_from_the_villages_own_larder():
	_found(4)
	_market().add_stock("bread", 400)
	_step()
	var satisfaction: Dictionary = manager.estate_satisfaction_for_settlement(_settlement_id)
	assert_true(
		float(satisfaction.get(VillageEstates.FOOD_KIND_TOKEN, 0.0)) > 0.0,
		"a village with four hundred loaves reported itself unfed"
	)


# -- the ladder actually moves --------------------------------------------

## A village kept at its standard long enough, with the charter standing,
## really promotes a household -- the thing village_growth.md's population
## could never do.
func test_a_well_kept_village_with_its_charter_up_really_promotes_a_household():
	var households := _found(3)
	for household_id in households:
		var household = manager.household_store().get_household(household_id)
		household.good_run_days = EstateAscension.ASCENT_DWELL_DAYS
	# A REAL completed farmhouse on the settlement's own construction ledger
	# -- the persisted record of what this village actually built, which is
	# what the charter gate reads for a village nobody is standing in.
	var project = manager.construction_project_store().start_project(
		CHUNK, Vector2i(3, 3), "farmhouse", _settlement_id
	)
	manager.construction_project_store().complete_project(project.id, manager.household_store())
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 900)
	_market().add_stock("herb", 900)
	_market().add_stock("bread", 900)
	_step()
	var census: Dictionary = manager.estate_census_for_settlement(_settlement_id)
	assert_true(int(census.get("bauer", 0)) > 0, "nobody rose in a village kept at its standard")


## And a starved one really loses standing -- the way down.
func test_a_starved_village_really_loses_standing():
	var households := _found(3)
	for household_id in households:
		var household = manager.household_store().get_household(household_id)
		household.estate = "handwerker"
		household.short_run_days = EstateAscension.DECLINE_DWELL_DAYS
	_step()
	var census: Dictionary = manager.estate_census_for_settlement(_settlement_id)
	assert_true(int(census.get("bauer", 0)) > 0, "a starved craftsman kept his standing")


## The bottom rung has nowhere to fall to, so it leaves -- and the village
## really is smaller afterwards. This is the departure path the growth
## system never had.
func test_a_starved_cottager_leaves_and_the_village_is_really_smaller():
	var households := _found(4)
	for household_id in households:
		manager.household_store().get_household(household_id).short_run_days = (
			EstateAscension.DECLINE_DWELL_DAYS
		)
	var before: int = manager.household_ids_in_settlement(_settlement_id).size()
	_step()
	assert_true(
		manager.household_ids_in_settlement(_settlement_id).size() < before,
		"a village that starved every one of its cottagers lost nobody"
	)


## A village empties one household at a time, never all at once.
##
## Found by a probe rather than reasoned about: with every starving
## household leaving on the same assessment, a four-household village went
## to ZERO inside twenty assessments -- about ten minutes of play -- and so
## would every lean village on the planet. One departure per assessment is
## also simply what happens: people leave a failing village one family at
## a time, and each one that goes leaves more of the larder for those who
## stay, which is a village's real chance to recover.
func test_a_starving_village_loses_one_household_per_assessment_at_most():
	_found(6)
	for household_id in manager.household_ids_in_settlement(_settlement_id):
		manager.household_store().get_household(household_id).short_run_days = (
			EstateAscension.DECLINE_DWELL_DAYS
		)
	var before: int = manager.household_ids_in_settlement(_settlement_id).size()
	_step()
	var after: int = manager.household_ids_in_settlement(_settlement_id).size()
	assert_eq(before - after, 1, "a starving village emptied itself in one assessment")


## And it keeps emptying: one at a time is a slower exodus, not a stopped
## one.
func test_a_village_that_never_recovers_really_does_empty_out():
	_found(4)
	for _i in 120:
		_step()
	assert_true(
		manager.household_ids_in_settlement(_settlement_id).size()
		< 4,
		"a village that never fed anybody kept every household it had"
	)


func test_a_household_that_left_never_comes_back_on_the_next_step():
	_found(4)
	for household_id in manager.household_ids_in_settlement(_settlement_id):
		manager.household_store().get_household(household_id).short_run_days = (
			EstateAscension.DECLINE_DWELL_DAYS
		)
	_step()
	var after_first: int = manager.household_ids_in_settlement(_settlement_id).size()
	_step()
	assert_true(manager.household_ids_in_settlement(_settlement_id).size() <= after_first)


# -- the ledger -----------------------------------------------------------

## Mechanism 6 live: a provided village really does pay into the same purse
## the subsistence wage comes out of.
func test_a_provided_village_really_pays_tax_into_the_shared_purse():
	_found(6)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 900)
	_market().add_stock("herb", 900)
	var before: float = NpcEconomy.purse_of(_market())
	_step()
	assert_true(
		NpcEconomy.purse_of(_market()) > before,
		"a fully provided village paid nothing into its own purse"
	)


func test_a_destitute_village_pays_nothing_into_the_purse():
	_found(6)
	var before: float = NpcEconomy.purse_of(_market())
	_step()
	assert_almost_eq(
		NpcEconomy.purse_of(_market()), before, 0.0001, "a village with nothing paid tax anyway"
	)


# -- what the house readout is handed -------------------------------------

## household_report_at needs a real building on real loaded ground, which
## costs a terrain load. What it needs from the ESTATE layer is this one
## helper, so that is what is checked here -- the report itself just carries
## what this returns.
func test_a_households_readout_carries_its_real_standing():
	var households := _found(3)
	manager.household_store().get_household(households[0]).estate = "handwerker"
	var estate_report: Dictionary = manager.estate_report_for_household(households[0], CHUNK)
	assert_eq(String(estate_report["estate"]), "handwerker")


func test_a_household_holding_its_standing_reads_as_holding():
	var households := _found(3)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 900)
	_market().add_stock("herb", 900)
	_step()
	var estate_report: Dictionary = manager.estate_report_for_household(households[0], CHUNK)
	assert_eq(String(estate_report["estate_verdict"]), EstateAscension.HOLD)


## A starved cottager with its run already banked reads as leaving, which
## is exactly what the panel then says out loud.
func test_a_starved_cottager_reads_as_on_its_way_out():
	var households := _found(3)
	for household_id in households:
		manager.household_store().get_household(household_id).short_run_days = (
			EstateAscension.DECLINE_DWELL_DAYS
		)
	manager.step_settlements(0.0)  # no time passes; only the reading is taken
	var estate_report: Dictionary = manager.estate_report_for_household(households[0], CHUNK)
	assert_eq(String(estate_report["estate_verdict"]), EstateAscension.DESCEND)


func test_a_building_nobody_owns_carries_no_standing_at_all():
	_found(2)
	var estate_report: Dictionary = manager.estate_report_for_household("", CHUNK)
	assert_eq(String(estate_report["estate"]), "")
	assert_eq(String(estate_report["estate_verdict"]), "")


# -- an unmet basket is something the village can build its way out of ----

## The step that keeps the estate ladder from being decorative. A village
## short of a station good has to be able to RAISE the works that makes it,
## or nobody ever meets their station and nobody ever rises.
func test_a_village_short_of_a_station_good_really_reports_a_buildable_shortfall():
	_found(5)
	_step()
	var shortfalls: Array = manager.estate_shortfalls_for_settlement(_settlement_id)
	var goods: Array = []
	for shortfall in shortfalls:
		for missing in shortfall["missing"]:
			goods.append(String(missing["item_id"]))
	assert_true(goods.has(VillageEstates.FUEL_ITEM_ID), "a village with no firewood asked for none")
	assert_false(
		goods.has(VillageEstates.FOOD_KIND_TOKEN),
		"the food token reached the build decision, which can build nothing for it"
	)


func test_a_supplied_village_reports_no_shortfall_to_build_for():
	_found(5)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 900)
	_market().add_stock("herb", 900)
	_step()
	assert_eq(manager.estate_shortfalls_for_settlement(_settlement_id), [])


## Every entry is in the shape SettlementBuildDecision already reads, so it
## reasons about an unmet basket with no new code on that side.
func test_the_shortfalls_are_in_the_shape_the_build_decision_reads():
	_found(5)
	_step()
	for shortfall in manager.estate_shortfalls_for_settlement(_settlement_id):
		for key in ["kind", "household_id", "occupation", "recipe_id", "missing"]:
			assert_true(shortfall.has(key), "a shortfall with no %s is not the shape" % key)
		assert_eq(String(shortfall["kind"]), EstateShortfall.KIND)


func test_a_settlement_nobody_founded_reports_no_shortfalls():
	assert_eq(manager.estate_shortfalls_for_settlement(EntityRef.for_settlement(Vector2i(2, 2))), [])


# -- the clock the basket is drawn on ------------------------------------

## The one relation the whole estate economy has to satisfy: a village's
## spare hands must out-gather its own firewood. Firewood IS `wood` --
## deliberately the same id a village builds with, so fuel and timber are a
## real competition for one resource rather than two parallel economies --
## and if the burn outruns the cut, no village on the planet can ever
## afford a building again.
##
## Pinned as a measurement against the real gathering rate, not as a
## number: `SettlementGathering` counts in ConstructionCatchup's one-hour
## day, so the basket has to be drawn on that same day or the two are
## sixty times apart. It was, once. The bread chain's own
## "spare hands gather building material between assessments" caught it.
## The one relation the whole estate economy has to satisfy, held as two
## real numbers rather than as a stock level: a village's firewood burn
## must stay under what its own spare hands cut. Firewood IS `wood` --
## deliberately the same id a village builds with, so fuel and timber are a
## real competition for one resource rather than two parallel economies --
## and if the burn outruns the cut, no village on the planet can ever
## afford a building again.
##
## It did, once, and by sixty times: `SettlementGathering` counts in
## ConstructionCatchup's one-hour day and the basket was being drawn on the
## sixty-second simulated one. The bread chain's own "spare hands gather
## building material between assessments" is what caught it.
##
## Measured in WINTER, the season the burn is worst in.
func test_a_villages_firewood_burn_stays_under_what_its_spare_hands_cut():
	_found(5)
	assert_true(
		manager.estate_fuel_demand_per_assessment_for(_settlement_id)
		< manager.gathering_wood_per_assessment_for(_settlement_id),
		"a village burns more firewood in winter than it can cut"
	)


## And it still holds as the village grows: the burn scales with
## households and the cut with spare hands, so a relation true at five is
## not automatically true at twenty-five.
func test_the_relation_still_holds_for_a_village_five_times_the_size():
	_found(5)
	for _i in 20:
		manager.admit_household(CHUNK)
	assert_true(
		manager.estate_fuel_demand_per_assessment_for(_settlement_id)
		< manager.gathering_wood_per_assessment_for(_settlement_id),
		"a village of twenty-five burns more firewood than it can cut"
	)


## The burn is still REAL, not rounded away to nothing: a village really
## does spend a share of its timber keeping warm.
func test_the_burn_is_a_real_share_of_the_cut_and_not_a_rounding_error():
	_found(5)
	assert_true(manager.estate_fuel_demand_per_assessment_for(_settlement_id) > 0.0)


## The emergence Market counts in WHOLE units and its own remove_stock
## CEILS -- so a draw of a fiftieth of a log took a whole log, every single
## assessment, and every village stripped its own timber sixty times over.
## The bread chain's own "a village with idle hands cuts its own timber" is
## what caught it.
##
## The fix is the carry-the-fraction idiom SettlementGathering,
## SettlementGranary and VillageImmigration all already run on: a sub-unit
## draw accrues until it crosses a whole unit.
##
## Measured on what the ESTATE LAYER itself took, not on a stock level:
## the merchant, the production step and every construction project spend
## from the same shelf, so a stock reading cannot tell any of them apart --
## which is exactly how this bug hid.
func test_a_sub_unit_draw_never_costs_the_village_a_whole_unit():
	_found(4)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 400)
	assert_true(
		manager.estate_fuel_demand_per_assessment_for(_settlement_id) < 1.0,
		"precondition: this village's draw really is a fraction of a log"
	)
	for _i in 5:
		_step()
	assert_eq(
		int(manager.estate_whole_units_drawn_for(_settlement_id).get(VillageEstates.FUEL_ITEM_ID, 0)),
		0,
		"five assessments of a fractional draw cost the village whole logs"
	)


## And the fraction is not thrown away either: run it long enough and the
## whole units really do come off.
func test_the_carried_fractions_really_do_add_up_to_whole_units():
	_found(4)
	_keep_the_village_alive()
	for _i in 400:
		_step()
	assert_true(
		int(manager.estate_whole_units_drawn_for(_settlement_id).get(VillageEstates.FUEL_ITEM_ID, 0)) > 0,
		"four hundred assessments of burning firewood cost the village nothing"
	)


## Conservation, which is what makes the carry trustworthy rather than
## merely quieter: whole units taken plus the remainder still carried is
## exactly what the baskets asked for over the same stretch.
func test_what_was_taken_plus_what_is_carried_is_what_the_baskets_asked_for():
	_found(4)
	_keep_the_village_alive()
	var steps := 30
	for _i in steps:
		_step()
	var taken: float = float(
		manager.estate_whole_units_drawn_for(_settlement_id).get(VillageEstates.FUEL_ITEM_ID, 0)
	)
	var carried: float = float(
		manager.estate_draw_carry_for(_settlement_id).get(VillageEstates.FUEL_ITEM_ID, 0.0)
	)
	var asked: float = (
		manager.estate_fuel_demand_per_assessment_for(_settlement_id) * float(steps)
	)
	# The seasonal term means the per-assessment figure above (winter, the
	# worst case) is an upper bound on what was really asked for, so the
	# claim is that nothing was invented, not that the two match exactly.
	assert_true(taken + carried <= asked + 0.0001, "the draw took more than the baskets asked for")
	assert_true(taken + carried > 0.0, "thirty assessments of burning firewood asked for nothing")


# -- staffed buildings really produce -------------------------------------

## Raises a real COMPLETE project for `building_id` on this settlement's
## own persisted ledger -- the record of what a village really built, which
## is what the estate layer reads for a village nobody is standing in.
func _raise(building_id: String, at: Vector2i) -> void:
	var project = manager.construction_project_store().start_project(
		CHUNK, at, building_id, _settlement_id
	)
	manager.construction_project_store().complete_project(project.id, manager.household_store())


## The close of village_growth.md's own "the rungs are buildings, not yet
## production": the dearest rung on that ladder made NOTHING, and now a
## staffed brewhouse really puts beer on the village's own shelf.
func test_a_staffed_brewery_really_brews_real_beer():
	var households := _found(8)
	# A brewer and a pair of hands: one craftsman, the rest cottagers.
	manager.household_store().get_household(households[0]).estate = "handwerker"
	_raise("brewery", Vector2i(3, 3))
	_keep_the_village_alive()
	_market().add_stock("wheat", 400)
	var before: int = _market().stock_of("beer")
	for _i in 60:
		_step()
	assert_true(_market().stock_of("beer") > before, "a staffed brewhouse brewed nothing at all")


## And the pyramid's whole claim, live: the same brewhouse with no
## craftsman in the village produces nothing, however long it stands.
func test_the_same_brewery_with_no_craftsman_in_the_village_brews_nothing():
	_found(8)  # every household a cottager -- hands, but no trade
	_raise("brewery", Vector2i(3, 3))
	_keep_the_village_alive()
	_market().add_stock("wheat", 400)
	var before: int = _market().stock_of("beer")
	for _i in 60:
		_step()
	assert_eq(_market().stock_of("beer"), before, "a brewhouse with no brewer in it made beer")


## And it costs real grain: beer and bread compete for one harvest, which
## is the supply-chain tension the whole chain exists to have.
func test_brewing_really_spends_the_villages_own_grain():
	var households := _found(8)
	manager.household_store().get_household(households[0]).estate = "handwerker"
	_raise("brewery", Vector2i(3, 3))
	_keep_the_village_alive()
	_market().add_stock("wheat", 400)
	var before: int = _market().stock_of("wheat")
	for _i in 60:
		_step()
	assert_true(_market().stock_of("wheat") < before, "the brewhouse brewed beer out of nothing")


## The assembly tells a village short of firewood to raise a sawmill. That
## has to be true, so a staffed saw pit really does bring more timber in.
func test_a_staffed_sawmill_really_brings_more_timber_in():
	var without := _timber_gathered_over(20, false)
	var with_mill := _timber_gathered_over(20, true)
	assert_true(
		with_mill > without,
		"a village with a staffed saw pit cut no more timber than one without"
	)


## How much timber a fresh village of cottagers brings in over `steps`,
## with or without a staffed mill standing.
func _timber_gathered_over(steps: int, with_sawmill: bool) -> int:
	var chunk := Vector2i(-31, -31) if with_sawmill else Vector2i(-32, -32)
	var npcs: Array = []
	for i in 6:
		npcs.append(FakeNpc.new(610_000 + i))
	manager.record_settlement_founded_if_new(chunk, npcs)
	var settlement := EntityRef.for_settlement(chunk)
	if with_sawmill:
		var project = manager.construction_project_store().start_project(
			chunk, Vector2i(6, 6), "sawmill", settlement
		)
		manager.construction_project_store().complete_project(project.id, manager.household_store())
	var market = manager.market_store().market_for(settlement)
	market.add_stock("bread", 9000)
	market.add_stock(VillageEstates.FUEL_ITEM_ID, 9000)
	market.add_stock("herb", 9000)
	var before: int = market.stock_of(VillageEstates.FUEL_ITEM_ID)
	for _i in steps:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	return market.stock_of(VillageEstates.FUEL_ITEM_ID) - before


## The sawmill's timber bonus is carried in the SAME place the gathering
## carry is, so a caller that resets one resets both. It was not, once:
## test_earth_chunk_manager_village_growth.gd's own "hunger must never slow
## the gathering" clears the material carry between two identical runs and
## saw 8 logs where it saw 7, purely because a second, separate remainder
## survived the reset. A gathering step with two carries and one reset is a
## step whose output depends on what ran before it.
func test_two_identical_gathering_runs_from_a_cleared_carry_cut_the_same_timber():
	_found(6)
	_raise("sawmill", Vector2i(9, 9))
	var household_ids := manager.household_ids_in_settlement(_settlement_id)

	for _i in 8:
		manager._step_settlement_gathering(_settlement_id, _market(), household_ids)
	var first: float = float(_market().stock.get(VillageEstates.FUEL_ITEM_ID, 0.0))

	_market().stock.clear()
	manager._settlement_material_carry.clear()
	for _i in 8:
		manager._step_settlement_gathering(_settlement_id, _market(), household_ids)
	var second: float = float(_market().stock.get(VillageEstates.FUEL_ITEM_ID, 0.0))

	assert_almost_eq(second, first, 0.001, "a leftover remainder survived the reset")
	assert_true(first > 0.0, "precondition: this village cuts timber at all")


# -- the labour pyramid reaches wellbeing ---------------------------------

## docs/concept/village_estates.md mechanism 4 into
## docs/concept/village_growth.md mechanism 4: a household that has no post
## to fill is idle, and idleness really costs the village happiness and
## therefore productivity.
## The village has a farm -- so its buildings really are readable -- and
## the farm wants husbandmen, of which it has none. Its cottagers are
## therefore genuinely idle, which is a different fact from "nobody looked"
## (see the last test in this block).
func test_a_village_whose_only_works_wants_another_estate_reads_its_people_as_idle():
	_found(6)
	_raise("farmhouse", Vector2i(3, 3))
	_keep_the_village_alive()
	_step()
	var idle_productivity: float = manager.settlement_productivity(_settlement_id)

	# The SAME village, with a store and a saw pit its cottagers can work.
	_raise("warehouse", Vector2i(12, 3))
	_raise("sawmill", Vector2i(9, 9))
	_step()
	assert_true(
		manager.settlement_productivity(_settlement_id) > idle_productivity,
		"giving every cottager a post changed nothing about how the village works"
	)


## And from the other side: a village that promoted everyone out of the
## class its own works need has idle risen households AND works nobody can
## run -- the squeeze, now felt as unhappiness rather than only as output.
func test_a_village_that_promoted_everyone_reads_its_risen_households_as_idle():
	var households := _found(6)
	_raise("warehouse", Vector2i(3, 3))
	_raise("sawmill", Vector2i(9, 9))
	_keep_the_village_alive()
	_step()
	var working: float = manager.settlement_productivity(_settlement_id)

	for household_id in households:
		manager.household_store().get_household(household_id).estate = "bauer"
	_step()
	assert_true(
		manager.settlement_productivity(_settlement_id) < working,
		"a village of husbandmen with nothing but a saw pit was just as productive"
	)


## The readout carries it too, so a player can see WHY a house is unhappy.
func test_the_house_readout_reports_the_work_need():
	var households := _found(6)
	_raise("farmhouse", Vector2i(3, 3))  # readable, and no post for a cottager
	_keep_the_village_alive()
	_step()
	var report: Dictionary = manager.household_wellbeing_report_for(households[0])
	assert_true(report["needs"].has("work"))
	assert_almost_eq(
		float(report["needs"]["work"]), 0.0, 0.001, "a cottager found work on a farm"
	)


func test_the_same_household_with_a_post_reads_its_work_met():
	var households := _found(1)
	_raise("warehouse", Vector2i(3, 3))
	_keep_the_village_alive()
	_step()
	var report: Dictionary = manager.household_wellbeing_report_for(households[0])
	assert_almost_eq(float(report["needs"]["work"]), 1.0, 0.001)


## A settlement whose buildings could not be read at all is NOT reported as
## idle -- that would have every village in the world nobody is standing in
## read as wholly out of work. Absence of a reading is not evidence of
## idleness.
func test_a_settlement_whose_buildings_are_unreadable_is_not_called_idle():
	var quiet := EntityRef.for_settlement(Vector2i(-91, -91))
	var npcs: Array = []
	for i in 4:
		npcs.append(FakeNpc.new(660_000 + i))
	manager.record_settlement_founded_if_new(Vector2i(-91, -91), npcs)
	var households := manager.household_ids_in_settlement(quiet)
	assert_eq(manager._settlement_present_building_ids(Vector2i(-91, -91)), [], "precondition")
	var report: Dictionary = manager.household_wellbeing_report_for(households[0])
	assert_almost_eq(
		float(report["needs"]["work"]), 1.0, 0.001,
		"a village nobody could look at was reported out of work"
	)


## Both wellbeing paths -- the settlement-wide assessment and the single
## household a click resolves to -- read the SAME employment, because both
## build their state through one builder. Two readings of "is this
## household in work" that could disagree is exactly the drift the shared
## builder exists to stop.
func test_the_settlement_assessment_and_the_single_readout_agree_on_work():
	var households := _found(6)
	_raise("farmhouse", Vector2i(3, 3))
	_keep_the_village_alive()
	_step()
	var single: float = float(
		manager.household_wellbeing_report_for(households[0])["needs"]["work"]
	)
	for assessment in manager._household_wellbeing_for_settlement(_settlement_id):
		assert_almost_eq(
			float(assessment["needs"]["work"]), single, 0.001,
			"the village and the household disagree about who is in work"
		)


# -- the charter, live ----------------------------------------------------

## docs/concept/settlement_charter.md mechanisms 2 and 5. A player refused
## a mage guild must leave knowing what to go and do.
func test_a_hamlet_refuses_a_mage_guild_and_says_what_it_is_short_of():
	_found(2)
	var refusal: Dictionary = manager.building_charter_refusal_at(_settlement_id, "mage_guild")
	assert_false(refusal.is_empty(), "a hamlet let a mage guild through")
	assert_eq(String(refusal["required_tier"]), SettlementTier.CITY)
	assert_gt(int(refusal["short"]["households"]), 0, "it did not say how many more people")


func test_a_settlement_is_never_refused_a_building_nothing_charters():
	_found(2)
	assert_eq(manager.building_charter_refusal_at(_settlement_id, "sawmill"), {})


func test_a_settlement_nobody_founded_refuses_a_chartered_building():
	var nowhere := EntityRef.for_settlement(Vector2i(-61, -61))
	assert_false(manager.building_charter_refusal_at(nowhere, "mage_guild").is_empty())


## The readout a player actually reads off the hall: what the place IS, and
## what it would take to be the next thing up.
func test_the_charter_report_names_the_tier_and_the_errand():
	_found(2)
	var report: Dictionary = manager.settlement_charter_report_for(_settlement_id)
	assert_eq(String(report["tier"]), SettlementTier.HAMLET)
	assert_eq(String(report["next_tier"]), SettlementTier.TOWN)
	assert_true(report.has("short"), "the report does not say what is short")
	assert_true(
		report["allowed"].is_empty(),
		"a hamlet was told it may raise a chartered building"
	)


## And it is a CONSUMER, never a driver: asking changes nothing.
func test_reading_the_charter_changes_nothing_about_the_settlement():
	_found(4)
	_keep_the_village_alive()
	_step()
	var households_before: int = manager.household_ids_in_settlement(_settlement_id).size()
	var stock_before: int = _market().stock_of(VillageEstates.FUEL_ITEM_ID)
	manager.settlement_charter_report_for(_settlement_id)
	manager.building_charter_refusal_at(_settlement_id, "mage_guild")
	assert_eq(manager.household_ids_in_settlement(_settlement_id).size(), households_before)
	assert_eq(_market().stock_of(VillageEstates.FUEL_ITEM_ID), stock_before)


## The village's own decision reads the same charter: a hamlet never queues
## what a player standing on its square would be refused.
func test_the_village_never_decides_to_build_what_its_charter_forbids():
	_found(6)
	_keep_the_village_alive()
	for _i in 12:
		_step()
		var next: String = manager.next_building_for_settlement(CHUNK)
		assert_true(
			SettlementCharter.allows(next, manager.settlement_tier_of(_settlement_id)),
			"a %s decided to build %s" % [manager.settlement_tier_of(_settlement_id), next]
		)
