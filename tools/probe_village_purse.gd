extends SceneTree

## Where does a village's FIRST gold come from?
##
## Commit 0514f08 ("gold has exactly one faucet, and it is the merchant")
## removed NpcProduction's conjured coin, so a settlement's only income is
## MerchantVisit: he arrives, buys real goods out of real containers, and
## pays into the purse NpcEconomy._draw_subsistence_wage draws from.
##
## tools/probe_village_famine.gd measured a village sitting on 99 units of
## market food and 117 on its shelves with BOTH purses at 0.0 gold and
## every villager broke. That is not "the gold landed in the wrong tank" --
## it is "no gold was ever made". This probe stands where
## EarthChunkManager._step_merchant_visits stands and reports its ACTUAL
## inputs: what is on the shelves by item id, what the village is saving
## for, how many of those units are on the merchant's buy list, and how
## much of a visit has accrued.
##
## Usage: godot --headless -s tools/probe_village_purse.gd

const MerchantVisit = preload("res://src/emergence/merchant_visit.gd")
const NpcEconomy = preload("res://src/world/npc_economy.gd")
const SettlementSurplus = preload("res://src/emergence/settlement_surplus.gd")

const CHUNK_SIZE := 32
const STEPS := 40
const SLICE := 0.25
const SIMULATED_SECONDS := 5000.0
## How often the timeline above prints a row.
const REPORT_EVERY := 500.0

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
		print("PURSE no populated village was met in %d chunk-widths" % STEPS)
	return true


func _villagers_in(chunk_coord: Vector2i) -> int:
	var count := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			count += 1
	return count


## Exactly the views _step_merchant_visits builds, in its own order.
func _merchant_views(settlement_id: String) -> Array:
	var market = _manager._market_store.market_for(settlement_id)
	var views: Array = []
	if market != null:
		views.append(market.stock)
	for shelf in _manager._settlement_structure_stocks(settlement_id):
		views.append(shelf.stock)
	return views


func _report_the_merchant(settlement_id: String) -> void:
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var catalog = ItemCatalog.new()
	var views := _merchant_views(settlement_id)
	var surplus: Dictionary = SettlementSurplus.combined(views)
	var reserved: Dictionary = _manager._construction_reserve_for(settlement_id)

	_lines.append("")
	_lines.append("  -- what the merchant is shown --")
	var item_ids: Array = []
	for item_id in surplus:
		item_ids.append(String(item_id))
	item_ids.sort()
	var on_list := 0
	var food_units := 0
	for item_id in item_ids:
		var units := int(floor(float(surplus[item_id])))
		if units <= 0:
			continue
		var kind: String = catalog.kind_of(item_id)
		var buys: bool = MerchantVisit.buy_list().has(item_id)
		if buys:
			on_list += units
		if kind == "food":
			food_units += units
		_lines.append("    %-16s %5d  kind=%-10s merchant %s" % [
			item_id, units, kind, "BUYS @%d" % MerchantVisit.price_of(item_id) if buys else "refuses"
		])
	_lines.append("  food units in the village : %d" % food_units)
	_lines.append("  units the merchant BUYS   : %d" % on_list)
	_lines.append("  sellable after reserve    : %d" % MerchantVisit.sellable_units(surplus, reserved))
	_lines.append("  reserved for next building: %s" % str(reserved))
	_lines.append("  visit accrued (0..1)      : %.3f" % float(
		_manager._settlement_merchant_carry.get(settlement_id, 0.0)
	))
	var sale: Dictionary = MerchantVisit.purchase(surplus, reserved)
	_lines.append("  a visit right now would pay: %d gold for %s" % [int(sale["paid"]), str(sale["bought"])])


func _sample() -> void:
	if _measured:
		return
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	var SettlementFood = load("res://src/emergence/settlement_food.gd")
	for chunk_coord in _manager._loaded_villages:
		if _villagers_in(chunk_coord) == 0:
			continue
		_measured = true
		var settlement_id: String = EntityRef.for_settlement(chunk_coord)
		_lines.append("")
		_lines.append("PURSE watch at %s" % str(chunk_coord))

		var elapsed := 0.0
		var next_report := 0.0
		_lines.append("  %8s %10s %10s %12s" % ["seconds", "sellable", "visit 0..1", "purse gold"])
		while elapsed < SIMULATED_SECONDS:
			if elapsed >= next_report:
				var purse_now = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)
				_lines.append("  %8.0f %10d %10.3f %12.1f" % [
					elapsed,
					MerchantVisit.sellable_units(
						SettlementSurplus.combined(_merchant_views(settlement_id)),
						_manager._construction_reserve_for(settlement_id)
					),
					float(_manager._settlement_merchant_carry.get(settlement_id, 0.0)),
					0.0 if purse_now == null else NpcEconomy.purse_of(purse_now),
				])
				next_report += REPORT_EVERY
			for node in _manager._loaded_villages.get(chunk_coord, []):
				if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
					node._process(SLICE)
			_manager.advance_world_age(SLICE)
			_manager.step_farm_plots(SLICE)
			_manager.step_settlements(SLICE)
			elapsed += SLICE

		var village_market = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)
		var traded = _manager._market_store.market_for(settlement_id)
		_lines.append("  after %.0f simulated seconds:" % elapsed)
		# The purse a wage is really drawn from is the LIVE VillageMarket's
		# own meta, which is where _step_merchant_visits pays. The
		# persisted ledger carries a purse of its own that nobody spends,
		# so both are printed: a village earning into the wrong tank looks
		# exactly like a village nobody ever paid.
		_lines.append("    village purse   %.1f gold" % (
			0.0 if village_market == null else NpcEconomy.purse_of(village_market)
		))
		_lines.append("    ledger purse    %.1f gold" % (
			0.0 if traded == null else NpcEconomy.purse_of(traded)
		))
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
		_lines.append("    %d of %d villagers broke" % [broke, villagers])
		_report_the_merchant(settlement_id)
		return
