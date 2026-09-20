extends GutTest

## docs/concept/village_economy_balance.md mechanism 5: a household eats
## from the village, not from one of its cupboards -- the estate draw reads
## the larder shelves too.
##
## MEASURED before this existed (tools/probe_village_economy.gd, a real
## village east of Berlin): the herbalist's crop sat on the farmhouse shelf
## -- 13, 21, 43 units -- while the stall held none, and every cottage read
## "Herb 0%". The one sample with three herbs on the stall read 1.00.
##
## Uses the fast (0, 0) chunk and build_at_global, exactly as
## test_earth_chunk_manager_village_meals.gd does.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _shelf := Vector2i(10, 6)
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
	manager._load_chunk(_chunk_coord)
	_settlement_id = EntityRef.for_settlement(_chunk_coord)
	var npcs: Array = []
	for i in 4:
		npcs.append(FakeNpc.new(940_000 + i))
	manager.record_settlement_founded_if_new(_chunk_coord, npcs)


func after_each():
	remove_child(tile_map_layer)
	remove_child(entities_parent)
	manager.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _a_stocked(structure_id: String, item_id: String, count: int) -> void:
	assert_true(
		manager.build_at_global(_shelf.x, _shelf.y, structure_id),
		"precondition: the %s stands" % structure_id
	)
	manager.deposit_to_structure_at(_shelf.x, _shelf.y, item_id, count)


func _on_the_shelf(item_id: String) -> int:
	return int(manager.structure_stock_contents_at(_shelf.x, _shelf.y).get(item_id, 0))


func _market():
	return manager.market_store().market_for(_settlement_id)


func _draw(demand: Dictionary) -> Dictionary:
	return manager._draw_estate_basket(_market(), null, _settlement_id, demand)


## The regression, through the real step: forty herbs on the farmhouse
## shelf and none on the stall is a village whose cottagers have herbs.
func test_a_basket_good_on_a_larder_shelf_is_a_good_the_households_have():
	_a_stocked(VillageFarm.FARM_BUILDING_ID, "herb", 40)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var satisfaction: Dictionary = manager.estate_satisfaction_for_settlement(_settlement_id)
	assert_almost_eq(float(satisfaction.get("herb", 0.0)), 1.0, 0.0001, "the herbs on the shelf were not the households'")


## And the goods really leave the shelf when a whole unit is owed.
func test_the_draw_really_takes_the_goods_off_the_shelf():
	_a_stocked(VillageFarm.FARM_BUILDING_ID, "herb", 40)
	var satisfaction := _draw({"herb": 3.0})
	assert_almost_eq(float(satisfaction.get("herb", 0.0)), 1.0, 0.0001)
	assert_eq(_on_the_shelf("herb"), 37)


## Stall, ledger, shelves: what the player can walk up to and open is the
## last thing to go, the same rule the merchant's sale keeps.
func test_the_markets_are_drawn_before_the_shelves():
	_market().add_stock("herb", 2)
	_a_stocked(VillageFarm.FARM_BUILDING_ID, "herb", 40)
	_draw({"herb": 3.0})
	assert_eq(_market().stock_of("herb"), 0, "the ledger goes first")
	assert_eq(_on_the_shelf("herb"), 39, "and the shelf covers the rest")


## A shelf nobody eats off is not the households' larder: a sawmill's
## timber is the village's income, not its dinner.
func test_a_shelf_nobody_eats_off_is_not_the_households_larder():
	_a_stocked("sawmill", "herb", 40)
	var satisfaction := _draw({"herb": 3.0})
	assert_almost_eq(float(satisfaction.get("herb", 1.0)), 0.0, 0.0001)
	assert_eq(_on_the_shelf("herb"), 40)


## A shelf counts in whole units like the ledger does, so the fraction is
## carried rather than taken -- a twentieth of a herb does not cost a herb.
func test_the_fraction_of_a_shelf_unit_is_carried_rather_than_taken():
	_a_stocked(VillageFarm.FARM_BUILDING_ID, "herb", 40)
	_draw({"herb": 0.4})
	assert_eq(_on_the_shelf("herb"), 40, "nothing whole was owed yet")
	assert_almost_eq(float(manager.estate_draw_carry_for(_settlement_id).get("herb", 0.0)), 0.4, 0.0001)
	_draw({"herb": 0.4})
	_draw({"herb": 0.4})
	assert_eq(_on_the_shelf("herb"), 39, "the third fraction crossed a whole unit")
	assert_almost_eq(float(manager.estate_draw_carry_for(_settlement_id).get("herb", 0.0)), 0.2, 0.0001)


## The village had less than it wanted, and does NOT go into debt for the
## rest -- the same rule the ledger's own draw keeps.
func test_a_shelf_short_of_the_draw_is_emptied_and_no_debt_is_kept():
	_a_stocked(VillageFarm.FARM_BUILDING_ID, "herb", 2)
	var satisfaction := _draw({"herb": 5.0})
	assert_almost_eq(float(satisfaction.get("herb", 0.0)), 0.4, 0.0001)
	assert_eq(_on_the_shelf("herb"), 0)
	assert_almost_eq(float(manager.estate_draw_carry_for(_settlement_id).get("herb", 0.0)), 0.0, 0.0001)
