extends SceneTree

## Does a building end up where its construction site stood?
##
## Reported live: *"The construction phase places the cottage at a different
## position than the finished cottage ... please align it so it doesn't jump
## that much"*.
##
## The art was measured first and is not the answer: every stage and the
## finished sheet are bottom-anchored on the plot line and centred on it
## (tools/probe_construction_alignment.gd -- content bottom 0.0 for all of
## them, 21x21 world units against 21x22). So this asks the other half, in a
## REAL village over REAL simulated time: where the site node stands while a
## project runs, and where the building node stands once it completes.
##
## Anything that moves between those two is the jump.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 30
const TICK_SECONDS := 60.0
const TICKS := 400
const LABOUR_PER_TICK := 4.0
const BUILDING_ID := "house_small"
const ConstructionLabor = preload("res://src/emergence/construction_labor.gd")

var _manager
var _origin: Vector2i
var _step := 0
var _chunk: Vector2i
var _ticked := 0
var _sites: Dictionary = {}   # "chunk|origin" -> {id, node_pos, seen}
var _started: Array = []
var _finished := 0
var _done := false


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES) / CHUNK_SIZE,
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES) / CHUNK_SIZE
	)


func _process(_delta: float) -> bool:
	if _manager == null:
		var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
		var tml := TileMapLayer.new()
		var ents := Node2D.new()
		var crts := Node2D.new()
		root.add_child(tml)
		root.add_child(ents)
		root.add_child(crts)
		_manager = EarthChunkManager.new(tml, ents, crts)
		print("")
		print("=== does a building land where its site stood? ===")
		return false
	if _step < STEPS:
		var c: Vector2i = _origin + Vector2i(_step, 0)
		_manager.update(Vector2(c * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)))
		_step += 1
		return false
	if _started.is_empty():
		_start_real_projects()
		return false
	if _ticked < TICKS and _finished < _started.size():
		_ticked += 1
		_manager.advance_world_age(TICK_SECONDS)
		_manager.step_settlements(TICK_SECONDS)
		# The village here has two households and starts nothing of its own,
		# so the projects are started above and driven by hand -- the real
		# ones, through the real store and the real site/worker sync.
		for entry in _started:
			var project = _project_at(entry["chunk"], entry["origin"])
			if project == null:
				continue
			project.labor_hours_accumulated += LABOUR_PER_TICK
			_manager._sync_construction_site(entry["chunk"], project)
			# Recorded BEFORE the completion check: a project that finishes
			# this same tick frees its site node, and a probe that looked
			# afterwards would report "no site was ever drawn" about its own
			# ordering.
			_record_sites()
			var required: float = ConstructionLabor.labor_hours_required(
				String(project.blueprint_id), _manager._recipe_book
			)
			if project.labor_hours_accumulated >= required:
				print("   completed at tick %d (required %.1f hours)" % [_ticked, required])
				_manager._place_completed_building_project(project)
				_manager.construction_project_store().complete_project(
					project.id, _manager._household_store
				)
				_finished += 1
		return false
	if not _done:
		_done = true
		_report()
	return true


## A real project on real clear ground in every loaded settlement chunk.
func _start_real_projects() -> void:
	var store = _manager.construction_project_store()
	for chunk_coord in _manager._loaded_chunks.keys():
		if _manager.buildings_in_chunk(chunk_coord).is_empty():
			continue
		var origin = _manager._settlement_build_origin_for(chunk_coord)
		if origin == null:
			continue
		var project = store.start_project(chunk_coord, origin, BUILDING_ID, "")
		if project == null:
			continue
		_started.append({"chunk": chunk_coord, "origin": origin})
		print("   started %s at %s in %s" % [BUILDING_ID, str(origin), str(chunk_coord)])
	if _started.is_empty():
		_started.append({"chunk": Vector2i.ZERO, "origin": Vector2i.ZERO})  # nothing to do


## Every construction site standing right now, and where its node sits.
func _record_sites() -> void:
	for chunk_coord in _manager._construction_site_nodes:
		var by_origin: Dictionary = _manager._construction_site_nodes[chunk_coord]
		for origin_local in by_origin:
			var node = by_origin[origin_local]
			if node == null or not is_instance_valid(node):
				continue
			var key := "%s|%s" % [str(chunk_coord), str(origin_local)]
			var project = _project_at(chunk_coord, origin_local)
			_sites[key] = {
				"chunk": chunk_coord, "origin": origin_local,
				"id": "" if project == null else String(project.blueprint_id),
				"node_pos": node.position,
				"tick": _ticked,
			}


## A project at this origin, in progress or merely planned -- a project
## waiting on its material is still a site that will be drawn, and looking
## only at in-progress ones made this probe report "no site was ever drawn"
## about its own query.
func _project_at(chunk_coord: Vector2i, origin_local: Vector2i):
	var store = _manager.construction_project_store()
	for project in store.active_projects_in_chunk(chunk_coord):
		if project.origin == origin_local:
			return project
	for project in store.in_progress_projects_in_chunk(chunk_coord):
		if project.origin == origin_local:
			return project
	return null


func _report() -> void:
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	print("")
	print("sites seen while building: %d" % _sites.size())
	var matched := 0
	var moved := 0
	for key in _sites:
		var site: Dictionary = _sites[key]
		var chunk_coord: Vector2i = site["chunk"]
		var origin_local: Vector2i = site["origin"]
		var standing := ""
		var standing_origin := Vector2i(-999, -999)
		for record in _manager.buildings_in_chunk(chunk_coord):
			if record.get("origin_local", Vector2i.ZERO) == origin_local:
				standing = String(record.get("id", ""))
				standing_origin = origin_local
		if standing == "":
			print("   site %s (%s, last seen tick %d): nothing standing there yet" % [
				key, site["id"], site["tick"]
			])
			continue
		# Where the finished node really is, the same formula both spawners use.
		var footprint: Vector2i = BuildingCatalog.footprint_of(standing)
		var footprint_px: Vector2 = Vector2(footprint) * float(TerrainRenderer.TILE_SIZE)
		var top_left_px: Vector2 = Vector2(chunk_coord * CHUNK_SIZE + standing_origin) * float(TerrainRenderer.TILE_SIZE)
		var finished_pos: Vector2 = top_left_px + Vector2(footprint_px.x * 0.5, footprint_px.y)
		var delta: Vector2 = finished_pos - (site["node_pos"] as Vector2)
		if delta.length() > 0.01:
			moved += 1
			print("   site %s: %s site at %s -> %s stands at %s   MOVED %s (%.1f world px)" % [
				key, site["id"], str(site["node_pos"]), standing, str(finished_pos),
				str(delta), delta.length()
			])
		else:
			matched += 1
	print("")
	print("sites whose building landed exactly where the site stood: %d" % matched)
	print("sites whose building MOVED: %d" % moved)
