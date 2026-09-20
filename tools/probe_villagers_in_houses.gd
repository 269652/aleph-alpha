extends SceneTree

## Do real villagers, in a real village, stand INSIDE a house?
##
## Reported twice -- "Creatures and NPCs also walk through houses", then,
## after every marker had grown a gate, **"NPCs still walk through houses
## and ignore the hitbox"**. The second report is why this exists: the gate
## was there and the bug was not in it, so the thing to measure is what the
## gate is actually ASKED about a real house.
##
## Reports, per villager met:
##   - whether its `_world` is set at all (a marker built with `world ==
##     null` silently never gates);
##   - whether its wall predicate is a valid Callable;
##   - how many of N simulated frames it spent standing on a cell the world
##     calls a building (`has_building_at_global`), and the worst offender.
##
## And, as the control that makes those numbers mean something, what the
## OLD question would have said about the same cells
## (`piece_blocks_movement_at_global`) -- because a village house is a
## whole-building entity with no BuildingPiece walls in it at all.
##
## Usage: godot --headless -s tools/probe_villagers_in_houses.gd

const CHUNK_SIZE := 32
const STEPS := 40
const FRAMES := 900
const SLICE := 0.05
const TILE := 16

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
		_sample()
		_step += 1
		return false

	for line in _lines:
		print(line)
	if _lines.is_empty():
		print("HOUSE GATE no villager was met in %d chunk-widths" % STEPS)
	return true


func _villagers() -> Array:
	var found: Array = []
	for chunk_coord in _manager._loaded_villages:
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.has_method("setup_economy"):
				found.append(node)
	return found


func _cell_of(node) -> Vector2i:
	return Vector2i(floori(node.position.x / TILE), floori(node.position.y / TILE))


func _houses_loaded() -> int:
	var total := 0
	for chunk_coord in _manager._loaded_chunks:
		total += _manager.buildings_in_chunk(chunk_coord).size()
	return total


func _sample() -> void:
	if _done:
		return
	var villagers := _villagers()
	var houses := _houses_loaded()
	if villagers.size() < 3 or houses < 2:
		return
	_done = true
	_lines.append(
		"HOUSE GATE %d villagers, %d buildings loaded, %d frames of %.2fs each"
		% [villagers.size(), houses, FRAMES, SLICE]
	)

	var no_world := 0
	var no_predicate := 0
	for villager in villagers:
		if villager._world == null:
			no_world += 1
		elif not villager._wall_tiles.is_valid():
			no_predicate += 1
	_lines.append("  markers with no world at all : %d" % no_world)
	_lines.append("  markers with no wall predicate: %d" % no_predicate)

	var inside_frames := 0
	var total_frames := 0
	var worst_name := ""
	var worst := 0
	var ever_inside := 0
	# Of the cells a villager stood on and the world called a building, how
	# many the OLD question would also have refused. Expected: none -- a
	# house entity has no pieces -- which is the whole diagnosis.
	var pieces_agreeing := 0
	for villager in villagers:
		var mine := 0
		for frame in FRAMES:
			villager._process(SLICE)
			var cell := _cell_of(villager)
			total_frames += 1
			if not _manager.has_building_at_global(cell.x, cell.y):
				continue
			mine += 1
			inside_frames += 1
			if _manager.piece_blocks_movement_at_global(cell.x, cell.y):
				pieces_agreeing += 1
		if mine > 0:
			ever_inside += 1
		if mine > worst:
			worst = mine
			worst_name = str(villager.identity.occupation) if villager.identity != null else "?"

	_lines.append(
		"  frames standing inside a building: %d / %d (%.2f%%)"
		% [inside_frames, total_frames, 100.0 * float(inside_frames) / maxf(1.0, float(total_frames))]
	)
	_lines.append("  villagers that were ever inside : %d / %d" % [ever_inside, villagers.size()])
	_lines.append("  worst offender                  : %s, %d frames" % [worst_name, worst])
	_lines.append(
		"  ...of which the PIECE question would also have refused: %d" % pieces_agreeing
	)
