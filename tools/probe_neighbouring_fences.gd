extends SceneTree

## Two farmhouses side by side: what happens on the line between them?
##
## Reported with both enclosures in shot: *"It should be possible to build
## two rails on a single tile so both enclosures are fenced properly. also
## the corner post can be removed"*.
##
## A rail is an ordinary chunk modification and a tile holds ONE
## modification id, so where two fields meet, the second one's rail finds
## the cell already occupied and is skipped (VillageRenderer's own
## `is_occupied` guard) -- one enclosure fenced, the other left open along
## the shared line.
##
## This walks real chunks, finds a village with two farmhouses whose fence
## rings actually TOUCH, and prints the ground: the beds of each field, what
## each field WANTS on every ring cell, and what really stands there.
##
## Usage: godot --headless -s tools/probe_neighbouring_fences.gd

const VillageFarm = preload("res://src/gameplay/village_farm.gd")

const CHUNK_SIZE := 32
const STEPS := 60

var _manager
var _origin: Vector2i
var _step := -1
var _measured := false
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

	if _step < STEPS and not _measured:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		_look(_manager._loaded_chunks.keys())
		_step += 1
		return false

	for line in _lines:
		print(line)
	if _lines.is_empty():
		print("FENCES no village with two touching fields was met in %d chunk-widths" % STEPS)
	return true


func _farmhouses_in(chunk_coord: Vector2i) -> Array:
	var out: Array = []
	for record in _manager.buildings_in_chunk(chunk_coord):
		if String(record["id"]) == VillageFarm.FARM_BUILDING_ID:
			out.append(Vector2i(record["origin_local"]))
	return out


## The beds this farmhouse really works, in LOCAL cells.
func _beds_of(chunk_coord: Vector2i, origin: Vector2i) -> Array:
	var is_free := func(cell: Vector2i) -> bool:
		var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
		return _manager.is_buildable_ground_at(g.x, g.y)
	var rect = VillageFarm.field_rect(origin, VillageFarm.FARM_BUILDING_ID, is_free)
	if rect == null:
		return []
	var beds: Array = []
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			beds.append(Vector2i(x, y))
	return beds


func _look(chunk_coords: Array) -> void:
	if _measured:
		return
	for chunk_coord in chunk_coords:
		var origins := _farmhouses_in(chunk_coord)
		if origins.size() < 2:
			continue
		# field -> its ring, and which cells more than one field wants.
		var rings: Array = []
		var beds_of: Array = []
		for origin in origins:
			var beds := _beds_of(chunk_coord, origin)
			if beds.is_empty():
				rings.append({})
				beds_of.append([])
				continue
			var ring: Dictionary = {}
			for rail in VillageFarm.fence_cells(beds, origin, VillageFarm.FARM_BUILDING_ID):
				ring[rail] = VillageFarm.fence_facing(rail, beds)
			rings.append(ring)
			beds_of.append(beds)
		var wanted_by: Dictionary = {}
		for i in rings.size():
			for cell in rings[i]:
				var claims: Array = wanted_by.get(cell, [])
				claims.append("%d:%s" % [i, rings[i][cell]])
				wanted_by[cell] = claims
		var contested: Array = []
		for cell in wanted_by:
			if (wanted_by[cell] as Array).size() > 1:
				contested.append(cell)
		if contested.is_empty():
			continue

		_measured = true
		_lines.append("")
		_lines.append("NEIGHBOURING FENCES at %s -- %d farmhouses" % [str(chunk_coord), origins.size()])
		_lines.append("  %d ring cells are wanted by more than one field:" % contested.size())
		contested.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
		)
		for cell in contested:
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			_lines.append("    %-9s wanted as %-26s -- actually stands: %s" % [
				str(cell), str(wanted_by[cell]),
				_describe(_manager.modification_at_global(g.x, g.y)),
			])
		_report_map(chunk_coord, origins, rings, beds_of, wanted_by)
		return


func _describe(modification: String) -> String:
	return "(nothing)" if modification == "" else modification


## The ground itself: H a farmhouse, digits the beds of each field, a rail's
## own glyph where one stands, and `!` where two fields want one cell.
func _report_map(
	chunk_coord: Vector2i, origins: Array, rings: Array, beds_of: Array, wanted_by: Dictionary
) -> void:
	var glyph := {
		"north": "^", "south": "v", "east": ">", "west": "<",
		"corner_nw": "+", "corner_ne": "+", "corner_sw": "+", "corner_se": "+",
	}
	var min_c := Vector2i(CHUNK_SIZE, CHUNK_SIZE)
	var max_c := Vector2i(0, 0)
	for i in rings.size():
		for cell in rings[i]:
			min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
			max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
	_lines.append("")
	_lines.append("  -- the ground (H farmhouse, 0/1 beds, ^v<> rails, + post, ! contested) --")
	for y in range(maxi(min_c.y - 1, 0), mini(max_c.y + 2, CHUNK_SIZE)):
		var row := "  "
		for x in range(maxi(min_c.x - 1, 0), mini(max_c.x + 2, CHUNK_SIZE)):
			var cell := Vector2i(x, y)
			var ch := "."
			var g: Vector2i = chunk_coord * CHUNK_SIZE + cell
			var modification: String = _manager.modification_at_global(g.x, g.y)
			if modification.begins_with("farm_fence"):
				ch = glyph.get(modification.replace("farm_fence_", ""), "#")
			elif modification != "":
				ch = "B"
			for i in beds_of.size():
				if (beds_of[i] as Array).has(cell):
					ch = str(i)
			for origin in origins:
				if cell == origin:
					ch = "H"
			if (wanted_by.get(cell, []) as Array).size() > 1:
				ch = "!"
			row += ch
		_lines.append(row)
