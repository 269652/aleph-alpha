extends SceneTree

## How much room to grow the settlement chunks near Berlin really have --
## the fixture question test_earth_chunk_manager_village_growth.gd depends
## on: a village with a square AND houses is not necessarily a village that
## can still house ten newcomers.

const CHUNK_SIZE := 32

var _manager
var _done := false


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
	if not _done:
		_done = true
		_report()
	return true


func _report() -> void:
	var EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	var GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	var SettlementGenerator = load("res://src/world/settlement_generator.gd")
	var BiomeClassifier = load("res://src/world/biome_classifier.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var VillageLayout = load("res://src/world/village_layout.gd")
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var geo = GeoCoordinates.new()
	var gen = SettlementGenerator.new()
	var classifier = BiomeClassifier.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE))
	)
	var loads := 0
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			if loads >= 14:
				return
			var coord := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(coord, "grassland"):
				continue
			var chunk = _manager.generator.generate_chunk(coord, CHUNK_SIZE)
			if not gen.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
				continue
			loads += 1
			_manager._load_chunk(coord)
			var ids: Dictionary = {}
			var houses := 0
			for record in _manager.buildings_in_chunk(coord):
				var id: String = record.get("id", "")
				ids[id] = int(ids.get(id, 0)) + 1
				if BuildingCatalog.capacity_of(id) > 0:
					houses += 1
			# the square, really laid?
			var bones: Dictionary = VillageLayout.skeleton(
				CHUNK_SIZE, VillageLayout.seed_for(coord), _manager._is_dry_local(coord)
			)
			var plaza: Rect2i = bones["plaza"]
			var square_real := true
			for y in range(plaza.position.y, plaza.end.y):
				for x in range(plaza.position.x, plaza.end.x):
					var tile: String = _manager._loaded_chunks[coord].modifications.get(Vector2i(x, y), "")
					if not (TerrainRenderer.is_road_tile(tile) or BuildingCatalog.occupies(tile)):
						square_real = false
			# how many MORE houses could the street still take?
			var spare := _spare_plots(coord, "house_small", 20)
			print("CANDIDATE %s houses=%d square=%s spare_plots=%d buildings=%s" % [
				str(coord), houses, str(square_real), spare, str(ids)
			])
			_manager._unload_chunk(coord)


## How many further house plots this village's own streets could still take
## -- pure, by claiming each answer before asking again.
func _spare_plots(coord: Vector2i, building_id: String, cap: int) -> int:
	var VillageLayout = load("res://src/world/village_layout.gd")
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	var claimed: Dictionary = {}
	var is_buildable := func(cell: Vector2i) -> bool:
		var g: Vector2i = coord * CHUNK_SIZE + cell
		return _manager.is_buildable_ground_at(g.x, g.y)
	var is_occupied := func(cell: Vector2i) -> bool:
		if claimed.has(cell):
			return true
		var g: Vector2i = coord * CHUNK_SIZE + cell
		return _manager.modification_at_global(g.x, g.y) != ""
	var is_paved := func(cell: Vector2i) -> bool:
		if claimed.has(cell):
			return false
		var g: Vector2i = coord * CHUNK_SIZE + cell
		return TerrainRenderer.is_road_tile(_manager.modification_at_global(g.x, g.y))
	var found := 0
	while found < cap:
		var plot: Dictionary = VillageLayout.next_street_plot(
			building_id, CHUNK_SIZE, VillageLayout.seed_for(coord), is_buildable, is_occupied,
			_manager._is_dry_local(coord), Callable(), is_paved
		)
		if plot.is_empty():
			return found
		found += 1
		for cell in BuildingCatalog.footprint_cells(building_id, plot["origin"]):
			claimed[cell] = true
	return found
