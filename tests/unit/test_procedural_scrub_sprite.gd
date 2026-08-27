extends GutTest

const ProceduralScrubSprite = preload("res://src/rendering/procedural_scrub_sprite.gd")

var sprite := ProceduralScrubSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := sprite.generate_image(1)
	assert_eq(image.get_width(), ProceduralScrubSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralScrubSprite.SIZE.y)


func test_background_corners_are_transparent():
	var image := sprite.generate_image(1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralScrubSprite.SIZE.x - 1, 0).a, 0.0)


## Scrub should read as dusty sage/olive, not the lush saturated green of
## tall grass -- so opaque pixels should be roughly balanced red/green with
## blue held distinctly lower, rather than green clearly dominating red.
func test_contains_sage_olive_dominant_blade_pixels():
	var image := sprite.generate_image(1)
	var sage_pixels := 0
	for y in ProceduralScrubSprite.SIZE.y:
		for x in ProceduralScrubSprite.SIZE.x:
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.g > c.b and c.r > c.b:
				sage_pixels += 1
	assert_gt(sage_pixels, 5)


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
# Every scrub tuft used to mint a brand new Texture2D per cell, uncached --
# unlike ProceduralTreeSprite's own _tree_texture_cache. Chunks aren't
# persisted on eviction (see EarthChunkManager's own doc comment), and a
# tuft's seed is derived from its cell, so a reloaded chunk asks for the exact
# same seed_value again; caching means that gets the exact same Texture2D
# back instead of a fresh repaint.

func test_the_same_seed_gets_its_texture_back_instead_of_redrawing_it():
	assert_same(sprite.generate_texture(1), sprite.generate_texture(1))


## The cache is shared across generator INSTANCES too -- each EarthChunkManager
## holds its own ProceduralScrubSprite, so a per-instance cache would still
## redraw once per instance.
func test_two_generators_of_one_seed_share_the_texture():
	assert_same(
		ProceduralScrubSprite.new().generate_texture(5),
		ProceduralScrubSprite.new().generate_texture(5)
	)


func test_a_different_seed_does_not_share_the_texture():
	assert_not_same(sprite.generate_texture(1), sprite.generate_texture(2))


func test_cached_texture_still_matches_a_freshly_drawn_one():
	assert_eq(
		sprite.generate_texture(3).get_image().get_data(), sprite.generate_image(3).get_data()
	)
