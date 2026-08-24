extends GutTest

const CircularPondSprite = preload("res://src/rendering/circular_pond_sprite.gd")


func test_center_pixel_is_deep_water_and_opaque():
	var image := CircularPondSprite.generate_image()
	var center := image.get_width() / 2
	var pixel := image.get_pixel(center, center)
	assert_almost_eq(pixel.r, 1.0, 0.05)
	assert_almost_eq(pixel.a, 1.0, 0.001)


func test_a_pixel_near_the_rim_is_close_to_shore_but_still_opaque():
	var image := CircularPondSprite.generate_image()
	var size := image.get_width()
	var center := Vector2(size - 1, size - 1) * 0.5
	var max_radius := center.x  # the INSCRIBED radius -- see generate_image's own comment on why
	# 95% of the way out along a cardinal axis -- clearly inside the
	# circle, but close to its rim.
	var point := center + Vector2(max_radius * 0.95, 0)
	var pixel := image.get_pixel(int(round(point.x)), int(round(point.y)))
	assert_lt(pixel.r, 0.2)
	assert_almost_eq(pixel.a, 1.0, 0.001)


func test_a_corner_pixel_outside_the_inscribed_circle_is_transparent():
	var image := CircularPondSprite.generate_image()
	var pixel := image.get_pixel(0, 0)
	assert_eq(pixel.a, 0.0)


func test_shore_distance_increases_toward_the_centre():
	var image := CircularPondSprite.generate_image()
	var size := image.get_width()
	var center := Vector2(size - 1, size - 1) * 0.5
	var max_radius := center.x  # the INSCRIBED radius -- see generate_image's own comment on why
	var near_center := image.get_pixel(int(center.x), int(center.y))
	var near_point := center + Vector2(max_radius * 0.8, 0)
	var near_rim := image.get_pixel(int(round(near_point.x)), int(round(near_point.y)))
	assert_gt(near_center.r, near_rim.r)


func test_generate_texture_returns_an_image_texture_of_the_same_size():
	var texture := CircularPondSprite.generate_texture()
	var image := CircularPondSprite.generate_image()
	# Texture2D.get_size() returns Vector2, Image.get_size() returns
	# Vector2i -- different types, so compare components, not the whole
	# vector.
	assert_eq(texture.get_size().x, float(image.get_size().x))
	assert_eq(texture.get_size().y, float(image.get_size().y))
