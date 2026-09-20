extends GutTest

## The kerb drawn round a building's own plot -- see docs/concept/
## building.md, "The ground a building stands on, and the kerb round its
## plot". Reported live with a screenshot: "there should be some kind of
## border so the hitbox is visible".
##
## It is the footprint's own outline and nothing else: continuous all the
## way round (a gap is a hitbox edge you cannot see), transparent in the
## middle (the ground inside it is the one the kerb rule just chose, and
## painting over it would undo that fix with this one), and drawn at the
## same pixels-per-world-unit as everything else standing on the ground
## (docs/concept/art_resolution.md).

const ProceduralFootprintKerbSprite = preload("res://src/rendering/procedural_footprint_kerb_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var kerb: ProceduralFootprintKerbSprite


func before_each():
	kerb = ProceduralFootprintKerbSprite.new()


func test_the_kerb_is_drawn_at_the_same_detail_per_world_unit_as_the_ground():
	var image := kerb.generate_image(Vector2i(2, 2))
	assert_eq(image.get_width(), 2 * TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), 2 * TerrainRenderer.ART_TILE_SIZE)


func test_the_kerb_covers_exactly_the_footprints_own_world_rect():
	var texture := kerb.footprint_texture(Vector2i(4, 3), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(texture.get_width(), 4 * TerrainRenderer.ART_TILE_SIZE, "as wide as the footprint, no wider")
	assert_eq(texture.get_height(), 3 * TerrainRenderer.ART_TILE_SIZE, "as tall as the footprint -- it lies on the ground")


## Every pixel of the outermost ring, all four sides, corners included: a
## hitbox is only visible where its edge is actually drawn, and a joint
## between two kerb stones must not read as a hole in the wall.
func test_the_kerb_outlines_the_whole_footprint_with_no_gaps():
	var image := kerb.generate_image(Vector2i(3, 2))
	var width := image.get_width()
	var height := image.get_height()
	for x in width:
		assert_gt(image.get_pixel(x, 0).a, 0.0, "top edge at x=%d" % x)
		assert_gt(image.get_pixel(x, height - 1).a, 0.0, "bottom edge at x=%d" % x)
	for y in height:
		assert_gt(image.get_pixel(0, y).a, 0.0, "left edge at y=%d" % y)
		assert_gt(image.get_pixel(width - 1, y).a, 0.0, "right edge at y=%d" % y)


## The whole point of the ground rule this kerb encloses is that a
## building shows the ground it stands on -- a filled plate would hide it.
func test_the_kerb_never_paints_over_the_ground_it_encloses():
	var image := kerb.generate_image(Vector2i(3, 2))
	var band := ProceduralFootprintKerbSprite.BAND_PIXELS
	for y in range(band, image.get_height() - band):
		for x in range(band, image.get_width() - band):
			assert_eq(image.get_pixel(x, y).a, 0.0, "inside the plot at (%d,%d)" % [x, y])


## Laid stones, not a debug rectangle: the edge carries a joint every few
## pixels and an inner line, so more than one tone appears in the band.
func test_the_kerb_reads_as_laid_stones_rather_than_one_flat_line():
	var image := kerb.generate_image(Vector2i(2, 2))
	var tones := {}
	for x in image.get_width():
		for y in ProceduralFootprintKerbSprite.BAND_PIXELS:
			tones[image.get_pixel(x, y)] = true
	assert_gt(tones.size(), 1, "one flat tone all the way round is a debug box, not a kerb")


func test_the_kerb_is_the_same_drawing_every_time():
	var first := kerb.generate_image(Vector2i(2, 2))
	var second := ProceduralFootprintKerbSprite.new().generate_image(Vector2i(2, 2))
	assert_eq(first.get_data(), second.get_data())


## A one-tile placeable is still a real footprint; the kerb must not fold
## in on itself or vanish when both bands meet.
func test_a_single_tile_footprint_still_gets_a_whole_kerb():
	var image := kerb.generate_image(Vector2i(1, 1))
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	for x in image.get_width():
		assert_gt(image.get_pixel(x, 0).a, 0.0, "top edge at x=%d" % x)
