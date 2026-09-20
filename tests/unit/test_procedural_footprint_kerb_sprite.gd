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


# -- visible against every ground it can lie on ----------------------------
#
# "So the hitbox is visible" is the whole ask, and a kerb lies on three
# real grounds: the village's cobbles (a hall on its square), the worn
# earth yard of a plot on open ground, and -- where the yard dithers into
# it -- the grass beside the plot. A colour that reads against one and
# washes out on another is a border only some of the time, so the margin
# is measured rather than eyeballed.

## Measured off the real render tools/probe_village_render.gd produces,
## inside a cottage's own kerb: rgb(0.21, 0.29, 0.07). The open grass
## beside it reads rgb(0.22, 0.33, 0.06); this is the harder of the two
## because it is what the kerb's own dark band sits closest to.
const GRASS_BESIDE_A_PLOT := Color(0.22, 0.33, 0.06)


func _grounds() -> Array:
	return [
		{"name": "the village's cobbles", "color": TerrainRenderer.ROAD_COLOR},
		{"name": "a worn earth yard", "color": TerrainRenderer.EARTH_COLOR},
		{"name": "the grass beside a plot", "color": GRASS_BESIDE_A_PLOT},
	]


func test_the_kerb_stands_out_from_every_ground_it_can_lie_on():
	for ground in _grounds():
		assert_gt(
			kerb.contrast_over(ground["color"]),
			ProceduralFootprintKerbSprite.MIN_GROUND_CONTRAST,
			"a kerb washed out against %s is not a visible hitbox" % ground["name"]
		)


## The contrast is a property of the PIXELS the kerb really draws, not of
## a palette constant somebody could change without it -- recomputed here
## straight off the image, so the two cannot drift apart.
func test_that_contrast_is_measured_off_the_pixels_it_really_draws():
	var image := kerb.generate_image(Vector2i(1, 1))
	for ground in _grounds():
		var background: Color = ground["color"]
		var strongest := 0.0
		for y in image.get_height():
			for x in image.get_width():
				var drawn := image.get_pixel(x, y)
				if drawn.a <= 0.0:
					continue
				var over := Vector3(
					drawn.a * drawn.r + (1.0 - drawn.a) * background.r,
					drawn.a * drawn.g + (1.0 - drawn.a) * background.g,
					drawn.a * drawn.b + (1.0 - drawn.a) * background.b
				)
				strongest = maxf(
					strongest, (over - Vector3(background.r, background.g, background.b)).length()
				)
		assert_almost_eq(kerb.contrast_over(background), strongest, 0.0001, ground["name"])
