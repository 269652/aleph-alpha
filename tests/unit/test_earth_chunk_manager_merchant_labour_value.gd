extends GutTest

## docs/concept/village_economy_balance.md mechanism 2, wired into the
## visit: the merchant pays the village the labour value of what it made
## since his last call -- twice its wage bill -- and the interval he pays
## for is capped at his own round.
##
## In memory, without a chunk, like the other settlement-step suites. Gold
## is conserved inside the village except for what the cart pays, so the
## payment a visit made is the change in purse-plus-wallets that
## assessment (the tax is a transfer between the two and the wage another).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const VillageWages = preload("res://src/world/village_wages.gd")
const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")

const CHUNK := Vector2i(4545, 4545)

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _settlement_id: String
var _households: Array


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
		npcs.append(FakeNpc.new(930_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	_households = manager.household_ids_in_settlement(_settlement_id)
	return _households


func _market():
	return manager.market_store().market_for(_settlement_id)


func _gold_in_the_village() -> float:
	var total: float = NpcEconomy.purse_of(_market())
	for household_id in _households:
		total += float(manager.household_store().get_household(household_id).wallet.balance)
	return total


## Steps until a cart pays something, returning {"paid", "steps"}; paid is
## 0.0 if none came inside `limit` steps.
func _step_until_a_visit(limit: int) -> Dictionary:
	for step in limit:
		var before := _gold_in_the_village()
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		var paid := _gold_in_the_village() - before
		if paid > 0.0001:
			return {"paid": paid, "steps": step + 1}
	return {"paid": 0.0, "steps": limit}


func _keep_fed() -> void:
	# Bread is not on the buy list, so it feeds the village without drawing
	# a cart of its own.
	_market().add_stock("bread", 9000)


## A first call pays for one round of labour: the cover, in assessments.
func test_a_first_visit_pays_for_one_round_of_labour():
	_found(4)
	_keep_fed()
	_market().add_stock("fish", 400)
	var visit := _step_until_a_visit(12)
	assert_gt(float(visit["paid"]), 0.0, "the premise: a village with four hundred fish drew a cart")
	assert_almost_eq(
		float(visit["paid"]),
		MerchantVisit.labour_value_for(VillageWages.wage_bill_for(4, float(SettlementSurplus.cover_assessments()))),
		0.0001
	)


## The next call pays for the labour since his last one.
func test_the_next_visit_pays_for_the_labour_since_his_last_call():
	_found(4)
	_keep_fed()
	_market().add_stock("fish", 4000)
	var first := _step_until_a_visit(12)
	assert_gt(float(first["paid"]), 0.0, "the premise: a first visit")
	var second := _step_until_a_visit(12)
	assert_gt(float(second["paid"]), 0.0, "the premise: a second visit")
	# At the farm-gate floor he takes WHOLE units to cover the labour value,
	# so the payment lands within one unit's base price above it.
	var labour: float = MerchantVisit.labour_value_for(VillageWages.wage_bill_for(4, float(second["steps"])))
	assert_between(float(second["paid"]), labour - 0.0001, labour + float(MerchantVisit.price_of("fish")))


## The interval is capped at the cover: a village that had nothing to sell
## for a while is owed the round when it finally has something, not the
## whole dry spell.
func test_the_interval_he_pays_for_is_capped_at_his_own_round():
	_found(4)
	_keep_fed()
	# A surplus worth LESS than the round's labour, so the cart takes the
	# whole of it: nothing sellable is left, and nothing draws him for a
	# long while.
	_market().add_stock("fish", 100)
	var first := _step_until_a_visit(12)
	assert_gt(float(first["paid"]), 0.0, "the premise: a first visit")
	assert_eq(
		_market().stock_of("fish"), SettlementSurplus.minimum_stock_for(4),
		"the premise: the cart took everything above the minimum stock"
	)
	var dry := SettlementSurplus.cover_assessments() * 3
	for _i in dry:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	_market().add_stock("fish", 400)
	var next := _step_until_a_visit(12)
	assert_gt(float(next["paid"]), 0.0, "the premise: he came back")
	assert_almost_eq(
		float(next["paid"]),
		MerchantVisit.labour_value_for(VillageWages.wage_bill_for(4, float(SettlementSurplus.cover_assessments()))),
		0.0001
	)


## The request itself, over a run: a village that exports what it makes
## earns at least twice its wage bill from the cart.
func test_a_village_that_exports_what_it_makes_earns_at_least_twice_its_wage_bill():
	_found(4)
	_keep_fed()
	_market().add_stock("fish", 40_000)
	var steps := 40
	var earned := 0.0
	for _i in steps:
		var before := _gold_in_the_village()
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		earned += maxf(_gold_in_the_village() - before, 0.0)
	var bill: float = VillageWages.wage_bill_for(4, float(steps))
	assert_true(earned >= MerchantVisit.labour_value_for(bill) - 0.0001, "earned %.1f against a bill of %.1f" % [earned, bill])
	# ...and not the moon: at most the bill plus one round's head start.
	var ceiling: float = MerchantVisit.labour_value_for(VillageWages.wage_bill_for(4, float(steps + SettlementSurplus.cover_assessments())))
	assert_true(earned <= ceiling + 0.0001, "earned %.1f, over the ceiling of %.1f" % [earned, ceiling])
