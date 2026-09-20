extends SceneTree

## Four reports, measured on REAL villages before anything is changed:
##
##   "There are still villages without plaza."
##   "There are fenced enclosures without farmhouse."
##   "The warehouse shows 205 Wheat but the Villagers show 50% food."
##   "They have 0 Herbs even though there are 3 farm houses."
##
## Per this repo's probe-before-you-trust convention. Each village reports
## what it really has, and -- for a village missing its square -- WHY: which
## cells of the skeleton's own plaza rect are unbuildable or already carry
## something, since _lay_plaza_if_missing abandons the whole square on the
## first such cell it meets.
##
## Structural notes are probe_village_store_round.gd's (work in _process,
## load() at runtime, ask the manager for its own loaded villages).

const CHUNK_SIZE := 32
const STEPS := 14

var _manager
var _origin: Vector2i
var _step := -1
var _seen: Dictionary = {}
var _villages := 0
var _without_plaza := 0
var _stray_rails := 0
var _item_catalog
var _VillageLayout
var _VillageFarm
var _TerrainRenderer


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
		_item_catalog = load("res://src/gameplay/item_catalog.gd").new()
		_VillageLayout = load("res://src/world/village_layout.gd")
		_VillageFarm = load("res://src/gameplay/village_farm.gd")
		_TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
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
		_survey()
		_step += 1
		return false

	print("")
	print("== TOTALS over %d villages ==" % _villages)
	print("  without a plaza : %d" % _without_plaza)
	print("  stray rails     : %d" % _stray_rails)
	return true


## Printed immediately rather than banked: a survey that only speaks at the
## end tells you nothing while it runs, and a village founding is slow.
func _say(line: String) -> void:
	print(line)


func _survey() -> void:
	for chunk_coord in _manager._loaded_villages.keys():
		if _seen.has(chunk_coord):
			continue
		_seen[chunk_coord] = true
		_villages += 1
		_report(chunk_coord)


func _report(chunk_coord: Vector2i) -> void:
	_say("")
	_say("== village at chunk %s ==" % str(chunk_coord))
	_report_plaza(chunk_coord)
	_report_rails(chunk_coord)
	_report_stores(chunk_coord)


## Is the skeleton's own plaza rect really paved, and if not, what stopped
## it? _lay_plaza_if_missing walks the rect and returns on the first cell
## that is unbuildable or already carries a non-road modification -- so one
## bad cell costs the whole square.
func _report_plaza(chunk_coord: Vector2i) -> void:
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not _manager.is_water_at_global(g.x, g.y)
	var skeleton: Dictionary = _VillageLayout.skeleton(
		CHUNK_SIZE, _VillageLayout.seed_for(chunk_coord), is_buildable
	)
	var plaza: Rect2i = skeleton["plaza"]
	var paved := 0
	var occupied := 0
	var total := 0
	var blockers: Array = []
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			total += 1
			var cell := Vector2i(x, y)
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			var existing: String = _manager.modification_at_global(g.x, g.y)
			if _TerrainRenderer.is_road_tile(existing):
				paved += 1
				continue
			# A building standing in the square is EXPECTED now: the square
			# is laid around what stands in it (VillageLayout.
			# plaza_is_worth_laying). Only a bare or wet cell is a real gap
			# -- counting a hall's own footprint as one is how the first
			# version of this probe called a perfectly good square
			# incomplete.
			if existing != "":
				occupied += 1
				continue
			if not is_buildable.call(cell):
				blockers.append("%s water" % str(cell))
			else:
				blockers.append("%s BARE" % str(cell))
	if paved + occupied < total:
		_without_plaza += 1
	_say("  PLAZA %d/%d paved, %d built on, %d bare%s" % [
		paved, total, occupied, total - paved - occupied,
		"" if paved + occupied == total else "   <-- GAPS"
	])
	if not blockers.is_empty():
		_say("    blocked by: %s" % ", ".join(blockers.slice(0, 8)))


## Every rail standing in the chunk, against every farmhouse standing in it.
func _report_rails(chunk_coord: Vector2i) -> void:
	var farmhouses := 0
	for record in _manager.buildings_in_chunk(chunk_coord):
		if String(record.get("id", "")) == _VillageFarm.FARM_BUILDING_ID:
			farmhouses += 1
	var rails := 0
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if _VillageFarm.is_fence_tile(_manager.modification_at_global(g.x, g.y)):
				rails += 1
	var stray := rails > 0 and farmhouses == 0
	if stray:
		_stray_rails += rails
	_say("  FARM  %d farmhouse(s), %d rail(s)%s" % [
		farmhouses, rails, "   <-- RAILS WITH NO FARMHOUSE" if stray else ""
	])


## What the village's own structures really hold, split by whether the item
## is ItemCatalog kind "food" -- the exact filter SettlementFood applies
## before anybody counts as fed.
func _report_stores(chunk_coord: Vector2i) -> void:
	var food: Dictionary = {}
	var not_food: Dictionary = {}
	for record in _manager.buildings_in_chunk(chunk_coord):
		var origin: Vector2i = record.get("origin_local", Vector2i.ZERO)
		var g: Vector2i = chunk_coord * CHUNK_SIZE + origin
		for item_id in _manager.building_inventory_at(g.x, g.y):
			var count: int = int(_manager.building_inventory_at(g.x, g.y)[item_id])
			if count <= 0:
				continue
			var into := food if _item_catalog.kind_of(item_id) == "food" else not_food
			into[item_id] = int(into.get(item_id, 0)) + count
	_say("  STORE food=%s" % ("(nothing edible)" if food.is_empty() else str(food)))
	_say("        other=%s" % ("(empty)" if not_food.is_empty() else str(not_food)))
