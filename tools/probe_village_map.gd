extends SceneTree

## Dev tool: prints an ASCII map of a REAL generated village, so the whole
## of docs/concept/village_growth.md's charter can be seen at once -- the
## street, the paved plaza, the civic plot, every house, and the sawmill at
## the forest with its road spur back to the street.
##
## Usage: godot --headless -s tools/probe_village_map.gd

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const CHUNK_SIZE := EarthChunkManager.CHUNK_SIZE

## One letter per building id, so a map shows WHAT stands where rather than
## an undifferentiated block of walls.
const _BUILDING_CHARS := {
	"house_small": "h", "house_medium": "H", "house_large": "M",
	"city_hall": "C", "warehouse": "W", "sawmill": "S",
	"farmhouse": "F", "blacksmith": "B", "brewery": "R",
}


func _initialize() -> void:
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	var manager := EarthChunkManager.new(tile_map_layer, entities, creatures)

	var coord := _find_village(manager)
	if coord == Vector2i.MAX:
		print("no settlement chunk found in the scanned neighbourhood")
		quit()
		return
	_scrub(manager, coord)
	manager._load_chunk(coord)

	var chunk = manager._loaded_chunks.get(coord)
	if chunk == null:
		print("chunk failed to load")
		quit()
		return
	var anchors := {}
	for origin_local in chunk.buildings:
		anchors[origin_local] = chunk.buildings[origin_local]["id"]

	print("village at chunk %s  (households: %d)" % [
		str(coord), manager.household_count_for_settlement(EntityRef.for_settlement(coord))
	])
	print("legend: '=' road/plaza  'T' forest  '~' water  '.' open ground")
	print("        h/H/M house  C city hall  W warehouse  S sawmill  F farmhouse  B smithy  R brewery")
	print("        (a capital marks the building's own anchor cell)")
	print("")
	for y in CHUNK_SIZE:
		var line := ""
		for x in CHUNK_SIZE:
			line += _char_at(manager, chunk, coord, Vector2i(x, y), anchors)
		print(line)

	var mills := 0
	for origin_local in anchors:
		if anchors[origin_local] == "sawmill":
			mills += 1
	print("")
	print("sawmill standing: %s" % ("yes" if mills > 0 else "no -- no timber in reach"))
	print("plaza laid: %s" % ("yes" if manager._civic_plot_origin_for(coord) != null else "no (or the hall already stands on it)"))
	_scrub(manager, coord)
	quit()


func _char_at(manager, chunk, coord: Vector2i, local: Vector2i, anchors: Dictionary) -> String:
	if anchors.has(local):
		return _BUILDING_CHARS.get(anchors[local], "?").to_upper()
	var tile: String = chunk.modifications.get(local, "")
	if tile == BuildingCatalog.FOOTPRINT_TILE_ID:
		# Which building's footprint this is -- walk back to its anchor.
		for origin_local in anchors:
			for cell in BuildingCatalog.footprint_cells(anchors[origin_local], origin_local):
				if cell == local:
					return _BUILDING_CHARS.get(anchors[origin_local], "?").to_lower()
		return "#"
	if TerrainRenderer.is_road_tile(tile):
		return "="
	if tile != "":
		return "*"
	var g: Vector2i = coord * CHUNK_SIZE + local
	if manager.is_water_at_global(g.x, g.y):
		return "~"
	if manager.biome_at_global(g.x, g.y) == "forest":
		return "T"
	return "."


func _find_village(manager) -> Vector2i:
	var settlements := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var geo := GeoCoordinates.new()
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(CHUNK_SIZE)),
		floori(float(geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(CHUNK_SIZE)),
	)
	for radius in range(0, 16):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var coord := centre + Vector2i(dx, dy)
				if not settlements.has_settlement_at(coord, "grassland"):
					continue
				var chunk = manager.generator.generate_chunk(coord, CHUNK_SIZE)
				if settlements.has_settlement_at(coord, classifier.dominant_biome(chunk.biome)):
					return coord
	return Vector2i.MAX


func _scrub(manager, coord: Vector2i) -> void:
	for path in [
		manager._modifications_path(coord), manager._buildings_path(coord),
		manager._roof_modifications_path(coord), manager._furniture_modifications_path(coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
