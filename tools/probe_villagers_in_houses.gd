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

	# Making a whole footprint solid can only hurt one way: a villager whose
	# TARGET sits on a building cell can no longer arrive, and would stand
	# there for good. So movement is measured beside trespass -- a fix that
	# freezes half the village is not a fix.
	var frozen := 0
	# "Still moving at the end" separates the two things a shorter total
	# distance can mean: a villager who ROUTES AROUND a house spends some
	# frames standing while the route is replanned but is still walking at
	# the end of the run, while one WEDGED against a wall it cannot get
	# round stops and never starts again.
	var stalled_at_end := 0
	var stalled_touching_a_house := 0
	var standing_frames := 0
	var travelled := 0.0
	var targets_on_a_building := 0
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
		var start: Vector2 = villager.position
		var walked := 0.0
		var previous: Vector2 = villager.position
		var tail := 0.0
		var workspot = villager.workspot_position if villager.has_method("workspot_position") else null
		if workspot != null:
			var wcell := Vector2i(floori(workspot.x / TILE), floori(workspot.y / TILE))
			if _manager.has_building_at_global(wcell.x, wcell.y):
				targets_on_a_building += 1
		for frame in FRAMES:
			villager._process(SLICE)
			var stepped := previous.distance_to(villager.position)
			walked += stepped
			if stepped < 0.01:
				standing_frames += 1
			if frame >= FRAMES - 90:
				tail += stepped
			previous = villager.position
			var cell := _cell_of(villager)
			total_frames += 1
			if not _manager.has_building_at_global(cell.x, cell.y):
				continue
			mine += 1
			inside_frames += 1
			if _manager.piece_blocks_movement_at_global(cell.x, cell.y):
				pieces_agreeing += 1
		travelled += walked
		if walked < 1.0:
			frozen += 1
		if tail < 1.0:
			stalled_at_end += 1
			# Wedged, or simply idle? A villager that stops with a house in
			# a neighbouring cell is the one worth worrying about; one that
			# stops in open ground is doing what villagers do between jobs,
			# and does it in the baseline run too.
			var cell := _cell_of(villager)
			var touching := false
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cell + offset
				if _manager.has_building_at_global(n.x, n.y):
					touching = true
			if touching:
				stalled_touching_a_house += 1
				# A doorstep TOUCHES its house by construction
				# (BuildingCatalog.doorstep_of), so a villager who got home
				# and is idling there looks exactly like one pressed
				# against a wall -- until you ask which it is.
				# Wedged means EVERY way out is refused. Asked directly
				# rather than inferred from "it stopped moving": a villager
				# waiting on a schedule and one pressed into a corner both
				# stand still, and only one of them is a bug.
				var open_ways := 0
				var step := 1.5  # roughly one frame of walking
				for offset in [
					Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
					Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
				]:
					var to: Vector2 = villager.position + offset.normalized() * step
					if villager._slid_along_walls(villager.position, to) != villager.position:
						open_ways += 1
				_lines.append(
					"    stopped by a house: %s, at_home=%s, tag=%s, route=%d, ways out=%d/8"
					% [
						str(villager.identity.occupation) if villager.identity != null else "?",
						str(villager._at_home),
						str(villager.current_location_tag()),
						villager._route.size() if "_route" in villager else -1,
						open_ways,
					]
				)
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
	_lines.append("  villagers that never moved at all: %d / %d" % [frozen, villagers.size()])
	_lines.append("  mean distance walked            : %.0f px" % (travelled / float(villagers.size())))
	_lines.append("  workspots sitting on a building : %d" % targets_on_a_building)
	_lines.append("  still walking in the last 90 fr : %d / %d" % [
		villagers.size() - stalled_at_end, villagers.size()
	])
	_lines.append("  ...of those, stopped touching a house: %d" % stalled_touching_a_house)
	_lines.append("  frames spent standing still     : %d / %d (%.1f%%)" % [
		standing_frames, total_frames, 100.0 * float(standing_frames) / maxf(1.0, float(total_frames))
	])
