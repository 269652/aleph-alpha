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
