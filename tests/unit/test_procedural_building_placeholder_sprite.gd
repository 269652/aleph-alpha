extends GutTest

## ProceduralBuildingPlaceholderSprite: a roof-over-walls box drawn for a
## building whose real sheet has not landed yet (docs/concept/building.md
## "Asset contract") -- so the whole-building system is playable and
## testable without art. Deterministic, same PixelPalette house style as
## every other procedural generator here.

const ProceduralBuildingPlaceholderSprite = preload("res://src/rendering/procedural_building_placeholder_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var generator: ProceduralBuildingPlaceholderSprite


func before_each():
	generator = ProceduralBuildingPlaceholderSprite.new()


## Drawn at art resolution, as wide as the footprint and one extra tile
## tall -- a roof rises above the footprint the way every real sheet's
## building does.
func test_image_is_footprint_wide_and_one_tile_taller_than_the_footprint():
	var image := generator.generate_image(Vector2i(3, 2), 7)
	assert_eq(image.get_width(), 3 * TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), (2 + 1) * TerrainRenderer.ART_TILE_SIZE)


func test_image_is_mostly_opaque_building():
	var image := generator.generate_image(Vector2i(2, 2), 1)
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.99:
				opaque += 1
	assert_gt(opaque, image.get_width() * image.get_height() / 2, "a placeholder is a solid box, not a smudge")


## The roof band (top) reads differently from the wall band (bottom) --
## otherwise the box is a flat rectangle, not a building.
func test_roof_and_wall_bands_are_visually_distinct():
	var image := generator.generate_image(Vector2i(2, 2), 3)
	var mid := image.get_width() / 2
	var roof := image.get_pixel(mid, TerrainRenderer.ART_TILE_SIZE / 2)
	var wall := image.get_pixel(mid, image.get_height() - TerrainRenderer.ART_TILE_SIZE / 2)
	assert_ne(roof, wall)


func test_image_is_deterministic_per_seed_and_differs_per_footprint():
	var a := generator.generate_image(Vector2i(2, 2), 5)
	var b := generator.generate_image(Vector2i(2, 2), 5)
	assert_eq(a.get_data(), b.get_data())
	var wide := generator.generate_image(Vector2i(4, 3), 5)
	assert_ne(wide.get_size(), a.get_size())


## The placeholder is scaled to its world footprint -- drawn INSIDE the
## plot since BuildingCatalog.PLOT_MARGIN_SHARE. What this test is really
## guarding is the SHAPE: three wide by (two deep plus a roof) tall, so the
## box still reads as a building on that ground whatever it is scaled to.
func test_footprint_texture_scales_to_the_world_footprint_width():
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	var texture := generator.footprint_texture(Vector2i(3, 2), 9, 16)
	assert_eq(texture.get_width(), int(round(16.0 * BuildingCatalog.drawn_plot_width_tiles(3))))
	assert_almost_eq(
		float(texture.get_height()) / float(texture.get_width()),
		float((2 + 1) * 16) / float(3 * 16),
		0.02,
		"3 wide x (2 + 1 roof) tall"
	)


## A building with no art yet stands in exactly as much of its plot as one
## with art does -- otherwise dropping a sheet in would visibly move the
## house, and a street of half-arted buildings would have two different
## rhythms in it. Both read BuildingCatalog.drawn_plot_width_tiles.
func test_a_placeholder_covers_the_same_plot_a_real_sheet_would():
	var BuildingCatalog = load("res://src/gameplay/building_catalog.gd")
	for footprint_width in [1, 2, 3]:
		var texture: ImageTexture = generator.footprint_texture(Vector2i(footprint_width, 2), 7, 16)
		assert_eq(
			texture.get_width(),
			int(round(16.0 * BuildingCatalog.drawn_plot_width_tiles(footprint_width))),
			"a %d-tile placeholder does not stand where a %d-tile building would"
			% [footprint_width, footprint_width]
		)
		assert_lt(texture.get_width(), footprint_width * 16, "the placeholder fills its whole plot")
