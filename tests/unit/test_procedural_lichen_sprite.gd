extends GutTest

const ProceduralLichenSprite = preload("res://src/rendering/procedural_lichen_sprite.gd")

var sprite := ProceduralLichenSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := sprite.generate_image(1)
	assert_eq(image.get_width(), ProceduralLichenSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralLichenSprite.SIZE.y)


func test_background_corners_are_transparent():
	var image := sprite.generate_image(1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralLichenSprite.SIZE.x - 1, 0).a, 0.0)


## Lichen should read as pale grey-green/mossy, not vibrant -- opaque pixels
## should have red/green/blue components all fairly close together (low
## saturation) rather than one channel clearly dominating.
func test_contains_muted_grey_green_dominant_blade_pixels():
	var image := sprite.generate_image(1)
	var muted_pixels := 0
	for y in ProceduralLichenSprite.SIZE.y:
		for x in ProceduralLichenSprite.SIZE.x:
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.g >= c.r and c.g >= c.b and (c.g - c.b) < 0.2:
				muted_pixels += 1
	assert_gt(muted_pixels, 5)


func test_is_deterministic_for_the_same_seed():
	var a := sprite.generate_image(42)
	var b := sprite.generate_image(42)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_tufts():
	var a := sprite.generate_image(1)
	var b := sprite.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := sprite.generate_texture(1)
	assert_true(texture is ImageTexture)


# -- texture cache ------------------------------------------------------------
#
# Every lichen patch used to mint a brand new Texture2D per cell, uncached --
# unlike ProceduralTreeSprite's own _tree_texture_cache. Chunks aren't
# persisted on eviction (see EarthChunkManager's own doc comment), and a
# patch's seed is derived from its cell, so a reloaded chunk asks for the
# exact same seed_value again; caching means that gets the exact same
# Texture2D back instead of a fresh repaint.

func test_the_same_seed_gets_its_texture_back_instead_of_redrawing_it():
	assert_same(sprite.generate_texture(1), sprite.generate_texture(1))


## The cache is shared across generator INSTANCES too -- each EarthChunkManager
## holds its own ProceduralLichenSprite, so a per-instance cache would still
## redraw once per instance.
func test_two_generators_of_one_seed_share_the_texture():
	assert_same(
		ProceduralLichenSprite.new().generate_texture(5),
		ProceduralLichenSprite.new().generate_texture(5)
	)


func test_a_different_seed_does_not_share_the_texture():
	assert_not_same(sprite.generate_texture(1), sprite.generate_texture(2))


func test_cached_texture_still_matches_a_freshly_drawn_one():
	assert_eq(
		sprite.generate_texture(3).get_image().get_data(), sprite.generate_image(3).get_data()
	)
