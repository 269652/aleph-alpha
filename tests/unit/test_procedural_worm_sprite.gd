extends GutTest

## Deterministic pixel art for a surfaced earthworm (see
## docs/concept/soil_fauna.md) -- what a player actually sees lying on wet
## grass, and what a robin lands on.

const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")

var generator := ProceduralWormSprite.new()


## The bounding box of everything actually painted.
func _painted_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= 0.0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func test_image_has_the_expected_size():
	var image := generator.generate_image(0)
	assert_eq(image.get_width(), ProceduralWormSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralWormSprite.SIZE.y)


func test_has_transparent_corners():
	var image := generator.generate_image(3)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralWormSprite.SIZE.x - 1, 0).a, 0.0)
	assert_eq(image.get_pixel(0, ProceduralWormSprite.SIZE.y - 1).a, 0.0)


func test_actually_paints_a_body():
	var bounds := _painted_bounds(generator.generate_image(3))
	assert_gt(bounds.size.x, 0)
	assert_gt(bounds.size.y, 0)


func test_is_deterministic_for_the_same_seed():
	assert_eq(generator.generate_image(11).get_data(), generator.generate_image(11).get_data())


func test_different_seeds_give_different_worms():
	assert_ne(generator.generate_image(1).get_data(), generator.generate_image(2).get_data())


## A worm reads as a worm because it is long and thin, not because of colour.
func test_a_worm_is_much_longer_than_it_is_thick():
	for seed_value in range(8):
		var bounds := _painted_bounds(generator.generate_image(seed_value))
		assert_gt(
			float(bounds.size.x) / float(bounds.size.y), 2.0,
			"seed %d should be a long thin body" % seed_value
		)


## An unbroken body: a gap mid-worm reads as two specks, not one animal.
func test_the_body_is_continuous_along_its_length():
	for seed_value in range(8):
		var image := generator.generate_image(seed_value)
		var bounds := _painted_bounds(image)
		for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
			var painted := false
			for y in image.get_height():
				if image.get_pixel(x, y).a > 0.0:
					painted = true
					break
			assert_true(painted, "seed %d has a gap at column %d" % [seed_value, x])


func test_the_body_curves_rather_than_lying_perfectly_straight():
	var curvy := 0
	for seed_value in range(8):
		if _painted_bounds(generator.generate_image(seed_value)).size.y > 2:
			curvy += 1
	assert_gt(curvy, 0, "worms should lie in a curve, not as a ruled line")


func test_generates_a_texture_matching_its_image():
	assert_eq(
		generator.generate_texture(4).get_image().get_data(),
		generator.generate_image(4).get_data()
	)


# -- world size, kept independent of the art canvas -------------------------
#
# This project has twice shipped sprites that changed size on screen because a
# world scale was derived from canvas dimensions (see ProceduralFlowerSprite's
# doc comment). The worm's world footprint is stated in TILES and the scale is
# derived to hit it, so raising SIZE for detail cannot change how big a worm
# looks.

func test_the_world_length_is_what_the_constant_says_regardless_of_canvas():
	assert_almost_eq(
		float(ProceduralWormSprite.SIZE.x) * ProceduralWormSprite.world_scale(),
		ProceduralWormSprite.WORLD_LENGTH_TILES * ProceduralWormSprite.TILE_SIZE,
		0.001
	)


func test_a_worm_is_smaller_than_a_tile():
	assert_lt(
		float(ProceduralWormSprite.SIZE.x) * ProceduralWormSprite.world_scale(),
		ProceduralWormSprite.TILE_SIZE,
		"a worm lies within its own tile"
	)


## A worm is a small thing on the ground next to the flowers it lies among.
##
## Compared against a real species' drawn height rather than a shared flower
## constant: flowers are sized per species against the player now (see
## FlowerSpecies "On stature"), and there is no one height they all share.
##
## Measured against a TULIP rather than the shortest flower in the roster. A
## crocus is 10cm and an earthworm is about 10cm, so they are genuinely the
## same size in life -- asking a worm to be shorter than a crocus is asking
## for something that is not true, and was only ever true while every flower
## shared one invented height.
func test_a_worm_is_shorter_than_a_flower_is_tall():
	var tulip_tiles: float = (
		ProceduralFlowerSprite.world_height_px("tulip") / ProceduralFlowerSprite.TILE_SIZE
	)
	assert_lt(ProceduralWormSprite.WORLD_LENGTH_TILES, tulip_tiles)


func test_the_world_scale_is_positive():
	assert_gt(ProceduralWormSprite.world_scale(), 0.0)


# -- how big a worm is -------------------------------------------------------

## A worm is about as long as a crocus is tall, because both are about ten
## centimetres.
##
## It was sized by eye at 0.55 tiles, which was set when flowers still shared
## one invented height; once flowers were pinned to the player's own scale the
## worm was suddenly longer than several of them and read as a snake.
func test_a_worm_is_about_as_long_as_a_crocus_is_tall():
	var crocus_tiles: float = (
		ProceduralFlowerSprite.world_height_px("crocus") / ProceduralFlowerSprite.TILE_SIZE
	)
	assert_almost_eq(
		ProceduralWormSprite.WORLD_LENGTH_TILES, crocus_tiles, crocus_tiles * 0.35,
		"a worm and a crocus are the same size in life"
	)


## ...and well under the player's foot. A worm you notice from across the
## meadow is not a worm.
func test_a_worm_is_a_small_thing_beside_the_player():
	var length_px: float = (
		ProceduralWormSprite.WORLD_LENGTH_TILES * ProceduralWormSprite.TILE_SIZE
	)
	assert_lt(
		length_px / ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX, 0.35,
		"a worm should be ankle-scale, not knee-scale"
	)
