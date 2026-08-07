extends GutTest

const ProceduralShoreDistanceSprite = preload("res://src/rendering/procedural_shore_distance_sprite.gd")

var generator := ProceduralShoreDistanceSprite.new()
const SIZE := ProceduralShoreDistanceSprite.SIZE


func test_deep_water_image_is_uniformly_far_from_shore():
	var image := generator.generate_deep_water_image()
	assert_eq(image.get_width(), SIZE)
	assert_eq(image.get_height(), SIZE)
	for y in SIZE:
		for x in SIZE:
			assert_almost_eq(image.get_pixel(x, y).r, 1.0, 0.01)


func test_land_edge_pixel_reads_near_zero_and_far_side_reads_near_one():
	var image := generator.generate_image([Vector2i(0, -1)])  # land to the north
	assert_lt(image.get_pixel(8, 0).r, 0.15, "row touching the land edge should read close to 0")
	assert_gt(image.get_pixel(8, SIZE - 1).r, 0.85, "row farthest from land should read close to 1")


func test_each_cardinal_direction_faces_its_own_edge():
	var north := generator.generate_image([Vector2i(0, -1)])
	var south := generator.generate_image([Vector2i(0, 1)])
	var west := generator.generate_image([Vector2i(-1, 0)])
	var east := generator.generate_image([Vector2i(1, 0)])
	assert_lt(north.get_pixel(8, 0).r, south.get_pixel(8, 0).r)
	assert_lt(south.get_pixel(8, SIZE - 1).r, north.get_pixel(8, SIZE - 1).r)
	assert_lt(west.get_pixel(0, 8).r, east.get_pixel(0, 8).r)
	assert_lt(east.get_pixel(SIZE - 1, 8).r, west.get_pixel(SIZE - 1, 8).r)


## Combining directions must take whichever edge is actually nearer at each
## pixel, not just the first one given -- proves the corner case a single
## direction alone can't express.
func test_two_land_directions_take_the_nearer_edge_at_each_pixel():
	var combo := generator.generate_image([Vector2i(0, -1), Vector2i(1, 0)])  # land north AND east
	var north_only := generator.generate_image([Vector2i(0, -1)])
	var point := Vector2i(12, 10)  # close to the east edge, far from the north edge
	assert_lt(
		combo.get_pixel(point.x, point.y).r, north_only.get_pixel(point.x, point.y).r,
		"combining directions should take whichever edge is actually nearer"
	)


func test_is_deterministic():
	var a := generator.generate_image([Vector2i(0, -1), Vector2i(-1, 0)])
	var b := generator.generate_image([Vector2i(0, -1), Vector2i(-1, 0)])
	assert_eq(a.get_data(), b.get_data())


func test_image_is_fully_opaque():
	var image := generator.generate_image([Vector2i(0, -1)])
	assert_eq(image.get_pixel(0, 0).a, 1.0)


func test_generate_texture_returns_an_image_texture_of_the_right_size():
	var texture := generator.generate_texture([Vector2i(0, -1)])
	assert_eq(texture.get_width(), SIZE)
