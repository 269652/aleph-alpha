extends SceneTree

## Do two farmhouses in one village end up on top of each other, and does
## only one of them get an enclosure?
##
## Reported live with the hamlet in shot: *"The two farmhouses collide and
## only one gets an enclosure"*.
##
## probe_farmhouse_fields.gd already asks the second half against a flat
## StubWorld. This asks both against REAL villages on real ground, because
## what the report shows is two farmsteads whose ground overlaps -- and a
## stub with no water, no forest and no street cannot produce the crowding
## that causes it.
##
## Per chunk with two or more farmhouses it reports, for each farmhouse:
## its origin, the field VillageRenderer really derives for it
## (_workable_field_of, the same call the renderer makes), and every overlap
## between one farmstead's ground and another's -- footprint, doorstep,
## field and fence ring alike.

const CHUNK_SIZE := 32
const LAT := 48.6
const LON := 12.7
const STEPS := 90        # chunks walked east; chunks unload behind, so report as we go
const SETTLE_STEPS := 2

var _manager
var _origin: Vector2i
var _step := 0
var _settling := 0
var _seen: Dictionary = {}
var _villages := 0
var _crowded := 0
var _fieldless := 0
var _overlaps := 0
var _renderer
var _VillageFarm
var _BuildingCatalog


func _initialize() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var geo = GeoCoordinates.new()
	var centre := Vector2i(
		geo.tile_for_longitude(LON, EarthChunkGenerator.WORLD_WIDTH_TILES) / CHUNK_SIZE,
		geo.tile_for_latitude(LAT, EarthChunkGenerator.WORLD_HEIGHT_TILES) / CHUNK_SIZE
	)
	_origin = centre


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
		_renderer = load("res://src/rendering/village_renderer.gd").new()
		_VillageFarm = load("res://src/gameplay/village_farm.gd")
		_BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
		print("")
		print("=== farmsteads ===")
		return false
	if _step < STEPS:
		var c: Vector2i = _origin + Vector2i(_step, 0)
		# Founding, not a reload. Chunks persist on unload, so a second run
		# of this probe would otherwise measure the villages the FIRST run
		# founded -- which is how an A/B of a siting change can come back
		# byte-identical and mean nothing. The test suites scrub the same
		# way before loading a chunk they mean to found.
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				_scrub(c + Vector2i(dx, dy))
		_manager.update(Vector2((c * CHUNK_SIZE + Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2))))
		_step += 1
		if _settling < SETTLE_STEPS:
			_settling += 1
			return false
		_settling = 0
		for chunk_coord in _manager._loaded_chunks.keys():
			if _seen.has(chunk_coord):
				continue
			_seen[chunk_coord] = true
			_examine(chunk_coord)
		return false
	print("")
	print("chunks swept: %d   villages with a farmhouse: %d   with two or more: %d" % [
		_seen.size(), _villages, _crowded
	])
	print("farmhouses with NO field: %d   villages with overlapping farm ground: %d" % [
		_fieldless, _overlaps
	])
	return true


## Everything persisted about this chunk, so the next load really founds it.
func _scrub(chunk_coord: Vector2i) -> void:
	for path in [
		_manager._modifications_path(chunk_coord), _manager._buildings_path(chunk_coord),
		_manager._roof_modifications_path(chunk_coord),
		_manager._furniture_modifications_path(chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _examine(chunk_coord: Vector2i) -> void:
	var VillageFarm = _VillageFarm
	var BuildingCatalog = _BuildingCatalog
	var renderer = _renderer
	var origins: Array = []
	for record in _manager.buildings_in_chunk(chunk_coord):
		if record.get("id", "") == VillageFarm.FARM_BUILDING_ID:
			origins.append(record["origin_local"])
	if origins.is_empty():
		return
	origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	_villages += 1
	if origins.size() >= 2:
		_crowded += 1
	renderer._buildable_memo.clear()
	renderer._dry_memo.clear()
	renderer._skeleton_memo.clear()
	var is_buildable: Callable = renderer._is_buildable_local(chunk_coord, CHUNK_SIZE, _manager)
	var is_occupied: Callable = renderer._is_occupied_local(chunk_coord, CHUNK_SIZE, _manager)
	var ground: Dictionary = {}
	var lines: Array = []
	var empty_here := 0
	for origin in origins:
		var field: Array = renderer._workable_field_of(
			origin, origins, chunk_coord, CHUNK_SIZE, is_buildable, is_occupied, _manager
		)
		if field.is_empty():
			_fieldless += 1
			empty_here += 1
		var mine: Dictionary = {}
		for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin):
			mine[cell] = "house"
		mine[origin + BuildingCatalog.doorstep_of(VillageFarm.FARM_BUILDING_ID)] = "door"
		var local_field: Array = []
		for g in field:
			var local: Vector2i = (g as Vector2i) - chunk_coord * CHUNK_SIZE
			local_field.append(local)
			mine[local] = "bed"
		for cell in VillageFarm.fence_cells(local_field, origin, VillageFarm.FARM_BUILDING_ID):
			if not mine.has(cell):
				mine[cell] = "rail"
		ground[origin] = mine
		# ...and what is REALLY on the ground: how much of this farmstead's
		# own ring carries a fence tile after the whole pass has run.
		var wanted := 0
		var standing := 0
		var gaps: Array = []
		for cell in VillageFarm.fence_cells(local_field, origin, VillageFarm.FARM_BUILDING_ID):
			var c: Vector2i = cell
			if c.x < 0 or c.y < 0 or c.x >= CHUNK_SIZE or c.y >= CHUNK_SIZE:
				continue
			wanted += 1
			var g: Vector2i = chunk_coord * CHUNK_SIZE + c
			var mod: String = _manager.modification_at_global(g.x, g.y)
			if VillageFarm.is_fence_tile(mod):
				standing += 1
			else:
				var why := "mod='%s'" % mod
				if not is_buildable.call(c):
					why = "not buildable"
				elif renderer._is_street_row(chunk_coord, CHUNK_SIZE, _manager, c.y):
					why += " streetrow"
				gaps.append("%s %s" % [str(c), why])
		lines.append("   farmhouse %s  field=%d  rails standing %d/%d  %s" % [
			str(origin), local_field.size(), standing, wanted, str(local_field)
		])
		if not gaps.is_empty():
			lines.append("      gaps: %s" % str(gaps))
	var clashes: Array = []
	for i in range(origins.size()):
		for j in range(i + 1, origins.size()):
			var a: Dictionary = ground[origins[i]]
			var b: Dictionary = ground[origins[j]]
			for cell in a:
				if b.has(cell):
					clashes.append("%s %s/%s" % [str(cell), a[cell], b[cell]])
	if not clashes.is_empty():
		_overlaps += 1
	if origins.size() < 2 and empty_here == 0 and clashes.is_empty():
		return  # a lone, well-fed farmstead is not what this probe is looking for
	print("")
	print("VILLAGE %s  farmhouses=%d  fieldless=%d" % [str(chunk_coord), origins.size(), empty_here])
	for line in lines:
		print(line)
	if not clashes.is_empty():
		print("   OVERLAPS: %s" % str(clashes))
