extends RefCounted

## Builds a small biome-colored Image centered on the player, one image pixel
## per world tile, reusing TerrainRenderer's biome palette so the minimap
## reads consistently with the main map. `biome_source` is duck-typed
## (anything exposing biome_at_global(x, y) -> String) rather than requiring
## a real EarthChunkManager, so this stays independently testable.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How many tiles around the player get sampled in each direction.
const SAMPLE_RADIUS_TILES := 40


func build_image(biome_source, center_tile: Vector2i) -> Image:
	var size := SAMPLE_RADIUS_TILES * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)

	for local_y in size:
		var global_y := center_tile.y - SAMPLE_RADIUS_TILES + local_y
		for local_x in size:
			var global_x := center_tile.x - SAMPLE_RADIUS_TILES + local_x
			var biome_name: String = biome_source.biome_at_global(global_x, global_y)
			image.set_pixel(local_x, local_y, _color_for_biome(biome_name))

	return image


func _color_for_biome(biome_name: String) -> Color:
	return TerrainRenderer.BIOME_COLORS.get(biome_name, Color(0.0, 0.0, 0.0, 0.0))
