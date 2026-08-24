extends SceneTree

## TEMPORARY PROBE (see CLAUDE.md METHODOLOGY: real-chunk debug-probe
## technique already used for all four prior corner-blend bug rounds --
## see docs/progress.md's corner-blend history around line 3140-3440).
##
## Fifth-round investigation: "blended tiles still have sharp edges and
## corner tiles are not blended", reported with a screenshot of a
## grass/forest area near a grass/dirt-path-looking boundary. Loads a REAL
## chunk through the REAL EarthChunkManager/TerrainRenderer, finds a real
## forest/grassland border cell, and inspects:
##   (a) the real biome/biome border (already fixed by 4 prior rounds --
##       confirm it's still fine, not a regression of an old fix)
##   (b) a real EARTH_TILE_ID modification cell (the same tile
##       PathScarring's "trampled path" and the player-build system both
##       use -- see TerrainRenderer.paint's modifications branch) sitting
##       directly next to real biome-blended ground, which is the exact
##       "grass to dirt path" shape the report describes.
##
## Usage: godot --headless -s tools/probe_path_scar_blend.gd

var EarthChunkManager
var TerrainRenderer
var GeoCoordinates
var EarthChunkGenerator
var BiomeClassifier


func _init() -> void:
	var max_iter := 20
	var iter := 0
	while Engine.get_main_loop() == null and iter < max_iter:
		await create_timer(.01).timeout
		iter += 1

	EarthChunkManager = load("res://src/world/earth_chunk_manager.gd")
	TerrainRenderer = load("res://src/rendering/terrain_renderer.gd")
	GeoCoordinates = load("res://src/world/geo_coordinates.gd")
	EarthChunkGenerator = load("res://src/world/earth_chunk_generator.gd")
	BiomeClassifier = load("res://src/world/biome_classifier.gd")

	_run()
	quit()


func _make_region():
	var tile_map_layer := TileMapLayer.new()
	var entities_parent := Node2D.new()
	var creatures_parent := Node2D.new()
	return EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func _run() -> void:
	var geo = GeoCoordinates.new()
	# Grunewald forest on Berlin's western edge -- real forest/grassland
	# adjacency expected nearby (see prior rounds' own Berlin-chunk probes).
	var candidates := [
		{"name": "Berlin/Grunewald", "lat": 52.48, "lon": 13.22},
		{"name": "Berlin center", "lat": 52.52, "lon": 13.405},
		{"name": "Berlin/Tegeler Forst", "lat": 52.58, "lon": 13.25},
	]

	for c in candidates:
		var tile := Vector2i(
			geo.tile_for_longitude(c["lon"], EarthChunkGenerator.WORLD_WIDTH_TILES),
			geo.tile_for_latitude(c["lat"], EarthChunkGenerator.WORLD_HEIGHT_TILES)
		)
		print("=== %s tile=%s ===" % [c["name"], tile])
		var manager = _make_region()
		manager.update(tile)

		var chunk_coord: Vector2i = manager._chunk_coord_for_tile(tile)
		var chunk = manager._loaded_chunks.get(chunk_coord)
		if chunk == null:
			print("  chunk not loaded, skipping")
			continue

		# Find a real forest cell with a grassland cardinal neighbor inside
		# this same chunk (a real, in-chunk shared-edge border).
		var found := false
		for y in chunk.height:
			for x in chunk.width:
				var biome: String = chunk.biome[y * chunk.width + x]
				if biome != "forest":
					continue
				for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
					var nx: int = x + dir.x
					var ny: int = y + dir.y
					if nx < 0 or nx >= chunk.width or ny < 0 or ny >= chunk.height:
						continue
					if chunk.biome[ny * chunk.width + nx] == "grassland":
						_report_biome_border(manager, chunk, chunk_coord, x, y)
						found = true
						break
				if found:
					break
			if found:
				break
		if not found:
			print("  no forest/grassland in-chunk shared edge found here")
			continue

		# Now simulate a worn dirt path (the same EARTH_TILE_ID modification
		# both player-building and PathScarring apply) on a grassland cell
		# and inspect what actually gets painted around it.
		_report_earth_modification_border(manager, chunk, chunk_coord, tile)
		return  # one good candidate is enough


