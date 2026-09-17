extends SceneTree

## The live half of tools/probe_village_houses.gd. That one measures
## VillageLayout alone and finds every village placing every house; this
## one runs the REAL EarthChunkManager load path -- the one that reported
## "Some villages have no houses" from a real screenshot -- and counts the
## houses that actually end up standing.
##
## Reports, per real settlement chunk: how many houses the village wanted,
## how many buildings of any kind stand, and how many of those are real
## dwellings (BuildingCatalog.capacity_of > 0). A village with roads, a
## sawmill and a hall but no dwellings is exactly the reported bug.
##
## Runs in _process, not _init/_initialize: see
## tools/probe_village_hunting.gd's doc comment -- a SceneTree script's
## children never get _ready() before the main loop starts, and everything
## heavy is load()ed at runtime because a -s script compiles before the
## project's autoloads register.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
## Chunk-widths walked. Settlements are sparse, so this is sized to meet
## several rather than to be exhaustive.
const STEPS := 30

var _building_catalog
var _manager
var _origin: Vector2i
var _step := -1
var _seen := {}


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	_building_catalog = load("res://src/gameplay/building_catalog.gd")
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
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_sample()
		_step += 1
		return false
	_report()
	return true


func _sample() -> void:
	for chunk_coord in _manager._loaded_villages:
		if _seen.has(chunk_coord):
			continue
		var villagers := 0
		for node in _manager._loaded_villages[chunk_coord]:
			if is_instance_valid(node) and node.has_method("setup_economy"):
				villagers += 1
		if villagers == 0:
			continue
		var dwellings := 0
		var other := 0
		for record in _manager.buildings_in_chunk(chunk_coord):
			if _building_catalog.capacity_of(record["id"]) > 0:
				dwellings += 1
			else:
				other += 1
		_seen[chunk_coord] = {"villagers": villagers, "dwellings": dwellings, "other": other}


func _report() -> void:
	var houseless := 0
	var dwelling_counts: Array = []
	var houseless_detail: Array = []
	for coord in _seen:
		var row: Dictionary = _seen[coord]
		dwelling_counts.append(row["dwellings"])
		if row["dwellings"] == 0:
			houseless += 1
			houseless_detail.append(
				"    chunk %s: %d villagers, 0 dwellings, %d other buildings"
				% [str(coord), row["villagers"], row["other"]]
			)
	print("-- real villages actually loaded near lat %.1f lon %.1f --" % [LAT, LON])
	print("villages met:                            %d" % _seen.size())
	if _seen.is_empty():
		return
	print(
		"villages with NO dwelling at all:        %d (%.1f%%)"
		% [houseless, 100.0 * float(houseless) / float(_seen.size())]
	)
	dwelling_counts.sort()
	print(
		"dwellings per village:                   min %d  median %d  max %d"
		% [
			dwelling_counts[0],
			dwelling_counts[dwelling_counts.size() / 2],
			dwelling_counts[dwelling_counts.size() - 1],
		]
	)
	for line in houseless_detail:
		print(line)
