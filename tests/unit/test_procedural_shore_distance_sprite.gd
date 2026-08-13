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
	# Close to the east edge, far from the north edge -- expressed as
	# SIZE-relative fractions (not an absolute pixel pair) so the "which
	# edge is nearer" relationship this test depends on holds at any tile
	# resolution (see docs/concept/art_resolution.md).
	var point := Vector2i(int(SIZE * 0.75), int(SIZE * 0.625))
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


# -- multi-tile shore rings ----------------------------------------------------
#
# A single tile's own local gradient (0..1 within its own 16px) confines any
# shore-driven wave effect to a razor-thin band, too narrow to read as visible
## interference at screen scale (reported: "waves don't produce interference").
# Ring tiles extend shore influence out several tiles: ring 0 is the existing
# per-direction touching-tile, rings 1..RING_MAX-1 are flat "this whole tile
# is N tiles from shore" values, giving the wave pattern room to actually be
# seen spreading across multiple tiles near a coast.

func test_ring_image_is_flat_and_scaled_by_ring_index():
	var ring1 := generator.generate_ring_image(1, 4)
	var ring2 := generator.generate_ring_image(2, 4)
	for y in SIZE:
		for x in SIZE:
			assert_almost_eq(ring1.get_pixel(x, y).r, 0.25, 0.01)
			assert_almost_eq(ring2.get_pixel(x, y).r, 0.5, 0.01)


func test_ring_image_is_deterministic_and_opaque():
	var a := generator.generate_ring_image(2, 4)
	var b := generator.generate_ring_image(2, 4)
	assert_eq(a.get_data(), b.get_data())
	assert_eq(a.get_pixel(0, 0).a, 1.0)
