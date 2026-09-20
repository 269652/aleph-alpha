extends SceneTree

## Where does a village's food actually SIT, and why is the stall empty?
##
## milling_and_baking.md's own open list calls this "three food containers,
## one eater": a villager eats from the stall, the persisted Market and the
## structure shelves alike, "but nothing ever moves food between them".
## Measured repeatedly since: farmhouses holding 5, 12 and 12 units with
## `VillageMarket 0` and `settlement Market 0` at every sample.
##
## A village moves food along a real chain -- field -> farmhouse shelf ->
## (a carter's round) -> the store -> ...and the stall, which is the link
## in question. This prints EVERY container separately over time, plus
## what is in the villagers' own hands, because "the market is empty" is
## consistent with the carter never running, the carter running and
## crediting the wrong place, or nobody producing at all.
##
## Usage: godot --headless -s tools/probe_food_containers.gd

const SettlementFood = preload("res://src/emergence/settlement_food.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")

const CHUNK_SIZE := 32
const STEPS := 40
const SLICE := 0.25
const SIMULATED_SECONDS := 600.0
const REPORT_EVERY := 100.0

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
var _lines: Array = []
var _catalog


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_catalog = load("res://src/gameplay/item_catalog.gd").new()


func _process(_delta: float) -> bool:
	if _step < 0:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tile_map_layer := TileMapLayer.new()
		var entities := Node2D.new()
		var creatures := Node2D.new()
		root.add_child(tile_map_layer)
		root.add_child(entities)
		root.add_child(creatures)
		_manager = EarthChunkManager.new(tile_map_layer, entities, creatures)
		_step = 0
		return false

	if _step < STEPS and not _measured:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false

	for line in _lines:
		print(line)
	if _lines.is_empty():
		print("CONTAINERS no populated village was met in %d chunk-widths" % STEPS)
	return true


func _villagers_in(chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			out.append(node)
	return out


func _food_of(held: Dictionary) -> int:
	var total := 0
	for item_id in held:
		if _catalog.kind_of(String(item_id)) == "food":
			total += int(held[item_id])
	return total


## Food on the shelves of every building of `building_id` in this chunk.
func _shelf_food(chunk_coord: Vector2i, building_id: String) -> int:
	var total := 0
	for record in _manager.buildings_in_chunk(chunk_coord):
		if String(record["id"]) != building_id:
			continue
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(record["origin_local"])
		total += _food_of(_manager.structure_stock_contents_at(tile.x, tile.y))
	return total


## Food in the villagers' own HANDS (NpcEconomy.carried) -- where hauling
## puts a producer's take until they walk it somewhere.
func _food_in_hands(chunk_coord: Vector2i) -> int:
	var total := 0
	for node in _villagers_in(chunk_coord):
		if node.economy == null:
			continue
		total += _food_of(node.economy.carried)
	return total


## ...and on the carts, which are a real container too.
func _food_on_carts(chunk_coord: Vector2i) -> int:
	var total := 0
	for node in _villagers_in(chunk_coord):
		if node.cart == null or not is_instance_valid(node.cart):
			continue
		total += _food_of(node.cart.stock)
	return total


func _carters_in(chunk_coord: Vector2i) -> int:
	var count := 0
	for node in _villagers_in(chunk_coord):
		if node.store_cell != node.NO_STORE:
			count += 1
	return count


func _sample() -> void:
	if _measured:
		return
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	for chunk_coord in _manager._loaded_villages:
		if _villagers_in(chunk_coord).is_empty():
			continue
		_measured = true
		var settlement_id: String = EntityRef.for_settlement(chunk_coord)
		var village_market = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)
		_lines.append("")
		_lines.append("FOOD CONTAINERS at %s   (%d carters of %d villagers)" % [
			str(chunk_coord), _carters_in(chunk_coord), _villagers_in(chunk_coord).size()
		])
		_lines.append("  %7s %9s %9s %8s %7s %6s %6s" % [
			"seconds", "farmhouse", "warehouse", "STALL", "ledger", "hands", "carts"
		])

		var elapsed := 0.0
		var next_report := 0.0
		while elapsed < SIMULATED_SECONDS:
			if elapsed >= next_report:
				var traded = _manager._market_store.market_for(settlement_id)
				_lines.append("  %7.0f %9d %9d %8d %7d %6d %6d" % [
					elapsed,
					_shelf_food(chunk_coord, "farmhouse"),
					_shelf_food(chunk_coord, VillageLayout.WAREHOUSE_BUILDING_ID),
					0 if village_market == null else SettlementFood.food_stock(null, village_market, _catalog, []),
					SettlementFood.food_stock(traded, null, _catalog, []),
					_food_in_hands(chunk_coord),
					_food_on_carts(chunk_coord),
				])
				next_report += REPORT_EVERY
			for node in _villagers_in(chunk_coord):
				node._process(SLICE)
			_manager.advance_world_age(SLICE)
			_manager.step_farm_plots(SLICE)
			_manager.step_settlements(SLICE)
			elapsed += SLICE
		return
