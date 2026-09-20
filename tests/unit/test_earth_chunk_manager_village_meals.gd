extends GutTest

## Where a villager may actually EAT from.
##
## Reported live with the panel open and a stocked store in shot: *"there's
## still not enough food even though the warehouse is full"*.
##
## Both halves of that sentence were true at once, and they disagreed
## inside the codebase. A settlement's own food assessment
## (SettlementFood.carrying_capacity, via _settlement_structure_stocks)
## counts EVERY StructureStock standing in the settlement's chunk, so the
## warehouse's grain is food the village has. An individual villager's meal
## came from STRUCTURE_MEAL_SOURCE_IDS -- a hand-written list of two ids
## that the village warehouse was never added to when it was introduced.
## So the village was fed on paper and its people could not eat.
##
## Uses the fast (0, 0) chunk and build_at_global, exactly as
## test_earth_chunk_manager_chain_logistics.gd does -- a structure here is
## a modification carrying its own id, which is what the meal search scans.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _store := Vector2i(10, 6)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	remove_child(tile_map_layer)
	remove_child(entities_parent)
	manager.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _pixel_of(tile: Vector2i) -> Vector2:
	return (Vector2(tile) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE


## Raises `structure_id` at the store cell and puts `count` of `item_id` on
## its shelf -- the same stock the village's carter really deposits into
## (NpcMarker's round calls deposit_to_structure_at with the store's cell).
func _a_stocked(structure_id: String, item_id: String, count: int) -> void:
	assert_true(
		manager.build_at_global(_store.x, _store.y, structure_id),
		"precondition: the %s stands" % structure_id
	)
	manager.deposit_to_structure_at(_store.x, _store.y, item_id, count)
	assert_eq(
		manager.structure_stock_at(_store.x, _store.y, item_id), count,
		"precondition: the %s is holding the food" % structure_id
	)


func test_a_villager_can_eat_from_the_village_warehouse():
	_a_stocked(VillageLayout.WAREHOUSE_BUILDING_ID, "cooked_meat", 5)
	assert_true(
		manager.has_village_meal_near(_pixel_of(_store)),
		"the warehouse is full and the village has nothing to eat"
	)


## The shelf the settlement's own assessment counts must be the shelf its
## people can eat off. These were two different answers, which is how a
## village starves next to its own full store.
func test_what_the_settlement_counts_as_food_is_what_its_people_can_eat():
	_a_stocked(VillageLayout.WAREHOUSE_BUILDING_ID, "cooked_meat", 5)
	var stocks: Array = manager._settlement_larder_stocks(
		manager.EntityRef.for_settlement(_chunk_coord)
	)
	assert_false(stocks.is_empty(), "precondition: the settlement counts this shelf at all")
	assert_true(manager.has_village_meal_near(_pixel_of(_store)))


func test_the_older_stores_still_feed_people():
	_a_stocked("storage", "cooked_meat", 5)
	assert_true(manager.has_village_meal_near(_pixel_of(_store)))


func test_an_empty_warehouse_feeds_nobody():
	assert_true(manager.build_at_global(_store.x, _store.y, VillageLayout.WAREHOUSE_BUILDING_ID))
	assert_false(manager.has_village_meal_near(_pixel_of(_store)))


## A warehouse full of timber is not a meal.
func test_a_warehouse_holding_no_food_feeds_nobody():
	_a_stocked(VillageLayout.WAREHOUSE_BUILDING_ID, "wood", 20)
	assert_false(manager.has_village_meal_near(_pixel_of(_store)))


# -- the village's larder is what its people can eat ------------------------
#
# Reported as a village that kept drawing households while everybody in it
# starved. Measured (tools/probe_village_famine.gd) on a real village at
# t=1200, with hunger pinned at 1.00 and the worst-off villager 174 of 200
# through the starvation window:
#
#     settlement Market : 0
#     VillageMarket     : 0
#     structure shelves : 234
#       farmhouse  holds  68 food -- a villager there CANNOT eat it
#       farmhouse  holds  68 food -- a villager there CANNOT eat it
#       farmhouse  holds  96 food -- a villager there CANNOT eat it
#
# 234 units over twelve households is 19.5 each against a FED_THRESHOLD of
# 2.0, so VillageImmigration read the place as richly fed and kept sending
# people into a famine.
#
# SettlementFood.food_stock documents this argument as "a Storage holding
# hauled bread, a Bakery with loaves still on its shelf" -- shelves people
# eat off. _settlement_structure_stocks handed it EVERY shelf in the
# chunk. The caller was breaking its own parameter's contract.

func _settlement_larder() -> int:
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var total := 0
	for stock in manager._settlement_larder_stocks(
		manager.EntityRef.for_settlement(_chunk_coord)
	):
		for item_id in stock.stock:
			if catalog.kind_of(String(item_id)) == "food":
				total += int(stock.stock[item_id])
	return total


## A farmhouse full of grain is not the village's larder. It is where a
## harvest waits for the carter; nobody eats off it.
func test_a_farmhouse_shelf_is_not_the_villages_larder():
	_a_stocked("farmhouse", "cooked_meat", 50)
	assert_false(
		manager.has_village_meal_near(_pixel_of(_store)),
		"precondition: nobody can eat off a farmhouse"
	)
	assert_eq(_settlement_larder(), 0, "the village counted food nobody could eat")


func test_a_warehouse_shelf_is_the_villages_larder():
	_a_stocked(VillageLayout.WAREHOUSE_BUILDING_ID, "cooked_meat", 50)
	assert_eq(_settlement_larder(), 50)


## The two the parameter's own documentation names.
func test_a_storage_is_still_the_villages_larder():
	_a_stocked("storage", "cooked_meat", 7)
	assert_eq(_settlement_larder(), 7)


func test_a_bakery_is_still_the_villages_larder():
	_a_stocked("bakery", "bread", 9)
	assert_eq(_settlement_larder(), 9)


## The invariant, stated once: every unit the settlement counts is on a
## shelf somebody standing there could eat from.
func test_every_unit_the_village_counts_is_one_its_people_could_eat():
	_a_stocked("farmhouse", "cooked_meat", 50)
	if _settlement_larder() > 0:
		assert_true(
			manager.has_village_meal_near(_pixel_of(_store)),
			"the village counted a shelf its own people cannot reach"
		)
	else:
		assert_eq(_settlement_larder(), 0)
