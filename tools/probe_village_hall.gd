extends SceneTree

## The reported village: lat 47.2 lon 15.1, a forest-edge hamlet whose City
## Hall never finishes and which shows no square.
##
## The first cut of this probe asked the skeleton with is_buildable_ground_at
## -- which vetoes FOREST -- while the game asks it with `not is_water_at_
## global`. On a forest-edge village those are different rectangles, so the
## numbers it printed described a square the game never lays. Fixed here:
## the predicate below is the game's own.

const CHUNK_SIZE := 32
const LAT := 47.2
const LON := 15.1
const SPAN := 3          # chunks either side of centre
const SETTLE_STEPS := 20 # let the settlement step run

var _manager
var _centre_tile: Vector2i
var _targets: Array = []
var _i := 0
var _settling := 0
var _done := false


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	_centre_tile = Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	var centre_chunk := Vector2i(_centre_tile.x / CHUNK_SIZE, _centre_tile.y / CHUNK_SIZE)
	for dy in range(-SPAN, SPAN + 1):
		for dx in range(-SPAN, SPAN + 1):
			_targets.append(centre_chunk + Vector2i(dx, dy))


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
		return false
	if _i < _targets.size():
		var c: Vector2i = _targets[_i]
		_manager.update(Vector2(c * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)))
		_i += 1
		return false
	if _settling < SETTLE_STEPS:
		_settling += 1
		return false
	if not _done:
		_done = true
		_report()
	return true


func _report() -> void:
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var VillageLayout = load("res://src/world/village_layout.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var EntityRef = load("res://src/emergence/entity_ref.gd")
	print("")
	print("CENTRE tile %s chunk %s" % [
		str(_centre_tile), str(Vector2i(_centre_tile.x / CHUNK_SIZE, _centre_tile.y / CHUNK_SIZE))
	])
	var found := 0
	for chunk_coord in _targets:
		var buildings: Array = _manager.buildings_in_chunk(chunk_coord)
		if buildings.is_empty():
			continue
		found += 1
		var ids: Dictionary = {}
		var covered: Dictionary = {}  # LOCAL cell -> building id standing on it
		for record in buildings:
			var id: String = record.get("id", "")
			ids[id] = int(ids.get(id, 0)) + 1
			var origin_local: Vector2i = (record.get("origin", Vector2i.ZERO) as Vector2i) - chunk_coord * CHUNK_SIZE
			for cell in BuildingCatalog.footprint_cells(id, origin_local):
				covered[cell] = id
		var settlement_id: String = EntityRef.for_settlement(chunk_coord)
		var households: int = _manager.household_count_for_settlement(settlement_id)
		# The game's own predicate: water, nothing else (VillageLayout's
		# `is_dry`, EarthChunkManager._is_dry_local, VillageRenderer._is_
		# buildable_local all ask exactly this).
		var is_dry := func(cell: Vector2i) -> bool:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			return not _manager.is_water_at_global(g.x, g.y)
		var bones: Dictionary = VillageLayout.skeleton(
			CHUNK_SIZE, VillageLayout.seed_for(chunk_coord), is_dry
		)
		var plaza: Rect2i = bones["plaza"]
		var paved := 0
		var pavable := 0
		var total := 0
		var blocked: Dictionary = {}   # what stopped each unpavable cell
		for y in range(plaza.position.y, plaza.end.y):
			for x in range(plaza.position.x, plaza.end.x):
				total += 1
				var cell := Vector2i(x, y)
				var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
				var existing: String = _manager.modification_at_global(g.x, g.y)
				if TerrainRenderer.is_road_tile(existing):
					paved += 1
					pavable += 1
					continue
				if not is_dry.call(cell):
					blocked["water"] = int(blocked.get("water", 0)) + 1
					continue
				if existing != "":
					var who: String = "%s(%s)" % [existing, covered.get(cell, "-")]
					blocked[who] = int(blocked.get(who, 0)) + 1
					continue
				pavable += 1
		var worth: bool = VillageLayout.plaza_is_worth_laying(pavable, total)
		# the seat's own plot
		var plot: Dictionary = bones["civic_plot"]
		var plot_cells: Array = BuildingCatalog.footprint_cells("city_hall", plot["origin"])
		plot_cells.append(plot["origin"] + BuildingCatalog.doorstep_of("city_hall"))
		var plot_detail: Array = []
		for local in plot_cells:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + (local as Vector2i)
			var mod: String = _manager.modification_at_global(g.x, g.y)
			var clear = _manager._house_site_cell_is_clear(chunk_coord, g, true)
			plot_detail.append("%s mod='%s' terrain=%s clear=%s%s" % [
				str(local), mod, str(_manager.is_buildable_terrain_at(g.x, g.y)), str(clear),
				("" if not covered.has(local) else " under=" + str(covered[local]))
			])
		var site_clear = _manager._civic_site_is_clear(chunk_coord, plot["origin"], "city_hall")
		var plot_origin_answer = _manager._civic_plot_origin_for(chunk_coord)
		# any live project?
		var projects: Array = _manager._construction_project_store.in_progress_projects_in_chunk(chunk_coord)
		var project_text := "none"
		for project in projects:
			project_text = "%s labour=%.1f/%.1f" % [
				project.blueprint_id, project.labor_hours_done, project.labor_hours_required
			]
		print("")
		print("VILLAGE %s households=%d  hall=%d  project=%s" % [
			str(chunk_coord), households, int(ids.get("city_hall", 0)), project_text
		])
		print("   PLAZA %s paved=%d/%d pavable=%d worth_laying=%s" % [
			str(plaza), paved, total, pavable, str(worth)
		])
		print("   blocked by: %s" % str(blocked))
		print("   CIVIC PLOT origin=%s site_clear=%s plot_origin_for=%s" % [
			str(plot["origin"]), str(site_clear), str(plot_origin_answer)
		])
		for line in plot_detail:
			print("      %s" % line)
		print("   buildings: %s" % str(ids))
		# Which buildings really stand ON the square, and were they stamped
		# at founding (a per-index seed) or raised later by the ladder?
		for record in buildings:
			var id: String = record.get("id", "")
			var origin_local: Vector2i = (record.get("origin", Vector2i.ZERO) as Vector2i) - chunk_coord * CHUNK_SIZE
			var on_plaza := false
			for cell in BuildingCatalog.footprint_cells(id, origin_local):
				if plaza.has_point(cell):
					on_plaza = true
			var stamped := -1
			for i in range(0, 40):
				if record.get("seed", -999) == hash("%d_%d_house_%d" % [chunk_coord.x, chunk_coord.y, i]):
					stamped = i
			print("      %s at %s on_plaza=%s founding_index=%d seed=%s" % [
				id, str(origin_local), str(on_plaza), stamped, str(record.get("seed", "-"))
			])
		# Would the FOUNDING layout have found this square clear on virgin
		# ground? (is_occupied = nothing modified, which is what founding saw.)
		var virgin_clear := true
		for y2 in range(plaza.position.y, plaza.end.y):
			for x2 in range(plaza.position.x, plaza.end.x):
				if not is_dry.call(Vector2i(x2, y2)):
					virgin_clear = false
		print("   plaza clear on virgin ground (water only): %s" % str(virgin_clear))
	print("")
	print("chunks with buildings: %d of %d swept" % [found, _targets.size()])
