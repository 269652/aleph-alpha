extends SceneTree

## Where, in a real village's chunk, a SECOND farmhouse could stand with a
## field of its own -- and why the siting walkers do or do not find it.
##
## Measured because a real village (tools/probe_village_economy.gd) with
## three farming households and one farmhouse ate its shelves to zero: the
## renderer raises one farmhouse per farming villager and stopped at one,
## so either the chunk has no room for a second field or the walkers never
## reach the room it has. A map says which.
##
## Usage: godot --headless -s tools/probe_field_room.gd

const CHUNK_SIZE := 32
const STEPS := 40

var _manager
var _origin: Vector2i
var _step := -1
var _done := false


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
	if _step < STEPS and not _done:
		_manager.update(_origin + Vector2i(_step * CHUNK_SIZE, 0))
		for chunk_coord in _manager._loaded_villages:
			if _villagers(chunk_coord) > 0:
				_report(chunk_coord)
				_done = true
				return true
		_step += 1
		return false
	print("FIELD ROOM: no populated village met")
	return true


func _villagers(chunk_coord: Vector2i) -> int:
	var count := 0
	for node in _manager._loaded_villages.get(chunk_coord, []):
		if is_instance_valid(node) and node.has_method("setup_economy"):
			count += 1
	return count


func _report(chunk_coord: Vector2i) -> void:
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var VillageFarm = load("res://src/gameplay/village_farm.gd")
	var VillageLayout = load("res://src/world/village_layout.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var renderer = _manager._village_renderer
	var base: Vector2i = chunk_coord * CHUNK_SIZE
	print("FIELD ROOM at %s" % str(chunk_coord))
	# The buildings and their origins.
	var farm_origins: Array = []
	var footprint_of := {}
	for record in _manager.buildings_in_chunk(chunk_coord):
		var id := String(record["id"])
		var origin: Vector2i = record["origin_local"]
		if id == VillageFarm.FARM_BUILDING_ID:
			farm_origins.append(origin)
		for cell in BuildingCatalog.footprint_cells(id, origin):
			footprint_of[cell] = id
	print("  buildings: %s" % str(_manager._settlement_building_counts(chunk_coord)))
	print("  farmhouse origins: %s" % str(farm_origins))
	# The map.
	var is_buildable: Callable = renderer._is_buildable_local(chunk_coord, CHUNK_SIZE, _manager)
	var is_occupied: Callable = renderer._is_occupied_local(chunk_coord, CHUNK_SIZE, _manager)
	var free := 0
	print("  map ('.' free, '=' road, 'W' unbuildable, 'F' farmhouse, 'f' its field, 'B' other building, 'x' fence/other):")
	var field_cells := {}
	for origin in farm_origins:
		var beds: Array = renderer._workable_field_of(
			origin, farm_origins, chunk_coord, CHUNK_SIZE, is_buildable, is_occupied, _manager
		)
		for cell in beds:
			var local: Vector2i = Vector2i(cell)
			if local.x >= base.x and local.y >= base.y:
				local -= base
			field_cells[local] = true
	for y in CHUNK_SIZE:
		var row := "  "
		for x in CHUNK_SIZE:
			var cell := Vector2i(x, y)
			var g: Vector2i = base + cell
			var mod: String = _manager.modification_at_global(g.x, g.y)
			var ch := "."
			if not is_buildable.call(cell):
				ch = "W"
			elif footprint_of.has(cell):
				ch = "F" if footprint_of[cell] == VillageFarm.FARM_BUILDING_ID else "B"
			elif field_cells.has(cell):
				ch = "f"
			elif TerrainRenderer.is_road_tile(mod):
				ch = "="
			elif mod != "":
				ch = "x"
			else:
				free += 1
			row += ch
		print(row)
	print("  free buildable cells: %d of %d" % [free, CHUNK_SIZE * CHUNK_SIZE])
	# Where a second farmhouse could stand with a field.
	var clear := 0
	var with_field := 0
	var first_fit: Array = []
	for y in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			var origin := Vector2i(x, y)
			var ok := true
			for cell in BuildingCatalog.footprint_cells(VillageFarm.FARM_BUILDING_ID, origin) + [origin + BuildingCatalog.doorstep_of(VillageFarm.FARM_BUILDING_ID)]:
				if not VillageLayout._cell_clear(cell, CHUNK_SIZE, is_buildable, is_occupied):
					ok = false
					break
			if not ok:
				continue
			clear += 1
			if renderer._field_fits_at(origin, farm_origins + [origin], {}, chunk_coord, CHUNK_SIZE, _manager, is_buildable, is_occupied):
				with_field += 1
				if first_fit.size() < 12:
					first_fit.append(origin)
	print("  farmhouse origins with a clear footprint: %d; of those with room for a field: %d" % [clear, with_field])
	print("  first field-capable origins: %s" % str(first_fit))
	# What the walkers say.
	var accepts := func(origin: Vector2i) -> bool:
		return renderer._field_fits_at(origin, farm_origins + [origin], {}, chunk_coord, CHUNK_SIZE, _manager, is_buildable, is_occupied)
	var is_paved: Callable = renderer._is_paved_local(chunk_coord, CHUNK_SIZE, _manager)
	var street: Dictionary = VillageLayout.next_street_plot(
		VillageFarm.FARM_BUILDING_ID, CHUNK_SIZE, VillageLayout.seed_for(chunk_coord),
		is_buildable, is_occupied, is_buildable, accepts, is_paved
	)
	print("  next_street_plot with field room: %s" % str(street.get("origin", "none")))
	var outskirt: Dictionary = VillageLayout.outskirt_plot(
		VillageFarm.FARM_BUILDING_ID, CHUNK_SIZE, VillageLayout.seed_for(chunk_coord),
		is_buildable, is_occupied, accepts, is_buildable
	)
	print("  outskirt_plot with field room: %s" % str(outskirt.get("origin", "none")))
	var growth = _manager._growth_site_for(chunk_coord, VillageFarm.FARM_BUILDING_ID)
	print("  manager _growth_site_for(farmhouse): %s" % str(growth))
