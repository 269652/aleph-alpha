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
var _village_layout_script
var _village_layout
var _manager
var _origin: Vector2i
var _step := -1
var _seen := {}


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
		_seen[chunk_coord] = {
			"villagers": villagers,
			"dwellings": dwellings,
			"other": other,
			"water_frontage": _house_strip_water_fraction(chunk_coord),
			"plots_if_only_water_blocked": _plots_with_real_water(chunk_coord, villagers),
		}


## How much of the strip a house would actually stand on -- the rows just
## north of the main street, along its whole length -- the REAL load path
## calls water. is_water_at_global is much stricter than a chunk's biome
## array: it also counts a still-water hydrology probe and any cell within
## a river's half width plus RiverCatalog.RIVER_BANK_APRON_TILES.
func _house_strip_water_fraction(chunk_coord: Vector2i) -> float:
	var bones: Dictionary = _village_layout_script.skeleton(
		CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord)
	)
	var street_y: int = bones["street_y"]
	var total := 0
	var water := 0
	for x in range(bones["street_x0"], bones["street_x1"] + 1):
		for dy in range(1, 4):
			var y: int = street_y - dy
			if y < 0:
				continue
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			total += 1
			if _manager.is_water_at_global(g.x, g.y):
				water += 1
	return float(water) / float(total) if total > 0 else 0.0


## What VillageLayout would have produced on a FIRST load: the real water
## test, and nothing built yet. If this is 5 and no dwelling stands, the
## layout found room and something downstream refused it; if it is 0, the
## ground itself is what said no.
func _plots_with_real_water(chunk_coord: Vector2i, villager_count: int) -> int:
	var manager = _manager
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not manager.is_water_at_global(g.x, g.y)
	var never_occupied := func(_cell: Vector2i) -> bool: return false
	var building_ids: Array = []
	for i in villager_count:
		building_ids.append("house_small")
	var result: Dictionary = _village_layout.layout(
		building_ids, CHUNK_SIZE, _village_layout_script.seed_for(chunk_coord),
		is_buildable, never_occupied
	)
	return (result["plots"] as Array).size()


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
				"    chunk %s: %d villagers, 0 dwellings, %d other buildings, house strip %.0f%% water, layout would fit %d"
				% [
					str(coord), row["villagers"], row["other"],
					100.0 * float(row["water_frontage"]), int(row["plots_if_only_water_blocked"]),
				]
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
	print("  for comparison, the villages that DID build:")
	for coord in _seen:
		var row: Dictionary = _seen[coord]
		if row["dwellings"] > 0:
			print(
				"    chunk %s: %d dwellings, house strip %.0f%% water, layout would fit %d"
				% [
					str(coord), row["dwellings"], 100.0 * float(row["water_frontage"]),
					int(row["plots_if_only_water_blocked"]),
				]
			)
