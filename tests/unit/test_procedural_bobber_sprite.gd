extends GutTest

const ProceduralBobberSprite = preload("res://src/rendering/procedural_bobber_sprite.gd")

var generator := ProceduralBobberSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image()
	assert_eq(image.get_width(), ProceduralBobberSprite.SIZE)
	assert_eq(image.get_height(), ProceduralBobberSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image()
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralBobberSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image()
	var b := generator.generate_image()
	assert_eq(a.get_data(), b.get_data())


## The classic look: a red top half and a white bottom half, not one flat color.
func test_has_both_a_red_top_and_a_white_bottom():
	var image := generator.generate_image()
	var top_red := false
	var bottom_white := false
	for y in ProceduralBobberSprite.SIZE:
		for x in ProceduralBobberSprite.SIZE:
			var p := image.get_pixel(x, y)
			if p.a == 0.0:
				continue
			if p.r > 0.6 and p.g < 0.35 and y < ProceduralBobberSprite.SIZE / 2:
				top_red = true
			if p.r > 0.8 and p.g > 0.8 and p.b > 0.8 and y >= ProceduralBobberSprite.SIZE / 2:
				bottom_white = true
	assert_true(top_red, "expected a red pixel in the top half")
	assert_true(bottom_white, "expected a white pixel in the bottom half")


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture()
	assert_eq(texture.get_width(), ProceduralBobberSprite.SIZE)
