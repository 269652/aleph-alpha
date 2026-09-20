extends GutTest

## docs/concept/village_economy_balance.md mechanism 1, wired into the live
## settlement step: every assessment, the village pays its households a
## living wage out of the purse the merchant fills.
##
## Built WITHOUT loading a chunk, exactly as test_earth_chunk_manager_
## village_estates.gd is: a settlement's households, its market and its
## purse are store state EarthChunkManager keeps for unloaded settlements
## too, so the real step_settlements is driven against a real founded
## settlement in memory.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const VillageWages = preload("res://src/world/village_wages.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")

const CHUNK := Vector2i(4343, 4343)

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


func _found(count: int) -> Array:
	var npcs: Array = []
	for i in count:
		npcs.append(FakeNpc.new(910_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return manager.household_ids_in_settlement(_settlement_id)


func _market():
	return manager.market_store().market_for(_settlement_id)


func _purse() -> float:
	return NpcEconomy.purse_of(_market())


func _fund(gold: float) -> void:
	# The guard test scans src/ for a third faucet; a test fixture standing
	# in for the merchant's sale is exactly what deposit_to_purse is for.
	NpcEconomy.deposit_to_purse(_market(), gold)


func _wallet_of(household_id: String):
	return manager.household_store().get_household(household_id).wallet


func _wallets_total(household_ids: Array) -> int:
	var total := 0
	for household_id in household_ids:
		total += int(_wallet_of(household_id).balance)
	return total


func _step() -> void:
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)


# -- the wage is really paid ------------------------------------------------

func test_a_funded_purse_pays_every_household_a_wage_each_assessment():
	var households := _found(4)
	_fund(1000.0)
	_step()
	for household_id in households:
		assert_gt(int(_wallet_of(household_id).balance), 0, "%s was not paid" % household_id)


## A TRANSFER, not a faucet: what the wallets gained is exactly what the
## purse lost.
func test_what_the_wallets_gained_is_exactly_what_the_purse_lost():
	var households := _found(5)
	_fund(1000.0)
	var purse_before := _purse()
	var wallets_before := _wallets_total(households)
	_step()
	assert_almost_eq(
		float(_wallets_total(households) - wallets_before), purse_before - _purse(), 0.0001
	)


## The bill is paid in whole coins, and the sub-coin remainder is carried
## rather than rounded away or up.
func test_one_assessment_pays_the_whole_bill_in_whole_coins():
	var households := _found(4)
	_fund(1000.0)
	_step()
	var bill: float = VillageWages.wage_bill_for(households.size(), 1.0)
	assert_eq(_wallets_total(households), int(floor(bill)))


func test_the_carried_fraction_is_paid_once_it_crosses_a_coin():
	var households := _found(4)
	_fund(1000.0)
	for _i in 5:
		_step()
	var bill: float = VillageWages.wage_bill_for(households.size(), 5.0)
	assert_eq(_wallets_total(households), int(floor(bill + 0.000001)))


# -- what the purse cannot pay ----------------------------------------------

func test_an_empty_purse_pays_nothing_and_nobody_goes_into_debt():
	var households := _found(4)
	_step()
	assert_eq(_wallets_total(households), 0)
	assert_almost_eq(_purse(), 0.0, 0.0001, "an empty purse was driven negative")


## When the purse cannot cover the bill, the household with nothing in hand
## is the one that gets the coin.
func test_a_short_purse_pays_the_poorest_first():
	var households := _found(3)
	var rich: String = households[0]
	_wallet_of(rich).add(50)
	_fund(2.0)
	_step()
	assert_eq(int(_wallet_of(rich).balance), 50, "the household with fifty in hand was paid first")
	assert_eq(int(_wallet_of(households[1]).balance), 1)
	assert_eq(int(_wallet_of(households[2]).balance), 1)
	assert_almost_eq(_purse(), 0.0, 0.0001)


## A village pays what it has, not what it owes: a dry spell is not banked
## as arrears to be paid off out of the next sale.
func test_unpaid_wages_are_not_banked_as_arrears():
	var households := _found(4)
	for _i in 3:
		_step()
	assert_eq(_wallets_total(households), 0, "the premise: nothing was paid while the purse was empty")
	_fund(1000.0)
	_step()
	var one_assessment: float = VillageWages.wage_bill_for(households.size(), 1.0)
	assert_true(
		float(_wallets_total(households)) <= ceil(one_assessment),
		"three dry assessments were paid off in one: %d against a bill of %.1f" % [
			_wallets_total(households), one_assessment
		]
	)


# -- what it is for ---------------------------------------------------------

## The readout the report was stuck on: a household on the living wage
## reaches HouseholdWellbeing's full income need.
func test_the_wage_lifts_the_income_need_off_the_floor():
	_found(3)
	_fund(10_000.0)
	var before: Array = manager._household_wellbeing_for_settlement(_settlement_id)
	for assessment in before:
		assert_almost_eq(float(assessment["needs"]["income"]), 0.0, 0.0001, "the premise: broke")
	for _i in int(ceil(VillageWages.assessments_to_full_purse())) + 1:
		_step()
	for assessment in manager._household_wellbeing_for_settlement(_settlement_id):
		assert_almost_eq(float(assessment["needs"]["income"]), 1.0, 0.0001)


## Gold that the cart brings this assessment is in a wallet this
## assessment, not one step later: the wage is paid AFTER the sale.
func test_the_wage_is_paid_after_the_cart_in_the_same_assessment():
	var households := _found(2)
	_market().add_stock("fish", 400)
	var paid_in_the_same_step := false
	for _i in 12:
		var purse_before := _purse()
		var wallets_before := _wallets_total(households)
		_step()
		var arrived: bool = _purse() + float(_wallets_total(households) - wallets_before) > purse_before + 0.5
		if arrived:
			paid_in_the_same_step = _wallets_total(households) > wallets_before
			break
	assert_true(paid_in_the_same_step, "the cart's gold sat in the purse for a whole assessment")
