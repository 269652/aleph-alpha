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
