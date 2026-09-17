extends SceneTree

## Throwaway probe: walks a ring of chunks in and out repeatedly, the way a
## player crossing a region does, and reports what is left behind each lap.
## A frame rate that starts at 60 and slides to 15 is something ACCUMULATING;
## this says whether it is nodes, objects or memory, and how fast.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

func _init() -> void:
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager := EarthChunkManager.new(tile_map_layer, entities, creatures)

	var geo := GeoCoordinates.new()
	var size := EarthChunkManager.CHUNK_SIZE
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(9.6, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(48.1, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			ring.append(centre + Vector2i(dx, dy))

	for lap in 6:
		for coord in ring:
			manager._load_chunk(coord)
		for coord in ring:
			manager._unload_chunk(coord)
		print("LAP %d nodes=%d objects=%d orphans=%d static_mem=%.1fMB" % [
			lap,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		])
	quit()
