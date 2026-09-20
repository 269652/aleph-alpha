extends SceneTree

## Why a real field yields a third of what the stub-world measurement says:
## every 30 seconds, each farmhouse's water, its farmer's whereabouts, and
## the state of each of its beds -- so a withering bed, a dry farmhouse or a
## farmer forever at the well shows up as a column rather than a guess.
##
## Usage: godot --headless -s tools/probe_field_timeline.gd

const CHUNK_SIZE := 32
const STEPS := 40
const SLICE := 0.25
const SIMULATED_SECONDS := 600.0
const REPORT_EVERY := 30.0

var _manager
var _origin: Vector2i
var _step := -1
var _done := false
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
	if _step < STEPS and not _done:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		for chunk_coord in _manager._loaded_villages:
			if not _farmers(chunk_coord).is_empty():
				_watch(chunk_coord)
				_done = true
				for line in _lines:
					print(line)
				return true
		_step += 1
		return false
	print("FIELD TIMELINE: no village with a farmer met")
	return true


func _villagers(chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("setup_economy"):
			out.append(node)
	return out


func _farmers(chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for node in _villagers(chunk_coord):
		if "field_cells" in node and node.field_cells.size() > 0:
			out.append(node)
	return out


func _bed_states(node) -> String:
	var counts := {"empty": 0, "growing": 0, "ready": 0, "withered": 0, "none": 0}
	for cell in node.field_cells:
		var plot = _manager.farm_plot_at_global(cell.x, cell.y)
		if plot == null:
			counts["none"] += 1
		elif plot.is_withered():
			counts["withered"] += 1
		elif plot.is_ready():
			counts["ready"] += 1
		elif plot.state == "empty":
			counts["empty"] += 1
		else:
			counts["growing"] += 1
	return "e%d g%d r%d w%d n%d" % [counts["empty"], counts["growing"], counts["ready"], counts["withered"], counts["none"]]


func _water_of(node) -> String:
	var found: Dictionary = _manager.building_at_global(node.stock_building_cell.x, node.stock_building_cell.y)
	if found.is_empty():
		return "?"
	var record: Dictionary = _manager.building_record_at(found["chunk_coord"], found["origin_local"])
	return "%.0f" % _manager.house_water_at(record)


func _watch(chunk_coord: Vector2i) -> void:
	var catalog = load("res://src/gameplay/item_catalog.gd").new()
	var farmers := _farmers(chunk_coord)
	_lines.append("FIELD TIMELINE at %s: %d farmers with fields" % [str(chunk_coord), farmers.size()])
	var header := "  %6s %5s" % ["sec", "hour"]
	for farmer in farmers:
		header += " | %-9s water  loc        beds" % String(farmer.identity.occupation)
	_lines.append(header)
	var harvested := 0.0
	var last_farm_food := _farmhouse_food(chunk_coord, catalog)
	var elapsed := 0.0
	var next_report := 0.0
	while elapsed <= SIMULATED_SECONDS:
		if elapsed >= next_report:
			var row := "  %6.0f %5d" % [elapsed, _manager.hour_of_day() if _manager.has_method("hour_of_day") else -1]
			for farmer in farmers:
				row += " | %-9s %5s  %-10s %s" % [
					"", _water_of(farmer), String(farmer._last_location_tag), _bed_states(farmer)
				]
			row += "  harvested %.0f" % harvested
			_lines.append(row)
			next_report += REPORT_EVERY
		for node in _villagers(chunk_coord):
			node._process(SLICE)
		_manager.advance_world_age(SLICE)
		_manager.step_farm_plots(SLICE)
		_manager.step_settlements(SLICE)
		elapsed += SLICE
		var farm_food := _farmhouse_food(chunk_coord, catalog)
		if farm_food > last_farm_food:
			harvested += farm_food - last_farm_food
		last_farm_food = farm_food


func _farmhouse_food(chunk_coord: Vector2i, catalog) -> float:
	var VillageFarm = load("res://src/gameplay/village_farm.gd")
	var total := 0.0
	for record in _manager.buildings_in_chunk(chunk_coord):
		if String(record["id"]) != VillageFarm.FARM_BUILDING_ID:
			continue
		var tile: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(record["origin_local"])
		var held: Dictionary = _manager.structure_stock_contents_at(tile.x, tile.y)
		for item_id in held:
			if catalog.kind_of(String(item_id)) == "food":
				total += float(held[item_id])
	return total