func _report_biome_border(manager, chunk, chunk_coord: Vector2i, x: int, y: int) -> void:
	print("  Real forest cell (%d,%d) has a grassland neighbor in-chunk." % [x, y])
	var global: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
	var atlas_coords: Vector2i = manager._tile_map_layer.get_cell_atlas_coords(global)
	var plain_forest: Vector2i = manager._terrain_renderer.atlas_coords_for_biome(
		"forest", manager._terrain_renderer.variant_index_for_position(global.x, global.y)
	)
	print("    painted atlas_coords=%s, plain-forest atlas_coords=%s -> %s" % [
		atlas_coords, plain_forest,
		"BLENDED (differs from plain forest, as expected)" if atlas_coords != plain_forest else "**NOT BLENDED - hard edge**"
	])


func _report_earth_modification_border(manager, chunk, chunk_coord: Vector2i, player_tile: Vector2i) -> void:
	# Find a grassland cell with an all-grassland neighborhood (a clean,
	# uncomplicated spot -- no pre-existing blend/corner tile muddying the
	# comparison) to plant a worn path on, mirroring what PathScarring does
	# to whatever tile the player repeatedly stands on.
	var target := Vector2i(-1, -1)
	for y in range(1, chunk.height - 1):
		for x in range(1, chunk.width - 1):
			if chunk.biome[y * chunk.width + x] != "grassland":
				continue
			var all_grass := true
			for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				if chunk.biome[(y + dir.y) * chunk.width + (x + dir.x)] != "grassland":
					all_grass = false
					break
			if all_grass:
				target = Vector2i(x, y)
				break
		if target.x != -1:
			break

	if target.x == -1:
		print("  no clean interior grassland cell found for the earth-modification probe")
		return

	var global: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + target
	print("  Planting a worn dirt path (EARTH_TILE_ID) at grassland cell %s (global %s)" % [target, global])

	var before: Vector2i = manager._tile_map_layer.get_cell_atlas_coords(global)
	var plain_grass: Vector2i = manager._terrain_renderer.atlas_coords_for_biome(
		"grassland", manager._terrain_renderer.variant_index_for_position(global.x, global.y)
	)
	print("    BEFORE atlas_coords=%s (plain grassland=%s)" % [before, plain_grass])

	var ok: bool = manager.build_at_global(global.x, global.y, TerrainRenderer.EARTH_TILE_ID)
	print("    build_at_global returned %s" % ok)

	var after: Vector2i = manager._tile_map_layer.get_cell_atlas_coords(global)
	var earth_coords: Vector2i = manager._terrain_renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID)
	print("    AFTER atlas_coords=%s (flat earth-modification coords=%s) -> %s" % [
		after, earth_coords,
		"IS the flat unblended earth tile (no border treatment at all)" if after == earth_coords else "unexpected"
	])

	# Now inspect the REAL baked pixels at the seam between this earth tile
	# and its still-pure-grassland neighbor to the east, to see whether
	# there is ANY dithered/carved transition or a dead-flat color cutoff.
	var tile_set = manager._terrain_renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()
	var art: int = TerrainRenderer.ART_TILE_SIZE

	var earth_origin := Vector2i(after.x * art, after.y * art)
	var earth_tile_img := image.get_region(Rect2i(earth_origin, Vector2i(art, art)))

	var neighbor_global := global + Vector2i(1, 0)
	var neighbor_atlas: Vector2i = manager._tile_map_layer.get_cell_atlas_coords(neighbor_global)
	var neighbor_origin := Vector2i(neighbor_atlas.x * art, neighbor_atlas.y * art)
	var neighbor_tile_img := image.get_region(Rect2i(neighbor_origin, Vector2i(art, art)))

	var earth_edge_pixel := earth_tile_img.get_pixel(art - 1, art / 2)
	var grass_edge_pixel := neighbor_tile_img.get_pixel(0, art / 2)
	print("    seam pixel on earth tile's east edge: %s" % earth_edge_pixel)
	print("    seam pixel on grass tile's west edge: %s" % grass_edge_pixel)
	print("    earth tile is a flat single color across its whole face: %s" % _is_flat(earth_tile_img))


func _is_flat(image: Image) -> bool:
	var first := image.get_pixel(0, 0)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y) != first:
				return false
	return true
