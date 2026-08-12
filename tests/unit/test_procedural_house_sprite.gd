extends GutTest

const ProceduralHouseSprite = preload("res://src/rendering/procedural_house_sprite.gd")

var generator := ProceduralHouseSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image(0)
	assert_eq(image.get_width(), ProceduralHouseSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralHouseSprite.SIZE.y)


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image(0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(ProceduralHouseSprite.SIZE.x / 2, ProceduralHouseSprite.SIZE.y - 2)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


func test_is_deterministic_for_the_same_seed():
	var a := generator.generate_image(9)
	var b := generator.generate_image(9)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_vary_the_wall_shade():
	var a := generator.generate_image(1)
	var b := generator.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


## A house should read as multi-toned (wall + roof + door, at minimum), not a
## single flat-colored block. 8-bit RGBA image storage quantizes stored
## colors slightly, so this checks each color's hue family (a tolerance
## band) rather than exact equality -- same technique as
## test_procedural_item_sprite.gd's campfire/furnace hue-family checks.
func _has_hue_family_pixel(image: Image, predicate: Callable) -> bool:
	for y in ProceduralHouseSprite.SIZE.y:
		for x in ProceduralHouseSprite.SIZE.x:
			if predicate.call(image.get_pixel(x, y)):
				return true
	return false


func test_has_both_a_wall_colored_pixel_and_a_roof_colored_pixel():
	var image := generator.generate_image(0)
	var is_wall := func(p: Color) -> bool: return p.r > 0.7 and p.g > 0.6 and p.b < 0.65
	var is_roof := func(p: Color) -> bool: return p.r > 0.4 and p.r < 0.7 and p.g < 0.35 and p.b < 0.3
	assert_true(_has_hue_family_pixel(image, is_wall), "expected at least one wall-colored pixel")
	assert_true(_has_hue_family_pixel(image, is_roof), "expected at least one roof-colored pixel")


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture(0)
	assert_eq(texture.get_width(), ProceduralHouseSprite.SIZE.x)
