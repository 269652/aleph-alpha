extends SceneTree

## Reported live with the warehouse readout open at "Stored: 0 / 240":
## *"The porter is moving products (beams, logs) from the sawmill to the
## warehouse but unloading doesn't put anything into warehouse.. storage is
## still 0 and goods just vanish"*.
##
## Measures that against a REAL village: who walks the store's round, which
## store and which producers they were given, what is on each shelf, what
## ends up on the wagon, and -- the part the report is actually about -- what
## the WAREHOUSE READOUT holds at the end (building_inventory_at, which is
## the exact call the popover draws from, not the tile-keyed stock the
## carter's own tests assert against).
##
## Structural notes are probe_village_hunting.gd's (work in _process, load()
## at runtime, ask the manager for its own loaded villages).

const CHUNK_SIZE := 32
const STEPS := 40
const SIMULATED_SECONDS := 600.0
const SLICE := 0.1

## Seeded onto each producer's shelf before the run, so the round has
## something to carry whatever the producers themselves managed to make.
const SEEDED_BEAMS := 12

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
		print("ROUND no villager with a store round was ever met in %d chunk-widths" % STEPS)
	return true


func _carters_in() -> Array:
	var found: Array = []
	for chunk_coord in _manager._loaded_villages:
		for node in _manager._loaded_villages[chunk_coord]:
			if not is_instance_valid(node) or not ("store_cell" in node):
				continue
			if not ("producer_cells" in node) or node.producer_cells.is_empty():
				continue
			if node.store_cell == Vector2i(-2147483648, -2147483648):
				continue
			found.append(node)
	return found


func _sample() -> void:
	if _measured:
		return
	var carters := _carters_in()
	if carters.is_empty():
		return
	_measured = true
	for carter in carters:
		_measure(carter)


func _measure(carter) -> void:
	var occupation: String = carter.identity.occupation if carter.identity != null else "?"
	var store: Vector2i = carter.store_cell
	_report_lines.append("")
	_report_lines.append(
		"CARTER occupation=%s store=%s producers=%d cart=%s"
		% [occupation, str(store), carter.producer_cells.size(), str(carter.cart != null)]
	)
	var record: Dictionary = _manager.building_at_global(store.x, store.y)
	_report_lines.append(
		"  the store tile holds building=%s origin_local=%s"
		% [str(record.get("id", "<none>")), str(record.get("origin_local", "?"))]
	)
	for cell in carter.producer_cells:
		var producer: Dictionary = _manager.building_at_global(cell.x, cell.y)
		_manager.deposit_to_structure_at(cell.x, cell.y, "beam", SEEDED_BEAMS)
		_report_lines.append(
			"  producer %s is a %s holding %s"
			% [str(cell), str(producer.get("id", "<none>")), str(_manager.structure_stock_contents_at(cell.x, cell.y))]
		)

	var elapsed := 0.0
	var round_ticks := 0
	var deliveries := 0
	var before_readout: int = _total(_manager.building_inventory_at(store.x, store.y))
	while elapsed < SIMULATED_SECONDS:
		var before: int = _total(_manager.building_inventory_at(store.x, store.y))
		carter._process(SLICE)
		if carter.cart != null and is_instance_valid(carter.cart):
			carter.cart._process(SLICE)
		elapsed += SLICE
		if carter._on_real_round:
			round_ticks += 1
		if _total(_manager.building_inventory_at(store.x, store.y)) > before:
			deliveries += 1

	_report_lines.append(
		"  walked the round %d/%d ticks over %ds"
		% [round_ticks, int(SIMULATED_SECONDS / SLICE), int(SIMULATED_SECONDS)]
	)
	_report_lines.append("  %d separate deliveries arrived" % deliveries)
	for cell in carter.producer_cells:
		_report_lines.append(
			"  producer %s left holding %s" % [str(cell), str(_manager.structure_stock_contents_at(cell.x, cell.y))]
		)
	if carter.cart != null and is_instance_valid(carter.cart):
		_report_lines.append("  still on the wagon: %s" % str(carter.cart.stock))
	_report_lines.append(
		"  WAREHOUSE READOUT was %d, is now %s (room left %d)"
		% [
			before_readout,
			str(_manager.building_inventory_at(store.x, store.y)),
			_manager.building_room_at(store.x, store.y),
		]
	)


func _total(contents: Dictionary) -> int:
	var sum := 0
	for key in contents:
		sum += int(contents[key])
	return sum
