extends GutTest

const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")

var generator: ProceduralOreSprite


func before_each():
	generator = ProceduralOreSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := generator.generate_image("iron", 42)
	assert_eq(image.get_width(), ProceduralOreSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralOreSprite.SIZE.y)


func test_image_has_transparent_background_and_opaque_boulder():
	var image := generator.generate_image("iron", 42)
	var opaque := 0
	var transparent := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
			else:
				transparent += 1
	assert_gt(opaque, 20)
	assert_gt(transparent, 20)


func test_same_seed_and_type_produce_identical_image():
	var a := generator.generate_image("copper", 123)
	var b := generator.generate_image("copper", 123)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_images():
	var a := generator.generate_image("iron", 1)
	var b := generator.generate_image("iron", 2)
	assert_ne(a.get_data(), b.get_data())


func _average_fleck_color(ore_type: String) -> Color:
	# Sum pixels that are strongly non-grey (the colored ore flecks).
	var image := generator.generate_image(ore_type, 42)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			var hi: float = max(max(c.r, c.g), c.b)
			var spread: float = hi - min(min(c.r, c.g), c.b)
			# A fleck is either strongly hued (iron/copper) or much darker than
			# the boulder greys (coal, near-black).
			if spread > 0.12 or hi < 0.18:
				r += c.r
				g += c.g
				b += c.b
				n += 1
	assert_gt(n, 0, "expected some colored flecks for %s" % ore_type)
	return Color(r / n, g / n, b / n)


func test_each_ore_type_has_distinct_fleck_color():
	var iron := _average_fleck_color("iron")
	var copper := _average_fleck_color("copper")
	var coal := _average_fleck_color("coal")
	var iron_v := Vector3(iron.r, iron.g, iron.b)
	var copper_v := Vector3(copper.r, copper.g, copper.b)
	var coal_v := Vector3(coal.r, coal.g, coal.b)
	assert_gt(iron_v.distance_to(copper_v), 0.15, "iron vs copper flecks too similar")
	assert_gt(iron_v.distance_to(coal_v), 0.15, "iron vs coal flecks too similar")
	assert_gt(copper_v.distance_to(coal_v), 0.15, "copper vs coal flecks too similar")


func test_iron_flecks_are_orange_brown():
	var c := _average_fleck_color("iron")
	assert_gt(c.r, c.b, "iron flecks should be warm (red > blue)")


func test_copper_flecks_are_teal_green():
	var c := _average_fleck_color("copper")
	assert_gt(c.g, c.r, "copper flecks should be green-dominant")


func test_generate_texture_wraps_image():
	var texture := generator.generate_texture("iron", 42)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralOreSprite.SIZE.x)
