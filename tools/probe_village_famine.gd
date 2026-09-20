extends SceneTree

## Does a real village feed itself, or does it starve to death?
##
## Starvation (docs/concept/village_mortality.md) kills a villager who
## spends Starvation.seconds_to_die at the top of their hunger drive --
## about 200 seconds of real play. That is a deliberately short fuse, and
## it is pointed at every village in the world at once, so the question
## "does an ordinary village survive being simulated?" is not rhetorical.
##
## Reports the roster and the villagers standing over time, so a village
## that quietly wipes itself out shows up as a number rather than as a
## surprise in somebody's save.
##
## Usage: godot --headless -s tools/probe_village_famine.gd

const Starvation = preload("res://src/emergence/starvation.gd")

const CHUNK_SIZE := 32
const STEPS := 40
const SLICE := 0.25
## Long enough for several starvation windows to pass end to end.
const SIMULATED_SECONDS := 1200.0
const REPORT_EVERY := 300.0

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
var _lines: Array = []


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)


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
		print("FAMINE no populated village was met in %d chunk-widths" % STEPS)
	return true


func _villagers_in(chunk_coord: Vector2i) -> int:
	var count := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			count += 1
	return count


## How far the worst-off villager has got through the starvation window.
## Hunger sitting at 1.00 says nothing on its own -- it reads the same for
## somebody who emptied a second ago and somebody about to die -- so this
## is what tells "fed just in time" apart from "the death never fires".
func _most_starved(chunk_coord: Vector2i) -> float:
	var worst := 0.0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if not is_instance_valid(node) or not node.has_method("setup_economy"):
			continue
		if node.economy == null:
			continue
		worst = maxf(worst, node.economy.needs.starved_seconds)
	return worst


func _hungriest(chunk_coord: Vector2i) -> float:
	var worst := 0.0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if not is_instance_valid(node) or not node.has_method("setup_economy"):
			continue
		if node.economy == null:
			continue
		worst = maxf(worst, node.economy.needs.hunger)
	return worst


## Everything edible in the village's own market -- the shelf a villager
## who cannot forage actually buys from. "They starved" and "there was
## food and they could not reach it" want different fixes.
func _market_food(chunk_coord: Vector2i) -> int:
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if not is_instance_valid(node) or not node.has_method("setup_economy"):
			continue
		if node.economy == null or node.economy.market == null:
			continue
		var total := 0
		for item_id in node.economy.market.stock:
			if catalog.kind_of(String(item_id)) == "food":
				total += int(node.economy.market.stock[item_id])
		return total
	return 0


## WHERE the food the immigration gate counts actually is, and whether a
## villager could eat it. The gate reads SettlementFood.food_stock across
## three containers; a villager eats from the Market or from a structure
## in STRUCTURE_MEAL_SOURCE_IDS. Those are not the same set, so a village
## can be judged fed while its people starve -- which is exactly what the
## rows above show.
func _report_where_the_food_is(chunk_coord: Vector2i, settlement_id: String) -> void:
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var SettlementFood = load("res://src/emergence/settlement_food.gd")
	var catalog = ItemCatalog.new()
	var market = _manager._market_store.market_for(settlement_id)
	var village_market = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)

	_lines.append("")
	_lines.append("  -- where the food the gate counts actually is --")
	_lines.append("  settlement Market : %d" % SettlementFood.food_stock(market, null, catalog, []))
	_lines.append("  VillageMarket     : %d" % SettlementFood.food_stock(null, village_market, catalog, []))
	_lines.append(
		"  structure shelves : %d"
		% SettlementFood.food_stock(null, null, catalog, _manager._settlement_structure_stocks(settlement_id))
	)
	for record in _manager.buildings_in_chunk(chunk_coord):
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(record["origin_local"])
		var held: Dictionary = _manager.structure_stock_contents_at(tile.x, tile.y)
		var food := 0
		for item_id in held:
			if catalog.kind_of(String(item_id)) == "food":
				food += int(held[item_id])
		if food <= 0:
			continue
		var pixel := (Vector2(tile) + Vector2(0.5, 0.5)) * 16.0
		_lines.append(
			"    %-12s holds %3d food -- a villager there %s eat it"
			% [String(record["id"]), food, "CAN" if _manager.has_village_meal_near(pixel) else "CANNOT"]
		)


