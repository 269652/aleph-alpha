extends SceneTree

## Where a village's herbs, food and gold actually are, step by step.
##
## Reported with the town panel open: every cottage reads "Herb 0%" while
## the village has a herbalist, "Food 85%" while the card says the village
## feeds 25 of 10, "Gold 1" and happiness "worst: income". This probe walks
## a real village and prints, every REPORT_EVERY seconds, each container
## the herbs could be in, the estate satisfaction the panel reads, the
## purse, the wallets, and what the merchant has carried off -- so the
## fault is measured rather than guessed at.
##
## Usage: godot --headless -s tools/probe_village_economy.gd

const CHUNK_SIZE := 32
const STEPS := 40
const SLICE := 0.25
const SIMULATED_SECONDS := 1200.0
const REPORT_EVERY := 150.0

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
		print("ECONOMY no populated village was met in %d chunk-widths" % STEPS)
	return true


func _villagers(chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			if node.economy != null:
				out.append(node)
	return out


func _village_market(chunk_coord: Vector2i):
	for node in _villagers(chunk_coord):
		if node.economy.market != null:
			return node.economy.market
	return null


func _units_of(view: Dictionary, item_id: String) -> float:
	return float(view.get(item_id, 0.0))


func _shelf_units(settlement_id: String, item_id: String) -> float:
	var total := 0.0
	for stock in _manager._settlement_structure_stocks(settlement_id):
		total += float(stock.stock.get(item_id, 0))
	return total


func _food_units(views: Array, catalog) -> float:
	var total := 0.0
	for view in views:
		for item_id in view:
			if catalog.kind_of(String(item_id)) == "food":
				total += float(view[item_id])
	return total


func _wallets(chunk_coord: Vector2i) -> Dictionary:
	var total := 0
	var broke := 0
	var count := 0
	for node in _villagers(chunk_coord):
		if node.economy.wallet == null:
			continue
		count += 1
		total += int(node.economy.wallet.balance)
		if node.economy.wallet.balance < 1:
			broke += 1
	return {"total": total, "broke": broke, "count": count}


func _occupations(chunk_coord: Vector2i) -> Dictionary:
	var counts := {}
	for node in _villagers(chunk_coord):
		var occupation := String(node.identity.occupation) if node.identity != null else "?"
		counts[occupation] = int(counts.get(occupation, 0)) + 1
	return counts


func _sample() -> void:
	if _measured:
		return
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	var NpcEconomy = load("res://src/world/npc_economy.gd")
	var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
	var HouseholdWellbeing = load("res://src/emergence/household_wellbeing.gd")
	var catalog = ItemCatalog.new()
	for chunk_coord in _manager._loaded_villages:
		if _villagers(chunk_coord).is_empty():
			continue
		_measured = true
		var settlement_id: String = EntityRef.for_settlement(chunk_coord)
		_lines.append("")
		_lines.append("ECONOMY watch at %s  occupations %s" % [str(chunk_coord), str(_occupations(chunk_coord))])
		_lines.append("  buildings: %s" % str(_manager._settlement_building_counts(chunk_coord)))
		_lines.append(
			"  %7s %6s | %6s %6s %6s | %5s %5s %5s | %6s %6s %6s | %7s %7s %5s | %5s %-9s" % [
				"seconds", "roster", "herbVM", "herbM", "herbSh", "satH", "satF", "satW",
				"foodVM", "foodM", "foodSh", "purse", "wallet", "broke", "happy", "worst"
			]
		)
		var elapsed := 0.0
		var next_report := 0.0
		while elapsed <= SIMULATED_SECONDS:
			if elapsed >= next_report:
				_lines.append(_row(elapsed, chunk_coord, settlement_id, NpcEconomy, catalog, HouseholdWellbeing))
				next_report += REPORT_EVERY
			for node in _villagers(chunk_coord):
				node._process(SLICE)
			_manager.advance_world_age(SLICE)
			_manager.step_farm_plots(SLICE)
			_manager.step_settlements(SLICE)
			elapsed += SLICE
		_report_where_the_herbs_are(chunk_coord, settlement_id, catalog)
		return


func _row(elapsed: float, chunk_coord: Vector2i, settlement_id: String, NpcEconomy, catalog, HouseholdWellbeing) -> String:
	var village_market = _village_market(chunk_coord)
	var market = _manager._market_store.market_for(settlement_id)
	var vm_stock: Dictionary = {} if village_market == null else village_market.stock
	var satisfaction: Dictionary = _manager.estate_satisfaction_for_settlement(settlement_id)
	var wallets := _wallets(chunk_coord)
	var assessments: Array = _manager._household_wellbeing_for_settlement(settlement_id)
	var happiness := 0.0
	var worst := ""
	var worst_score := INF
	var needs_sum := {}
	for assessment in assessments:
		happiness += float(assessment["happiness"])
		for need_id in assessment["needs"]:
			needs_sum[need_id] = float(needs_sum.get(need_id, 0.0)) + float(assessment["needs"][need_id])
	if not assessments.is_empty():
		happiness /= float(assessments.size())
		for need_id in needs_sum:
			if float(needs_sum[need_id]) < worst_score:
				worst_score = float(needs_sum[need_id])
				worst = String(need_id)
	var shelves: Array = []
	for stock in _manager._settlement_structure_stocks(settlement_id):
		shelves.append(stock.stock)
	return "  %7.0f %6d | %6.1f %6d %6.0f | %5.2f %5.2f %5.2f | %6.0f %6.0f %6.0f | %7.1f %7d %5d | %5.2f %-9s" % [
		elapsed,
		_manager.household_count_for_settlement(settlement_id),
		_units_of(vm_stock, "herb"), market.stock_of("herb"), _shelf_units(settlement_id, "herb"),
		float(satisfaction.get("herb", -1.0)), float(satisfaction.get("kind:food", -1.0)), float(satisfaction.get("wood", -1.0)),
		_food_units([vm_stock], catalog), _food_units([market.stock], catalog), _food_units(shelves, catalog),
		0.0 if village_market == null else NpcEconomy.purse_of(village_market),
		int(wallets["total"]), int(wallets["broke"]),
		happiness, worst,
	]


func _report_where_the_herbs_are(chunk_coord: Vector2i, settlement_id: String, catalog) -> void:
	_lines.append("")
	_lines.append("  -- where the herbs and the food are --")
	var village_market = _village_market(chunk_coord)
	if village_market != null:
		_lines.append("  VillageMarket stock: %s" % str(village_market.stock))
	_lines.append("  settlement Market stock: %s" % str(_manager._market_store.market_for(settlement_id).stock))
	for record in _manager.buildings_in_chunk(chunk_coord):
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(record["origin_local"])
		var held: Dictionary = _manager.structure_stock_contents_at(tile.x, tile.y)
		if held.is_empty():
			continue
		_lines.append("    %-12s holds %s" % [String(record["id"]), str(held)])
	_lines.append("  estate satisfaction: %s" % str(_manager.estate_satisfaction_for_settlement(settlement_id)))
	_lines.append("  merchant carry: %s" % str(_manager._settlement_merchant_carry.get(settlement_id, 0.0)))
