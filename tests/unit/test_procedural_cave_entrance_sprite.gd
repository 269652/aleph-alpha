extends GutTest

const ProceduralCaveEntranceSprite = preload("res://src/rendering/procedural_cave_entrance_sprite.gd")

var generator: ProceduralCaveEntranceSprite


func before_each():
	generator = ProceduralCaveEntranceSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := generator.generate_image(3)
	assert_eq(image.get_width(), ProceduralCaveEntranceSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralCaveEntranceSprite.SIZE.y)


func test_image_has_a_dark_opaque_center_and_transparent_corners():
	var image := generator.generate_image(3)
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var corner := image.get_pixel(0, 0)
	assert_gt(center.a, 0.0, "center should be opaque, reading as a real hole")
	assert_eq(corner.a, 0.0, "corners should stay transparent")


func test_generation_is_deterministic():
	var a := generator.generate_image(7)
	var b := generator.generate_image(7)
	assert_eq(a.get_pixel(4, 4), b.get_pixel(4, 4))
