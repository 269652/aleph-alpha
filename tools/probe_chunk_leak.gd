extends SceneTree

## Throwaway probe: walks a ring of chunks in and out repeatedly, the way a
## player crossing a region does, and reports what is left behind each lap.
## A frame rate that starts at 60 and slides to 15 is something ACCUMULATING;
## this says whether it is nodes, objects or memory, and how fast.

## EarthChunkManager ALONE is loaded at run time rather than preloaded, for
## the reason probe_settlement_history_cost.gd already documents: a tool
## script is compiled while the autoloads are still coming up, and this is
## the script with the deepest preload graph in the project, so preloading it
## fails to compile ("Identifier not found: WorldItemBus"). The two below
## have no such graph.
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")

func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities := Node2D.new()
	var creatures := Node2D.new()
	root.add_child(tile_map_layer)
	root.add_child(entities)
	root.add_child(creatures)
	var manager = EarthChunkManager.new(tile_map_layer, entities, creatures)

	var geo := GeoCoordinates.new()
	var size: int = EarthChunkManager.CHUNK_SIZE
	var centre := Vector2i(
		floori(float(geo.tile_for_longitude(9.6, EarthChunkGenerator.WORLD_WIDTH_TILES)) / float(size)),
		floori(float(geo.tile_for_latitude(48.1, EarthChunkGenerator.WORLD_HEIGHT_TILES)) / float(size)),
	)
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			ring.append(centre + Vector2i(dx, dy))

	# Counted by WALKING THE TREE, not read off Performance. Those monitors
	# only refresh on a frame boundary and a -s script never yields one, so
	# they hand back the same stale snapshot every lap -- six identical lines
	# that look exactly like "no leak" and mean nothing. What is really under
	# the parents, plus what the manager still believes is loaded, is data.
	for lap in 6:
		for coord in ring:
			manager._load_chunk(coord)
		var loaded_entities := _descendants(entities)
		var loaded_creatures := _descendants(creatures)
		for coord in ring:
			manager._unload_chunk(coord)
		print("LAP %d after_load(entities=%d creatures=%d) after_unload(entities=%d creatures=%d) chunks=%d" % [
			lap, loaded_entities, loaded_creatures,
			_descendants(entities), _descendants(creatures),
			(manager._loaded_chunks as Dictionary).size(),
		])
	quit()


func _descendants(node: Node) -> int:
	var total := node.get_child_count()
	for child in node.get_children():
		total += _descendants(child)
	return total
