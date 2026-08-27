extends GutTest

const MinimapRenderer = preload("res://src/rendering/minimap_renderer.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var renderer: MinimapRenderer


## A tiny stand-in for EarthChunkManager: duck-types biome_at_global(x, y) so
## these tests don't need a real chunk manager or real Earth elevation data.
class StubBiomeSource:
	var _biome_by_tile: Dictionary  # Vector2i -> String
	var _default_biome: String

	func _init(default_biome: String, overrides: Dictionary = {}) -> void:
		_default_biome = default_biome
		_biome_by_tile = overrides

	func biome_at_global(x: int, y: int) -> String:
		return _biome_by_tile.get(Vector2i(x, y), _default_biome)


## Same duck-typed stub as above, but counts biome_at_global() calls so a
## test can prove a rebuild was (or was not) actually attempted, rather than
## just checking the returned image looks right.
class CountingBiomeSource extends StubBiomeSource:
	var call_count := 0

	func biome_at_global(x: int, y: int) -> String:
		call_count += 1
		return super.biome_at_global(x, y)


func before_each():
	renderer = MinimapRenderer.new()


func test_image_size_matches_two_times_the_sample_radius_plus_one():
	var source := StubBiomeSource.new("grassland")
	var image := renderer.build_image(source, Vector2i(0, 0))
	var expected_size := MinimapRenderer.SAMPLE_RADIUS_TILES * 2 + 1
	assert_eq(image.get_width(), expected_size)
	assert_eq(image.get_height(), expected_size)


## FORMAT_RGBA8 quantizes to 8 bits per channel, so a round-tripped color is
## only ever accurate to about 1/255 -- exact float equality would always fail.
func _assert_color_almost_eq(actual: Color, expected: Color) -> void:
	assert_almost_eq(actual.r, expected.r, 0.005)
	assert_almost_eq(actual.g, expected.g, 0.005)
	assert_almost_eq(actual.b, expected.b, 0.005)
	assert_almost_eq(actual.a, expected.a, 0.005)


func test_center_pixel_reflects_the_biome_at_the_center_tile():
	var center := Vector2i(500, 500)
	var source := StubBiomeSource.new("ocean", {center: "desert"})
	var image := renderer.build_image(source, center)
	var mid := MinimapRenderer.SAMPLE_RADIUS_TILES
	_assert_color_almost_eq(image.get_pixel(mid, mid), TerrainRenderer.BIOME_COLORS["desert"])


func test_uniform_biome_produces_a_uniform_image():
	var source := StubBiomeSource.new("forest")
	var image := renderer.build_image(source, Vector2i(0, 0))
	var expected: Color = TerrainRenderer.BIOME_COLORS["forest"]
	_assert_color_almost_eq(image.get_pixel(0, 0), expected)
	_assert_color_almost_eq(image.get_pixel(image.get_width() - 1, image.get_height() - 1), expected)


func test_unloaded_tiles_render_as_fully_transparent():
	var source := StubBiomeSource.new("")  # EarthChunkManager returns "" for unloaded tiles
	var image := renderer.build_image(source, Vector2i(0, 0))
	assert_eq(image.get_pixel(0, 0).a, 0.0)


## world.gd's caller already time-gates rebuilds to at most once/second, but
## the player often stands still for many of those ticks (fishing, crafting,
## just admiring the view) -- each of which used to re-sample all 6561 tiles
## for a result identical to the one already on screen. Skipping the rebuild
## when the player's tile hasn't moved since the last build avoids that.
func test_a_second_build_at_the_same_tile_skips_the_expensive_rebuild():
	var source := CountingBiomeSource.new("grassland")
	var tile := Vector2i(10, 10)

	renderer.build_image(source, tile)
	var calls_after_first_build := source.call_count
	assert_gt(calls_after_first_build, 0, "sanity check: the first build should sample biomes")

	renderer.build_image(source, tile)
	assert_eq(
		source.call_count, calls_after_first_build,
		"a second build at the same tile should not re-sample any biomes"
	)


## The skip must be keyed on the tile actually changing, not just "already
## built once" -- otherwise the minimap would freeze the first time it's
## drawn and never update again as the player walks around.
func test_a_build_at_a_different_tile_still_rebuilds():
	var source := CountingBiomeSource.new("grassland")

	renderer.build_image(source, Vector2i(10, 10))
	var calls_after_first_build := source.call_count

	renderer.build_image(source, Vector2i(11, 10))
	assert_gt(
		source.call_count, calls_after_first_build,
		"moving to a new tile should trigger a fresh sample"
	)


## build_image() bulk-writes raw bytes instead of calling Image.set_pixel()
## per pixel (for performance), so it must reproduce Godot's own float-to-byte
## quantization exactly -- otherwise every biome color is off by up to 1/255,
## silently, in a way the tolerant _assert_color_almost_eq() above (0.005 ==
## ~1.3/255) is too loose to ever catch. Build an oracle image the slow way,
## with the engine's real Image.set_pixel(), and compare byte-for-byte rather
## than pinning specific numbers (which would rot if BIOME_COLORS changes).
func test_pixel_bytes_exactly_match_the_engines_own_set_pixel_quantization():
	var tile_x := 0
	for biome_name in TerrainRenderer.BIOME_COLORS:
		var color: Color = TerrainRenderer.BIOME_COLORS[biome_name]
		var oracle := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		oracle.set_pixel(0, 0, color)
		var expected := oracle.get_pixel(0, 0)

		var source := StubBiomeSource.new(biome_name)
		# A distinct tile per biome -- build_image() correctly skips rebuilding
		# (see the cache test above) when the tile is unchanged, which would
		# otherwise make every iteration after the first see the first
		# biome's cached image instead of its own.
		var image := renderer.build_image(source, Vector2i(tile_x, 0))
		tile_x += 1
		var actual := image.get_pixel(0, 0)

		assert_eq(
			actual, expected,
			"biome '%s': bulk-written pixel %s must exactly match Image.set_pixel()'s own quantization %s" % [biome_name, actual, expected]
		)