## The village purse and the villagers' own pockets. Once food is on the
## stall, MONEY is the next thing that can stop somebody eating:
## NpcEconomy._try_eat draws a subsistence wage from the purse and then
## BUYS. A village with a full market and an empty purse starves beside
## its own food.
func _purse_and_pockets(chunk_coord: Vector2i, settlement_id: String) -> String:
	var NpcEconomy = load("res://src/world/npc_economy.gd")
	var SettlementFood = load("res://src/emergence/settlement_food.gd")
	var village_market = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)
	var purse: float = 0.0 if village_market == null else NpcEconomy.purse_of(village_market)
	# The OTHER purse. The merchant deposits into the emergence Market
	# (EarthChunkManager._step_merchant_visits), while the subsistence wage
	# and the settlement card read the VillageMarket's own meta. If gold is
	# sitting in one and nobody draws from the other, the faucet is
	# plumbed to the wrong tank -- and that is a different bug from a
	# merchant who never came.
	var traded = _manager._market_store.market_for(settlement_id)
	var trade_purse: float = 0.0 if traded == null else NpcEconomy.purse_of(traded)
	var broke := 0
	var villagers := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if not is_instance_valid(node) or not node.has_method("setup_economy"):
			continue
		if node.economy == null or node.economy.wallet == null:
			continue
		villagers += 1
		if node.economy.wallet.balance < 1.0:
			broke += 1
	return "villagers' purse %.1f gold | merchant's purse %.1f gold | %d of %d villagers broke" % [
		purse, trade_purse, broke, villagers
	]


func _sample() -> void:
	if _measured:
		return
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	for chunk_coord in _manager._loaded_villages:
		if _villagers_in(chunk_coord) == 0:
			continue
		_measured = true
		var settlement_id: String = EntityRef.for_settlement(chunk_coord)
		_lines.append("")
		_lines.append("FAMINE watch at %s" % str(chunk_coord))
		_lines.append(
			"  %8s %8s %10s %10s %10s" % ["seconds", "roster", "standing", "hungriest", "market food"]
		)

		var elapsed := 0.0
		var next_report := 0.0
		while elapsed < SIMULATED_SECONDS:
			if elapsed >= next_report:
				_lines.append("  %8.0f %8d %10d %10.2f %10d %6.0f/%-5.0f" % [
					elapsed,
					_manager.household_count_for_settlement(settlement_id),
					_villagers_in(chunk_coord),
					_hungriest(chunk_coord),
					_market_food(chunk_coord),
					_most_starved(chunk_coord), Starvation.seconds_to_die(),
				])
				next_report += REPORT_EVERY
			# The villagers themselves. Hand-ticked because _sample runs
			# synchronously inside one frame, so the engine never gets a
			# turn -- the same shape probe_village_farming.gd uses.
			for node in _manager._loaded_villages.get(chunk_coord, []):
				if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
					node._process(SLICE)
			# ...and the world around them. Without the CLOCK and the FARM
			# PLOTS this measures a village that can never grow anything,
			# which would make "they all starved" a fact about the probe
			# rather than about the game -- the exact mistake that made the
			# first cut of LITRES_PER_TENDING four times too big.
			_manager.advance_world_age(SLICE)
			_manager.step_farm_plots(SLICE)
			_manager.step_settlements(SLICE)
			elapsed += SLICE
		_lines.append("  %8.0f %8d %10d %10.2f %10d %6.0f/%-5.0f" % [
			elapsed,
			_manager.household_count_for_settlement(settlement_id),
			_villagers_in(chunk_coord),
			_hungriest(chunk_coord),
			_market_food(chunk_coord),
			_most_starved(chunk_coord), Starvation.seconds_to_die(),
		])
		_lines.append("  %s" % _purse_and_pockets(chunk_coord, settlement_id))
		_report_where_the_food_is(chunk_coord, settlement_id)
		return
