extends SceneTree

## Why do two real villages stand with five villagers and NOT ONE
## dwelling? tools/probe_village_houses_live.gd measures the symptom
## (chunks (668,143) and (670,144) near lat 48.6 lon 12.7); this one opens
## those exact chunks and asks, in order, every question that could
## explain it:
##
##   - what buildings actually stand there, by id and origin
##   - how many villagers spawned
##   - what VillageLayout would return RIGHT NOW with the renderer's own
##     two predicates (water, and real chunk modifications)
##   - whether those plots' own cells were already modified, which is the
##     one thing EarthChunkManager.place_building refuses on
##
## Same SceneTree conventions as tools/probe_village_hunting.gd: everything
## runs in _process and every heavy script is load()ed at runtime.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 30
const TARGETS := [Vector2i(668, 143), Vector2i(670, 144)]

var _building_catalog
var _village_layout_script
var _village_layout
var _manager
var _origin: Vector2i
var _step := -1
var _reported := {}


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_building_catalog = load("res://src/gameplay/building_catalog.gd")
	_village_layout_script = load("res://src/world/village_layout.gd")
	_village_layout = _village_layout_script.new()
	var geo = GeoCoordinates.new()
	_origin = Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES)
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
	if _step < STEPS and _reported.size() < TARGETS.size():
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		for target in TARGETS:
			if not _reported.has(target) and _manager._loaded_villages.has(target):
				_report(target)
				_reported[target] = true
		_step += 1
		return false
	if _reported.size() < TARGETS.size():
		print("never met: ", TARGETS)
	return true


func _report(chunk_coord: Vector2i) -> void:
	print("== chunk ", chunk_coord, " ==")
	var villagers := 0
	for node in _manager._loaded_villages[chunk_coord]:
		if is_instance_valid(node) and node.has_method("setup_economy"):
			villagers += 1
	print("  villagers spawned:  ", villagers)
	var records: Array = _manager.buildings_in_chunk(chunk_coord)
	print("  buildings standing: ", records.size())
	for record in records:
		print("     ", record.get("id", "?"), " at ", record.get("origin_local", "?"),
			" capacity=", _building_catalog.capacity_of(record.get("id", "")))

	var manager = _manager
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not manager.is_water_at_global(g.x, g.y)
	var is_occupied := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return manager.modification_at_global(g.x, g.y) != ""
	var never_occupied := func(_cell: Vector2i) -> bool: return false
	var ids: Array = []
	for i in maxi(villagers, 5):
		ids.append("house_small")
	var now: Dictionary = _village_layout.layout(
		ids, CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord), is_buildable, is_occupied
	)
	var fresh: Dictionary = _village_layout.layout(
		ids, CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord), is_buildable, never_occupied
	)
	print("  layout NOW (water + real modifications): ", (now["plots"] as Array).size(), " plots")
	print("  layout FRESH (water only):               ", (fresh["plots"] as Array).size(), " plots")
	var bones: Dictionary = _village_layout_script.skeleton(
		CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord)
	)
	var street_y: int = bones["street_y"]
	var dry := 0
	var modified := 0
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, street_y)
		if not _manager.is_water_at_global(g.x, g.y):
			dry += 1
		if _manager.modification_at_global(g.x, g.y) != "":
			modified += 1
	print("  spine row: ", bones["street_x1"] - bones["street_x0"] + 1, " cells, ",
		dry, " dry, ", modified, " already modified")
	var plaza: Rect2i = bones["plaza"]
	var plaza_dry := 0
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			var g2: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if not _manager.is_water_at_global(g2.x, g2.y):
				plaza_dry += 1
	print("  plaza: ", plaza.size.x * plaza.size.y, " cells, ", plaza_dry, " dry")
