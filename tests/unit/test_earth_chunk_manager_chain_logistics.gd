extends GutTest

## Hauling between the bread chain's links (docs/concept/milling_and_
## baking.md, "Hauling between the links"): the SAME LogisticsMarker that
## already moves a producer's output into Storage, configured with a
## consumer as its destination -- wheat from a Farm (or a Storage holding
## wheat) into a Mill, flour from a Mill into a Bakery, bread from a Bakery
## into Storage. One hauler per real (source, destination) pair within the
## existing pairing radius, reconciled the same way the Sägewerk's and
## Farm's Storage pairing already is (EarthChunkManager.CHAIN_LOGISTICS_
## LEGS / _resync_all_chain_legs).
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const LogisticsMarker = preload("res://src/rendering/logistics_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _farm := Vector2i(6, 6)
var _fence := Vector2i(7, 6)
var _mill := Vector2i(10, 6)
var _bakery := Vector2i(14, 6)
var _storage := Vector2i(18, 6)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _local(tile: Vector2i) -> Vector2i:
	return tile - _chunk_coord * EarthChunkManager.CHUNK_SIZE


## The haulers currently paired for `source` tile's `destination_id` leg:
## {destination_pairing_key -> {item_id -> LogisticsMarker}}.
func _legs(source: Vector2i, destination_id: String) -> Dictionary:
	return manager._chain_logistics_workers.get(_chunk_coord, {}).get(_local(source), {}).get(destination_id, {})


func _the_one_hauler(source: Vector2i, destination_id: String, item_id: String):
	var legs := _legs(source, destination_id)
	assert_eq(legs.size(), 1, "exactly one paired %s for the %s leg" % [destination_id, item_id])
	var by_item: Dictionary = legs.values()[0]
	assert_true(by_item.has(item_id))
	return by_item[item_id]


func _build_fenced_farm() -> void:
	manager.build_at_global(_farm.x, _farm.y, "farm")
	manager.build_at_global(_fence.x, _fence.y, "wooden_fence")


func test_a_fenced_farm_near_a_mill_gets_a_wheat_hauler_bound_for_the_mill():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")

	var hauler = _the_one_hauler(_farm, "mill", "wheat")
	assert_eq(hauler.source_structure_id, "farm")
	assert_eq(hauler.item_id, "wheat")
	assert_eq(hauler.storage_structure_id, "mill", "the destination is the Mill, not a Storage")
	var mill_pixel := (Vector2(_mill) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
	assert_eq(hauler.preferred_storage_position, mill_pixel)
	assert_eq(hauler.earth, manager)


func test_a_mill_near_a_bakery_gets_a_flour_hauler_and_a_bakery_near_storage_a_bread_hauler():
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	manager.build_at_global(_storage.x, _storage.y, "storage")

	assert_eq(_the_one_hauler(_mill, "bakery", "flour").storage_structure_id, "bakery")
	assert_eq(_the_one_hauler(_bakery, "storage", "bread").storage_structure_id, "storage")


func test_wheat_already_in_a_storage_is_hauled_on_to_the_mill():
	manager.build_at_global(_storage.x, _storage.y, "storage")
	manager.build_at_global(_mill.x, _mill.y, "mill")
	assert_eq(_the_one_hauler(_storage, "mill", "wheat").source_structure_id, "storage")


func test_an_unfenced_farm_has_no_farmer_and_so_no_hauler_until_it_is_fenced():
	manager.build_at_global(_farm.x, _farm.y, "farm")
	manager.build_at_global(_mill.x, _mill.y, "mill")
	assert_true(_legs(_farm, "mill").is_empty(), "no Farmer, no wheat, no hauler")

	manager.build_at_global(_fence.x, _fence.y, "wooden_fence")
	assert_eq(_legs(_farm, "mill").size(), 1, "fencing the farm staffs it, and its haulers follow")


func test_destroying_the_mill_despawns_the_legs_on_both_sides_of_it():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	assert_eq(_legs(_farm, "mill").size(), 1)
	assert_eq(_legs(_mill, "bakery").size(), 1)

	manager.destroy_at_global(_mill.x, _mill.y)

	assert_true(_legs(_farm, "mill").is_empty())
	assert_true(_legs(_mill, "bakery").is_empty())


func test_repeated_resyncs_never_double_spawn_a_leg():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager._resync_all_chain_legs()
	manager._resync_all_chain_legs()
	assert_eq(_legs(_farm, "mill").size(), 1)
	var haulers := 0
	for node in entities_parent.get_children():
		if node is LogisticsMarker and node.storage_structure_id == "mill":
			haulers += 1
	assert_eq(haulers, 1)


func test_unloading_the_chunk_frees_its_chain_haulers():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager._unload_chunk(_chunk_coord)
	assert_false(manager._chain_logistics_workers.has(_chunk_coord))
	var path: String = manager._modifications_path(_chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## End to end, with the real hauler: wheat deposited at the Farm reaches the
## Mill's own stock -- the same real trip test_logistics_marker.gd already
## proves for a Storage destination, here with a consumer as the
## destination, which is the whole point of the leg.
func test_wheat_at_the_farm_is_actually_carried_into_the_mill():
	_build_fenced_farm()
	manager.build_at_global(_mill.x, _mill.y, "mill")
	manager.deposit_to_structure_at(_farm.x, _farm.y, "wheat", 4)
	var hauler = _the_one_hauler(_farm, "mill", "wheat")

	for i in 400:
		hauler._process(0.25)
		if manager.structure_stock_at(_mill.x, _mill.y, "wheat") > 0:
			break

	assert_gt(manager.structure_stock_at(_mill.x, _mill.y, "wheat"), 0, "wheat arrived at the Mill")
	assert_lt(manager.structure_stock_at(_farm.x, _farm.y, "wheat"), 4, "...and left the Farm -- a transfer, not a copy")



# -- a meal from the village's own stores (docs/concept/milling_and_ -------
# -- baking.md) ----------------------------------------------------------------
#
# NpcEconomy._try_eat asks the world, duck-typed, for a meal from the
# village's stores when the stall is bare -- these are the world's real
# answers: first the settlement's own persisted Market (where the merchant
# stocks and the granary/trade fill -- the food SettlementState has always
# counted and nobody ever ate), then one whole unit of any kind == "food"
# item on a Bakery's or Storage's own shelf within STRUCTURE_MEAL_RADIUS_
# TILES; at VillageMarket's own meal price, all-or-nothing like buy_meal.

const Wallet = preload("res://src/gameplay/wallet.gd")
const VillageMarket = preload("res://src/world/village_market.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")


func _near(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE


func test_bread_on_a_bakerys_shelf_is_a_meal_and_buying_it_takes_one_loaf_at_the_meal_price():
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	manager.deposit_to_structure_at(_bakery.x, _bakery.y, "bread", 3)
	var wallet := Wallet.new()
	wallet.add(10)

	assert_true(manager.has_village_meal_near(_near(_bakery + Vector2i(2, 2))))
	assert_eq(manager.buy_village_meal_near(_near(_bakery + Vector2i(2, 2)), wallet), "bread")
	assert_eq(manager.structure_stock_at(_bakery.x, _bakery.y, "bread"), 2)
	assert_eq(wallet.balance, 10 - VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)


func test_wheat_and_flour_in_a_storage_are_not_meals():
	manager.build_at_global(_storage.x, _storage.y, "storage")
	manager.deposit_to_structure_at(_storage.x, _storage.y, "wheat", 5)
	manager.deposit_to_structure_at(_storage.x, _storage.y, "flour", 5)
	assert_false(manager.has_village_meal_near(_near(_storage)))
	var wallet := Wallet.new()
	wallet.add(10)
	assert_eq(manager.buy_village_meal_near(_near(_storage), wallet), "")
	assert_eq(wallet.balance, 10, "a failed purchase never touches the wallet")


func test_an_empty_wallet_buys_nothing_and_the_loaf_stays():
	manager.build_at_global(_storage.x, _storage.y, "storage")
	manager.deposit_to_structure_at(_storage.x, _storage.y, "bread", 1)
	assert_eq(manager.buy_village_meal_near(_near(_storage), Wallet.new()), "")
	assert_eq(manager.structure_stock_at(_storage.x, _storage.y, "bread"), 1)


func test_a_bakehouse_across_the_map_is_not_near():
	manager.build_at_global(_bakery.x, _bakery.y, "bakery")
	manager.deposit_to_structure_at(_bakery.x, _bakery.y, "bread", 3)
	var far := _near(_bakery + Vector2i(EarthChunkManager.STRUCTURE_MEAL_RADIUS_TILES + 8, 0))
	assert_false(manager.has_village_meal_near(far))


## The merchant's own cooked meat -- reported directly: "the food should be
## actually consumed and not stay at 20 cooked meat".
func test_the_settlements_own_market_food_is_eaten_first_at_the_local_meal_price():
	var settlement_id := EntityRef.for_settlement(_chunk_coord)
	var market = manager._market_store.market_for(settlement_id)
	market.add_stock("cooked_meat", 20)
	manager.build_at_global(_storage.x, _storage.y, "storage")
	manager.deposit_to_structure_at(_storage.x, _storage.y, "bread", 3)
	var wallet := Wallet.new()
	wallet.add(10)

	assert_true(manager.has_village_meal_near(_near(_storage)))
	assert_eq(manager.buy_village_meal_near(_near(_storage), wallet), "cooked_meat", "the stores before the shelf")
	assert_eq(market.stock_of("cooked_meat"), 19, "one portion actually left the market")
	assert_eq(manager.structure_stock_at(_storage.x, _storage.y, "bread"), 3, "the shelf untouched")
	assert_eq(wallet.balance, 10 - VillageMarket.VILLAGE_LOCAL_FOOD_PRICE)


func test_only_food_in_the_market_counts_as_a_meal():
	var market = manager._market_store.market_for(EntityRef.for_settlement(_chunk_coord))
	market.add_stock("torch", 20)
	market.add_stock("wood", 20)
	assert_false(manager.has_village_meal_near(_near(_storage)))
