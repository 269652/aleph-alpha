extends SceneTree

## What a REAL village field actually costs its farmhouse's tank
## (docs/concept/village_water.md mechanism 3).
##
## This probe exists because the first cut of LITRES_PER_TENDING was pinned
## against an ASSUMED tending rate -- "a living field is tended more than
## once a simulated day" -- and the assumption was wrong by an order of
## magnitude. Billed at that rate the farmhouse ran dry almost at once and
## the field starved: measured against the same village,
## tools/probe_village_farming.gd went from 164 wheat harvested to 24.
##
## So the rate is measured here rather than reasoned about. Read
## `tendings/day` off a run where `dry ticks` is 0 -- a farm that is being
## REFUSED water is not being tended at its natural rate, and its number
## understates the real one.
##
## Usage: godot --headless -s tools/probe_farm_water.gd
##
## Structural notes are probe_village_farming.gd's, whose village and
## sampling this deliberately mirrors so the two runs are comparable.

const HouseholdWater = preload("res://src/emergence/household_water.gd")

const CHUNK_SIZE := 32
const STEPS := 40
const SIMULATED_SECONDS := 600.0
const SLICE := 0.1
## The player-felt day (EarthChunkManager.SECONDS_PER_SIMULATED_DAY).
const SECONDS_PER_DAY := 60.0

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
		print("FARM WATER no villager with a field was ever met in %d chunk-widths" % STEPS)
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
	_report_lines.append(
		"-- one tending currently costs %.2f L; the tank holds %.0f and keeps %.0f back --"
		% [HouseholdWater.LITRES_PER_TENDING, HouseholdWater.TANK_LITRES, HouseholdWater.DRINKING_RESERVE_LITRES]
	)
	for farmer in farmers:
		_measure(farmer)


func _tank_of(cell: Vector2i) -> float:
	var record: Dictionary = _manager.building_at_global(cell.x, cell.y)
	return 0.0 if record.is_empty() else _manager.house_water_at(record)


func _measure(farmer) -> void:
	var occupation: String = farmer.identity.occupation if farmer.identity != null else "?"
	var crop: String = farmer._field_crop
	var store_cell: Vector2i = farmer.stock_building_cell
	_report_lines.append("")
	_report_lines.append(
		"FARM WATER %s at %s, %d beds" % [occupation, str(store_cell), farmer.field_cells.size()]
	)
	if _tank_of(store_cell) <= 0.0:
		_report_lines.append("  no farmhouse tank here -- nothing to measure")
		return

	var elapsed := 0.0
	var drawn := 0.0
	var poured := 0.0
	var trips := 0
	var dry_ticks := 0
	var working_ticks := 0
	var peak_harvest := 0
	var last := _tank_of(store_cell)
	while elapsed < SIMULATED_SECONDS:
		farmer._process(SLICE)
		_manager.step_farm_plots(SLICE)
		elapsed += SLICE
		if farmer._on_real_field:
			working_ticks += 1
		var now := _tank_of(store_cell)
		if now < last:
			drawn += last - now
		elif now > last:
			poured += now - last
			trips += 1
		if not HouseholdWater.can_water_crops(now):
			dry_ticks += 1
		last = now
		if crop != "":
			peak_harvest = maxi(
				peak_harvest, _manager.structure_stock_at(store_cell.x, store_cell.y, crop)
			)

	var days := SIMULATED_SECONDS / SECONDS_PER_DAY
	var tendings := drawn / maxf(HouseholdWater.LITRES_PER_TENDING, 0.0001)
	_report_lines.append(
		"  tank %.1f -> %.1f over %.0fs (%.1f simulated days)" % [
			_tank_of(store_cell) + drawn - poured, _tank_of(store_cell), SIMULATED_SECONDS, days
		]
	)
	_report_lines.append(
		"  drew %.1f L in %.0f tendings -- %.1f tendings/day, %.1f L/day"
		% [drawn, tendings, tendings / days, drawn / days]
	)
	_report_lines.append(
		"  poured %.1f L in %d trips to the well -- one every %.1f days"
		% [poured, trips, days / float(maxi(trips, 1))]
	)
	_report_lines.append(
		"  %d/%d ticks with nothing to spare (the beds went unwatered)"
		% [dry_ticks, int(SIMULATED_SECONDS / SLICE)]
	)
	_report_lines.append(
		"  worked %d/%d ticks, farmhouse peak %d %s"
		% [working_ticks, int(SIMULATED_SECONDS / SLICE), peak_harvest, crop]
	)
