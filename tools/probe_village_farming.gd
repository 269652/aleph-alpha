extends SceneTree

## Reported live with the field in shot: "it plows the soil but then the soil
## mound sprites don't appear and nothing gets planted, nothing grows and
## nothing gets harvested".
##
## Measures that against a REAL village's real field: who works it, what they
## sow, what each bed's FarmPlot actually holds after a stretch of work, and
## what the bed DRAWS -- so "nothing grows" can be told apart from "it grows
## and nothing is drawn", which look identical in a screenshot.
##
## Structural notes are probe_village_hunting.gd's (work in _process, load()
## at runtime, ask the SceneTree for groups).

const CHUNK_SIZE := 32
const STEPS := 40
const SIMULATED_SECONDS := 600.0
const SLICE := 0.1

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
var _report_lines: Array = []


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

	for line in _report_lines:
		print(line)
	if _report_lines.is_empty():
		print("FARMING no villager with a field was ever met in %d chunk-widths" % STEPS)
	return true


func _farmers_in() -> Array:
	var found: Array = []
	for chunk_coord in _manager._loaded_villages:
		for node in _manager._loaded_villages[chunk_coord]:
			if not is_instance_valid(node) or not node.has_method("setup_economy"):
				continue
			if not ("field_cells" in node) or node.field_cells.is_empty():
				continue
			found.append(node)
	return found


func _sample() -> void:
	if _measured:
		return
	var farmers := _farmers_in()
	if farmers.is_empty():
		return
	_measured = true
	for chunk_coord in _manager._loaded_villages:
		_report_market(chunk_coord)
	for farmer in farmers:
		_measure(farmer)


func _measure(farmer) -> void:
	var occupation: String = farmer.identity.occupation if farmer.identity != null else "?"
	var crop: String = farmer._field_crop
	var cells: Array = farmer.field_cells
	_report_lines.append("")
	_report_lines.append(
		"FARMER occupation=%s crop=%s cells=%d stock_building=%s"
		% [occupation, crop, cells.size(), str(farmer.stock_building_cell)]
	)

	var elapsed := 0.0
	var working_ticks := 0
	var planted_calls := 0
	while elapsed < SIMULATED_SECONDS:
		farmer._process(SLICE)
		_manager.step_farm_plots(SLICE)
		elapsed += SLICE
		if farmer._on_real_field:
			working_ticks += 1
	_report_lines.append(
		"  worked %d/%d ticks over %.0fs" % [working_ticks, int(SIMULATED_SECONDS / SLICE), SIMULATED_SECONDS]
	)

	for cell in cells:
		var marker = _manager._farm_plots.get(cell)
		if marker == null:
			_report_lines.append("  CELL %s no marker -- never tilled" % str(cell))
			continue
		var plot = marker.plot
		_report_lines.append(
			"  CELL %s state=%s crop=%s sown=%s grown=%.1f/%.1f soil_visible=%s draws_a_crop=%s blades=%d"
			% [
				str(cell), plot.state, plot.crop_id, marker._sown_crop_id,
				plot.time_growing, plot.growth_time,
				str(marker.is_showing_tilled_ground()),
				str(marker.is_drawing_a_crop()),
				marker.wheat_blade_count(),
			]
		)
	if farmer.economy != null and farmer.economy.market != null:
		_report_lines.append("  village market stock=%s" % str(farmer.economy.market.stock))


func _report_market(chunk_coord: Vector2i) -> void:
	var stands: Array = []
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and node.has_meta("landmark_id") and node.get_meta("landmark_id") == "stall":
			stands.append(node)
	for node in stands:
		var tile := Vector2i(int(node.position.x) / 16, int(node.position.y) / 16)
		_report_lines.append(
			"  STAND at %s visible=%s paving='%s'"
			% [str(tile), str(node.visible), _manager.modification_at_global(tile.x, tile.y)]
		)
	if not stands.is_empty():
		return
	var merchants := 0
	var villagers := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and node.has_method("setup_economy"):
			villagers += 1
			if node.identity != null and node.identity.occupation == "merchant":
				merchants += 1
	if villagers == 0:
		return
	var VillageLayout = load("res://src/world/village_layout.gd")
	var skeleton: Dictionary = VillageLayout.skeleton(32, VillageLayout.seed_for(chunk_coord))
	var planned: Array = VillageLayout.market_stand_cells(skeleton, maxi(merchants, 1))
	var paving: Array = []
	for cell in planned:
		var g: Vector2i = chunk_coord * 32 + cell
		paving.append("%s='%s'" % [str(cell), _manager.modification_at_global(g.x, g.y)])
	_report_lines.append(
		"  STAND none at %s -- villagers=%d merchants=%d planned=%s"
		% [str(chunk_coord), villagers, merchants, str(paving)]
	)
