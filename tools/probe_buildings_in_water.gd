extends SceneTree

## Throwaway probe: reported live with the screenshot -- "Buildings are placed
## in rivers". Founds real villages on real settlement chunks and reports
## every placed building cell that is really water, so the claim is measured
## rather than argued about.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

const SPAN := 10


func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var size: int = EarthChunkManager.CHUNK_SIZE
	var geo := GeoCoordinates.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(9.5, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(52.3, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	var gen := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var villages := 0
	var wet_buildings := 0
	var wet_villages := 0

	for dy in range(-SPAN, SPAN + 1):
		for dx in range(-SPAN, SPAN + 1):
			var coord := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(coord, "grassland"):
				continue
			var chunk = manager.generator.generate_chunk(coord, size)
			if not gen.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
				continue
			manager._load_chunk(coord)
			villages += 1
			var wet_here := 0
			var loaded = manager._loaded_chunks.get(coord)
			if loaded != null:
				for origin_local in loaded.buildings:
					var building_id: String = loaded.buildings[origin_local].get("id", "")
					for cell in BuildingCatalog.footprint_cells(building_id, origin_local):
						var g: Vector2i = coord * size + cell
						if manager.is_water_at_global(g.x, g.y):
							wet_here += 1
							print("  WET %s at %s (chunk %s) river=%s pond=%s" % [
								building_id, str(g), str(coord),
								str(manager.is_river_at_global(g.x, g.y)),
								str(manager.is_pond_at_global(g.x, g.y))
							])
							break
			if wet_here > 0:
				wet_villages += 1
				wet_buildings += wet_here
			manager._unload_chunk(coord)

	print("villages=%d  villages_with_a_building_in_water=%d  buildings_in_water=%d" % [
		villages, wet_villages, wet_buildings
	])
	quit(0)
