extends SceneTree

## Reported in play, with a screenshot: "There are still Farmhouses not
## connected by a street". This probe does not guess -- it opens real
## village chunks, finds every farmhouse actually standing, and asks
## whether its doorstep is reachable over PAVING from the village's own
## spine (the main street row the skeleton drew).
##
## Same SceneTree conventions as tools/probe_village_ghost.gd: everything
## runs in _process, every heavy script is load()ed at runtime.

const CHUNK_SIZE := 32
const LAT := 49.8
const LON := 10.6
const STEPS := 40

var _village_layout_script
var _village_farm
var _manager
var _origin: Vector2i
var _step := -1
var _seen: Dictionary = {}
var _checked := 0
var _with_farm := 0
var _disconnected := 0


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_village_layout_script = load("res://src/world/village_layout.gd")
	_village_farm = load("res://src/gameplay/village_farm.gd")
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
	if _step < STEPS:
		_manager.update(_origin + Vector2i((_step % 8) * CHUNK_SIZE, (_step / 8) * CHUNK_SIZE))
		for chunk_coord in _manager._loaded_villages.keys():
			if not _seen.has(chunk_coord):
				_seen[chunk_coord] = true
				_report(chunk_coord)
		_step += 1
		return false
	print("")
	print("village chunks met:     ", _seen.size())
	print("  of them with a farm:  ", _with_farm)
	print("farmhouses checked:     ", _checked)
	print("NOT on the road net:    ", _disconnected)
	return true


## Every cell of this chunk that is paved road right now.
func _road_cells(chunk_coord: Vector2i) -> Dictionary:
	var roads: Dictionary = {}
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if _manager.modification_at_global(g.x, g.y) == "road":
				roads[Vector2i(x, y)] = true
	return roads


## The paving reachable from the village spine, 4-connected.
func _reachable_from_spine(chunk_coord: Vector2i, roads: Dictionary) -> Dictionary:
	var bones: Dictionary = _village_layout_script.skeleton(
		CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord)
	)
	var frontier: Array = []
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		var cell := Vector2i(x, bones["street_y"])
		if roads.has(cell):
			frontier.append(cell)
	var seen: Dictionary = {}
	for cell in frontier:
		seen[cell] = true
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if roads.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen


func _report(chunk_coord: Vector2i) -> void:
	var farms: Array = []
	for record in _manager.buildings_in_chunk(chunk_coord):
		if record.get("id", "") == _village_farm.FARM_BUILDING_ID:
			farms.append(record)
	if farms.is_empty():
		print("== chunk ", chunk_coord, " : NO farmhouse (",
			_manager.buildings_in_chunk(chunk_coord).size(), " buildings)")
		return
	_with_farm += 1
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var roads := _road_cells(chunk_coord)
	var net := _reachable_from_spine(chunk_coord, roads)
	print("== chunk ", chunk_coord, " : ", farms.size(), " farmhouse(s), ",
		roads.size(), " road cells, ", net.size(), " of them on the spine net")
	for record in farms:
		var origin: Vector2i = record["origin_local"]
		var doorstep: Vector2i = origin + BuildingCatalog.doorstep_of(_village_farm.FARM_BUILDING_ID)
		var paved: bool = roads.has(doorstep)
		var linked: bool = net.has(doorstep)
		_checked += 1
		if not linked:
			_disconnected += 1
		# How much paving touches the doorstep at all: a lone paved cell in
		# open ground has zero neighbours and is the shape the report shows.
		var neighbours := 0
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if roads.has(doorstep + step):
				neighbours += 1
		print("   farmhouse at ", origin, " doorstep ", doorstep,
			" paved=", paved, " road-neighbours=", neighbours,
			" REACHES SPINE=", linked)
