extends GutTest

## docs/concept/village_economy_balance.md mechanism 3, wired into the
## merchant's visit: the cart is handed the village's minimum stock as its
## larder reserve, and never sells below it.
##
## In memory, without a chunk, like test_earth_chunk_manager_village_
## estates.gd: an unloaded settlement's granary eats and its merchant
## trades off the persisted Market, which is all this needs.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")

const CHUNK := Vector2i(4444, 4444)

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
		npcs.append(FakeNpc.new(920_000 + i))
	manager.record_settlement_founded_if_new(CHUNK, npcs)
	return manager.household_ids_in_settlement(_settlement_id)


func _market():
	return manager.market_store().market_for(_settlement_id)


func _step() -> void:
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)


## The reserve the cart is handed holds back exactly the minimum stock, in
## food, and nothing of what the village is not short of.
func test_the_cart_is_handed_the_minimum_stock_as_its_larder_reserve():
	var households := _found(4)
	_market().add_stock("fish", 100)
	var reserved: Dictionary = manager._merchant_reserve_for(_settlement_id, [_market().stock])
	assert_eq(int(reserved.get("fish", 0)), SettlementSurplus.minimum_stock_for(households.size()))


## A village with less food than its minimum holds back all of it -- there
## is no surplus, and he finds nothing to buy.
func test_a_village_below_its_minimum_stock_offers_the_cart_nothing():
	var households := _found(4)
	_market().add_stock("fish", SettlementSurplus.minimum_stock_for(households.size()) - 1)
	var reserved: Dictionary = manager._merchant_reserve_for(_settlement_id, [_market().stock])
	assert_eq(int(reserved.get("fish", 0)), _market().stock_of("fish"))


## The claim in the step itself: the assessment the cart comes, the food it
## leaves behind is at least the minimum stock.
func test_the_cart_never_takes_the_village_below_its_minimum_stock():
	var households := _found(4)
	_market().add_stock("fish", 400)
	var visited := false
	for _i in 12:
		var purse_before: float = NpcEconomy.purse_of(_market())
		_step()
		if NpcEconomy.purse_of(_market()) > purse_before:
			visited = true
			assert_true(
				_market().stock_of("fish") >= SettlementSurplus.minimum_stock_for(households.size()),
				"the cart left %d fish, under a minimum of %d" % [
					_market().stock_of("fish"), SettlementSurplus.minimum_stock_for(households.size())
				]
			)
	assert_true(visited, "the premise: a village with four hundred fish drew a cart")


# -- and the fuel: the minimum stock is the whole subsistence basket ---------

## The reserve the cart is handed holds back the fuel the households burn
## over the cover, plus the one whole unit a shelf's granularity costs.
func test_the_cart_is_handed_the_fuel_the_village_burns_as_its_reserve():
	_found(10)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 100)
	var reserved: Dictionary = manager._merchant_reserve_for(_settlement_id, [_market().stock])
	var burn: float = manager._fuel_burn_over_cover_for(_settlement_id)
	assert_gt(burn, 0.0, "the premise: ten households burn something over a round")
	assert_eq(int(reserved.get(VillageEstates.FUEL_ITEM_ID, 0)), SettlementSurplus.minimum_fuel_for(burn))


## Through the step: the assessment the cart comes, the woodpile it leaves
## is at least that.
func test_the_cart_never_strips_the_woodpile():
	_found(10)
	_market().add_stock("bread", 9000)
	_market().add_stock(VillageEstates.FUEL_ITEM_ID, 100)
	var visited := false
	for _i in 12:
		var purse_before: float = NpcEconomy.purse_of(_market())
		_step()
		if NpcEconomy.purse_of(_market()) > purse_before:
			visited = true
			assert_true(
				_market().stock_of(VillageEstates.FUEL_ITEM_ID)
					>= SettlementSurplus.minimum_fuel_for(manager._fuel_burn_over_cover_for(_settlement_id)),
				"the cart left %d wood" % _market().stock_of(VillageEstates.FUEL_ITEM_ID)
			)
			break
	assert_true(visited, "the premise: a village with a hundred wood drew a cart")
