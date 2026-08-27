extends RefCounted

## Builds a small biome-colored Image centered on the player, one image pixel
## per world tile, reusing TerrainRenderer's biome palette so the minimap
## reads consistently with the main map. `biome_source` is duck-typed
## (anything exposing biome_at_global(x, y) -> String) rather than requiring
## a real EarthChunkManager, so this stays independently testable.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

## How many tiles around the player get sampled in each direction.
const SAMPLE_RADIUS_TILES := 40

## The caller (world.gd's _update_minimap) already time-gates rebuilds to at
## most once/second, but the player is often still standing on the same tile
## when that gate opens (fishing, crafting, admiring the view) -- so beyond
## the time gate, also skip re-sampling all size*size tiles when the center
## tile hasn't actually moved since the last build, and just hand back the
## previously-built image.
var _has_built_before := false
var _last_built_tile := Vector2i.ZERO
var _last_built_image: Image


func build_image(biome_source, center_tile: Vector2i) -> Image:
	if _has_built_before and center_tile == _last_built_tile:
		return _last_built_image

	var size := SAMPLE_RADIUS_TILES * 2 + 1

	# FORMAT_RGBA8 packs 4 bytes per pixel, R/G/B/A in that order, row-major --
	# filling that buffer directly and uploading it in one Image.set_data()
	# call is dramatically faster in GDScript than size*size individual
	# set_pixel() calls (each of which round-trips through the engine).
	var bytes := PackedByteArray()
	bytes.resize(size * size * 4)

	for local_y in size:
		var global_y := center_tile.y - SAMPLE_RADIUS_TILES + local_y
		var row_offset := local_y * size
		for local_x in size:
			var global_x := center_tile.x - SAMPLE_RADIUS_TILES + local_x
			var biome_name: String = biome_source.biome_at_global(global_x, global_y)
			var color := _color_for_biome(biome_name)
			var idx := (row_offset + local_x) * 4
			bytes[idx] = _channel_byte(color.r)
			bytes[idx + 1] = _channel_byte(color.g)
			bytes[idx + 2] = _channel_byte(color.b)
			bytes[idx + 3] = _channel_byte(color.a)

	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, bytes)

	_has_built_before = true
	_last_built_tile = center_tile
	_last_built_image = image
	return image


## Mirrors Image.set_pixel()'s own float-to-byte quantization for FORMAT_RGBA8
## (truncate towards zero, clamped to 0..255) so bulk-writing bytes here
## produces a byte-for-byte identical image to the old per-pixel set_pixel()
## loop -- confirmed against the real engine, not assumed: Godot's own
## quantization truncates rather than rounds to nearest (e.g. 0.651*255 =
## 165.99... becomes byte 165, not 166), see
## test_pixel_bytes_exactly_match_the_engines_own_set_pixel_quantization.
func _channel_byte(channel_value: float) -> int:
	return clampi(int(channel_value * 255.0), 0, 255)


func _color_for_biome(biome_name: String) -> Color:
	return TerrainRenderer.BIOME_COLORS.get(biome_name, Color(0.0, 0.0, 0.0, 0.0))
