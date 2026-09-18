extends SceneTree

## Throwaway probe: reported live -- "it starts at 60-100 fps but quickly
## degrades to 20ish".
##
## A framerate that starts high and falls is accumulation, not a slow
## algorithm: something the world keeps making and never lets go of. This
## loads and unloads the SAME real chunks over and over and counts the live
## nodes by class after each cycle, so anything that survives an unload shows
## up as a count that climbs cycle after cycle instead of returning to where
## it started.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const SettlementGenerator = preload("res://src/world/settlement_generator.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")

const CYCLES := 6


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
		floori(float(geo.tile_for_longitude(8.4, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(51.2, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	# A settlement chunk and two plain ones: a village is where most of the
	# per-chunk nodes are.
	var gen := SettlementGenerator.new()
	var classifier := BiomeClassifier.new()
	var coords: Array = []
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var candidate := centre + Vector2i(dx, dy)
			if not gen.has_settlement_at(candidate, "grassland"):
				continue
			var chunk = manager.generator.generate_chunk(candidate, size)
			if gen.has_settlement_at(candidate, classifier.dominant_biome(chunk.biome)):
				coords.append(candidate)
			if coords.size() >= 2:
				break
		if coords.size() >= 2:
			break
	coords.append(centre + Vector2i(3, 3))
	print("chunks: ", coords)

	for cycle in CYCLES:
		for coord in coords:
			manager._load_chunk(coord)
		for coord in coords:
			manager._unload_chunk(coord)
		print("cycle %d  %s" % [cycle, _census(root)])
	quit(0)


## Every live node under `node`, by class name -- only the classes that
## actually appear, so the line stays readable.
func _census(node: Node) -> String:
	var counts := {}
	_count(node, counts)
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array = []
	for key in keys:
		parts.append("%s=%d" % [key, counts[key]])
	return " ".join(parts)


func _count(node: Node, counts: Dictionary) -> void:
	var key: String = node.get_script().resource_path.get_file() if node.get_script() != null else node.get_class()
	counts[key] = int(counts.get(key, 0)) + 1
	for child in node.get_children():
		_count(child, counts)
