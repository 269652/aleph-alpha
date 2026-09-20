extends SceneTree

## WHERE a village puts the things a player looks for -- reported live with
## a screenshot of a plaza, a city hall, two cottages and a fenced pond:
## *"not a single Farmhouse even though there's plenty of space"*.
##
## "Not a single one" and "none in this picture" are different claims, and
## only a measurement tells them apart: a farmhouse is sited on a street
## plot that has room for a 3x2 FIELD beside it (VillageLayout's
## accepts_origin), which is a condition the centre of a village never
## meets. So this prints, per village, every building's distance from the
## plaza's own middle -- the point a screenshot centred on the square is
## centred on.
##
## Jumps straight at named chunks rather than streaming a transect: one
## village founding is slow, and this question is about ONE village's
## layout rather than about how many villages have the fault.
##
## Structural notes are probe_village_supply.gd's.

const CHUNK_SIZE := 32
## The chunks tools/probe_pond_and_farmhouse.gd found real, stamped
## villages in on the Berlin transect -- named here so this probe founds
## two villages instead of twenty-six.
const VILLAGE_CHUNKS: Array[Vector2i] = [Vector2i(678, 128), Vector2i(682, 132), Vector2i(696, 128)]

var _manager
var _step := -1
var _VillageLayout
var _VillageFarm
var _VillagePond
var _BuildingCatalog
var _TerrainRenderer


func _process(_delta: float) -> bool:
	if _step < 0:
		_VillageLayout = load("res://src/world/village_layout.gd")
		_VillageFarm = load("res://src/gameplay/village_farm.gd")
		_VillagePond = load("res://src/gameplay/village_pond.gd")
		_BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
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

	if _step < VILLAGE_CHUNKS.size():
		var chunk_coord: Vector2i = VILLAGE_CHUNKS[_step]
		_manager.update(chunk_coord * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2))
		_report(chunk_coord)
		_step += 1
		return false
	return true


func _report(chunk_coord: Vector2i) -> void:
	print("")
	print("== village at chunk %s ==" % str(chunk_coord))
	var records: Array = _manager.buildings_in_chunk(chunk_coord)
	if records.is_empty():
		print("  nothing stamped here")
		return
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return not _manager.is_water_at_global(g.x, g.y)
	var skeleton: Dictionary = _VillageLayout.skeleton(
		CHUNK_SIZE, _VillageLayout.seed_for(chunk_coord), is_buildable
	)
	var plaza: Rect2i = skeleton["plaza"]
	var middle := Vector2(plaza.position) + Vector2(plaza.size) * 0.5
	print("  plaza %s, middle at local %s, street row %d" % [
		str(plaza), str(middle), int(skeleton["street_y"])
	])
	var rows: Array = []
	for record in records:
		var origin: Vector2i = record.get("origin_local", Vector2i.ZERO)
		var id := String(record.get("id", ""))
		var footprint: Vector2i = _BuildingCatalog.footprint_of(id)
		var centre := Vector2(origin) + Vector2(footprint) * 0.5
		rows.append({
			"id": id, "origin": origin, "distance": middle.distance_to(centre),
			"occupation": String(record.get("occupation", "")),
		})
	rows.sort_custom(func(a, b): return float(a["distance"]) < float(b["distance"]))
	for row in rows:
		print("    %6.1f tiles  %-12s at %s%s" % [
			row["distance"], row["id"], str(row["origin"]),
			"" if row["occupation"] == "" else "   (%s)" % row["occupation"],
		])
	# A screenshot is a WINDOW, not a village. The player's own camera sees
	# roughly this many tiles across at the zoom the report was taken at,
	# so anything further from the square than half of it simply is not in
	# the picture the report is about.
	_report_hut_sites(chunk_coord)
	for half_window in [8, 12, 16]:
		var inside: Dictionary = {}
		for row in rows:
			if float(row["distance"]) <= float(half_window):
				inside[row["id"]] = int(inside.get(row["id"], 0)) + 1
		print("  within %2d tiles of the square: %s" % [half_window, str(inside)])


