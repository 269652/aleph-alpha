extends SceneTree

## Where do real seeded beehives actually stand, relative to a real tree?
##
## Reported live: *"Beehives should not be built on grass... they need a tree
## branch to build it please"* -- so this measures the gap between what
## _has_real_hive_anchor allows (a tree ANYWHERE within
## a tree anywhere within a radius) and what a hive hanging from a branch
## needs (a tree on the hive's own tile). Loads real chunks around several
## real places and reports, per seeded hive, how far its own tile is from
## the nearest real standing tree -- so the fix can be re-measured rather
## than assumed to have worked.

const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## Two real, tree-bearing places, 2x2 chunks each. Kept small on purpose:
## generating real terrain is genuinely slow, and a 3x3 around four places
## ran past fifteen minutes without finishing. Eight chunks is enough to
## see several real hives.
const PLACES := {
	"Berlin": Vector2(13.405, 52.52),
	"Bavaria": Vector2(11.58, 48.14),
}


## EarthChunkManager ALONE is loaded at run time rather than preloaded, for
## the reason tools/probe_chunk_leak.gd already documents: a tool script is
## compiled while the project's autoloads are still coming up, and this is
## the script with the deepest preload graph in the project, so preloading it
## fails to compile ("Identifier not found: WorldItemBus"). The three above
## have no such graph.
func _initialize() -> void:
	var EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	var tile_map_layer := TileMapLayer.new()
	var entities_parent := Node2D.new()
	var creatures_parent := Node2D.new()
	get_root().add_child(entities_parent)
	var manager := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()

	var hives_total := 0
	var hives_on_a_tree_tile := 0
	var distances: Array[float] = []
	var tree_tile_share: Array[float] = []

	for name in PLACES:
		var lonlat: Vector2 = PLACES[name]
		var tile := Vector2i(
			geo.tile_for_longitude(lonlat.x, EarthChunkGenerator.WORLD_WIDTH_TILES),
			geo.tile_for_latitude(lonlat.y, EarthChunkGenerator.WORLD_HEIGHT_TILES)
		)
		var home := Vector2i(
			floori(float(tile.x) / EarthChunkManager.CHUNK_SIZE),
			floori(float(tile.y) / EarthChunkManager.CHUNK_SIZE)
		)
		for dy in range(0, 2):
			for dx in range(0, 2):
				var chunk_coord := home + Vector2i(dx, dy)
				manager._load_chunk(chunk_coord)
				var trees: Array = manager._loaded_trees.get(chunk_coord, [])
				var occupied: Dictionary = {}
				for tree in trees:
					if is_instance_valid(tree) and not tree.is_felled():
						occupied[_tile_of(tree.position)] = true
				tree_tile_share.append(
					float(occupied.size())
					/ float(EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE)
				)
				var colony = manager._bee_colonies.get(chunk_coord, null)
				if colony == null:
					continue
				for hive_cell in colony.hive_cells():
					hives_total += 1
					var global_tile: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + hive_cell
					if occupied.has(global_tile):
						hives_on_a_tree_tile += 1
					var pixel := (Vector2(global_tile) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)
					var nearest := 1e9
					for tree in trees:
						if not is_instance_valid(tree) or tree.is_felled():
							continue
						nearest = minf(nearest, tree.position.distance_to(pixel))
					distances.append(nearest / float(TerrainRenderer.TILE_SIZE))
					print("  %-8s hive at %s -- nearest tree %.2f tiles, on a tree tile: %s" % [
						name, global_tile, nearest / float(TerrainRenderer.TILE_SIZE),
						"YES" if occupied.has(global_tile) else "no",
					])

	print()
	print("hives seeded:            %d" % hives_total)
	print("standing on a tree tile: %d" % hives_on_a_tree_tile)
	if not distances.is_empty():
		distances.sort()
		print("distance to nearest tree (tiles): min %.2f  median %.2f  max %.2f" % [
			distances[0], distances[distances.size() / 2], distances[-1],
		])
	if not tree_tile_share.is_empty():
		var total := 0.0
		for share in tree_tile_share:
			total += share
		print("share of a chunk's tiles holding a standing tree: %.1f%% mean over %d chunks" % [
			total / float(tree_tile_share.size()) * 100.0, tree_tile_share.size(),
		])
	quit()


func _tile_of(pixel: Vector2) -> Vector2i:
	return Vector2i(
		floori(pixel.x / float(TerrainRenderer.TILE_SIZE)),
		floori(pixel.y / float(TerrainRenderer.TILE_SIZE))
	)
