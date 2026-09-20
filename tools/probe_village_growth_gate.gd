extends SceneTree

## Why does a real village stop growing?
##
## Measured after the gold faucet was closed and repaired
## (docs/concept/traveling_merchants.md): the roster HOLDS at its founding
## ten for a whole 1200-second watch, where the same village used to reach
## twelve. Surviving is not growing, and "it stopped growing" has at least
## four different causes that look identical from outside.
##
## VillageImmigration.arrivals gates on THREE things at once -- room in
## houses that already stand, food per household against FED_THRESHOLD, and
## the accrued rate -- and VillageGrowth is what is supposed to MAKE the
## room. This prints each of them, every REPORT_EVERY seconds, so the one
## that is actually shut shows up as a number instead of a theory.
##
## Usage: godot --headless -s tools/probe_village_growth_gate.gd

const VillageImmigration = preload("res://src/emergence/village_immigration.gd")
const VillageGrowth = preload("res://src/emergence/village_growth.gd")
const SettlementFood = preload("res://src/emergence/settlement_food.gd")

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
		print("GATE no populated village was met in %d chunk-widths" % STEPS)
	return true


func _villagers_in(chunk_coord: Vector2i) -> int:
	var count := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			count += 1
	return count


## Exactly the three numbers VillageImmigration.arrivals is handed, read
## the same way _step_village_immigration reads them.
func _gate(chunk_coord: Vector2i, settlement_id: String) -> Dictionary:
	var household_ids: Array = _manager._households_in_settlement(settlement_id)
	if household_ids.is_empty():
		return {}
	var census: Dictionary = _manager._village_census_for(chunk_coord, household_ids)
	var market = _manager._market_store.market_for(settlement_id)
	var present: Array = _manager._present_structure_ids_for_settlement_chunk(chunk_coord)
	return {
		"households": household_ids.size(),
		"housed": int(census["housed_count"]),
		"room": int(census["spare_house_capacity"]),
		"food_per_household": _manager._food_per_household(
			settlement_id, market, household_ids.size()
		),
		"ladder_share": VillageGrowth.ladder_share(present),
		"carry": float(_manager._settlement_immigration_carry.get(settlement_id, 0.0)),
		# Through the SAME function the village really asks -- the assembly,
		# not VillageGrowth's ladder directly. The first cut of this probe
		# asked the ladder with three arguments, so `spare_house_capacity`
		# defaulted to "there is already room" and the column read "-" for
		# a reason that was about the probe rather than the village.
		"next_building": _manager.next_building_for_settlement(chunk_coord),
	}


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
		_lines.append("GROWTH GATE at %s   (FED_THRESHOLD %.1f)" % [
			str(chunk_coord), VillageImmigration.FED_THRESHOLD
		])
		_lines.append("  %7s %6s %6s %5s %8s %7s %6s  %s" % [
			"seconds", "house", "housed", "room", "food/hh", "ladder", "carry", "next build"
		])

		var elapsed := 0.0
		var next_report := 0.0
		while elapsed < SIMULATED_SECONDS:
			if elapsed >= next_report:
				var g := _gate(chunk_coord, settlement_id)
				if g.is_empty():
					_lines.append("  %7.0f  (no households)" % elapsed)
				else:
					_lines.append("  %7.0f %6d %6d %5d %8.2f %7.2f %6.2f  %s%s" % [
						elapsed, g["households"], g["housed"], g["room"],
						g["food_per_household"], g["ladder_share"], g["carry"],
						str(g["next_building"]) if str(g["next_building"]) != "" else "-",
						"" if float(g["food_per_household"]) >= VillageImmigration.FED_THRESHOLD
							else "   <- HUNGRY, gate shut",
					])
				next_report += REPORT_EVERY
			for node in _manager._loaded_villages.get(chunk_coord, []):
				if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
					node._process(SLICE)
			_manager.advance_world_age(SLICE)
			_manager.step_farm_plots(SLICE)
			_manager.step_settlements(SLICE)
			elapsed += SLICE

		_lines.append("")
		_lines.append("  -- where the food the gate counts actually is --")
		var ItemCatalog = load("res://src/gameplay/item_catalog.gd")
		var catalog = ItemCatalog.new()
		var market = _manager._market_store.market_for(settlement_id)
		var village_market = SettlementFood.village_market_for(settlement_id, _manager._loaded_villages)
		_lines.append("  settlement Market : %d" % SettlementFood.food_stock(market, null, catalog, []))
		_lines.append("  VillageMarket     : %d" % SettlementFood.food_stock(null, village_market, catalog, []))
		_lines.append("  larder shelves    : %d" % SettlementFood.food_stock(
			null, null, catalog, _manager._settlement_larder_stocks(settlement_id)
		))
		_lines.append("")
		_lines.append("  -- what stands in the village --")
		var standing: Dictionary = {}
		for record in _manager.buildings_in_chunk(chunk_coord):
			var id := String(record["id"])
			standing[id] = int(standing.get(id, 0)) + 1
		for id in standing:
			_lines.append("    %-14s x%d" % [id, standing[id]])
		return