## Why the pond in this chunk has no hut on its bank, where it has none --
## measured by walking the SAME candidate grid VillagePond.hut_origin
## walks and naming what refused each cell, rather than by reading the
## function and guessing. Two of six real ponds came back with no hut at
## all (tools/probe_pond_and_farmhouse.gd), and "no bank clear enough to
## build on" is a different bug from "the search cannot reach the bank".
func _report_hut_sites(chunk_coord: Vector2i) -> void:
	var water: Array = []
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + Vector2i(x, y)
			if _VillagePond.is_pond_tile(_manager.modification_at_global(g.x, g.y)):
				water.append(Vector2i(x, y))
	if water.is_empty():
		print("  HUT SITES: no pond in this chunk")
		return
	var footprint: Vector2i = _BuildingCatalog.footprint_of(_VillagePond.HUT_BUILDING_ID)
	var doorstep: Vector2i = _BuildingCatalog.doorstep_of(_VillagePond.HUT_BUILDING_ID)
	var low: Vector2i = water[0]
	var high: Vector2i = low
	for cell in water:
		low = Vector2i(mini(low.x, (cell as Vector2i).x), mini(low.y, (cell as Vector2i).y))
		high = Vector2i(maxi(high.x, (cell as Vector2i).x), maxi(high.y, (cell as Vector2i).y))
	print("  HUT SITES: pond %s..%s, hut %s, doorstep offset %s, reach %d" % [
		str(low), str(high), str(footprint), str(doorstep), _VillagePond.HUT_BANK_REACH_TILES
	])
	var margin: int = _VillagePond.HUT_BANK_REACH_TILES + maxi(footprint.x, footprint.y)
	var in_reach := 0
	var reasons: Dictionary = {}
	var examples: Dictionary = {}
	for y in range(low.y - margin, high.y + margin + 1):
		for x in range(low.x - margin, high.x + margin + 1):
			var origin := Vector2i(x, y)
			var nearest := INF
			for cell in _BuildingCatalog.footprint_cells(_VillagePond.HUT_BUILDING_ID, origin):
				for wet in water:
					nearest = minf(
						nearest, Vector2(cell as Vector2i).distance_to(Vector2(wet as Vector2i))
					)
			if nearest > float(_VillagePond.HUT_BANK_REACH_TILES):
				continue
			in_reach += 1
			var why := _why_refused(chunk_coord, origin, footprint, doorstep, water)
			reasons[why] = int(reasons.get(why, 0)) + 1
			if not examples.has(why):
				examples[why] = origin
	print("    %d candidate origin(s) in reach of the water" % in_reach)
	for why in reasons:
		print("      %-34s x%d   e.g. %s" % [why, reasons[why], str(examples[why])])
	# And the counterfactual the fix turns on: the fence goes in with the
	# water and the hut goes up afterwards, so every site on the ring is
	# lost to a rail. Raising the hut FIRST would let the frame go round it
	# the way it already goes round a farmhouse -- so the number that
	# matters is how many candidates ONLY the rails refuse.
	var only_rails := 0
	var example_cell = null
	for why in reasons:
		if String(why) == "the pond\'s own fence rail":
			only_rails = int(reasons[why])
			example_cell = examples[why]
	print("    %d of them are refused by the pond\'s own rails ALONE%s" % [
		only_rails, "" if example_cell == null else "   e.g. %s" % str(example_cell)
	])


## The FIRST thing that refuses a hut at this origin, named -- "free" when
## nothing does.
func _why_refused(
	chunk_coord: Vector2i, origin: Vector2i, footprint: Vector2i, doorstep: Vector2i, water: Array
) -> String:
	var taken: Array = _BuildingCatalog.footprint_cells(_VillagePond.HUT_BUILDING_ID, origin)
	taken.append(origin + doorstep)
	for cell in taken:
		var local: Vector2i = cell
		if water.has(local):
			return "stands in its own water"
		if local.x < 0 or local.y < 0 or local.x >= CHUNK_SIZE or local.y >= CHUNK_SIZE:
			return "off the chunk"
		var g: Vector2i = chunk_coord * CHUNK_SIZE + local
		if _manager.is_water_at_global(g.x, g.y):
			return "other water"
		if not _manager.is_buildable_terrain_at(g.x, g.y):
			return "unbuildable ground"
		var existing: String = _manager.modification_at_global(g.x, g.y)
		if _VillageFarm.is_fence_tile(existing):
			return "the pond's own fence rail"
		if _TerrainRenderer.is_road_tile(existing):
			return "the village street"
		if existing != "":
			return "occupied: %s" % existing
	return "free"
