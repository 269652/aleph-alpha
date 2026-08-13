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
