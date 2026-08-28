extends GutTest

## MountainVeinSprite: a mineral-colored streak oriented along the local
## slope-facing direction (aspect), replacing the round ore-boulder decal a
## mountain vein used to draw (see docs/concept/terrain_relief.md's
## "Mountain ore" section and mountain_vein_sprite.gd's own doc comment).

const MountainVeinSprite = preload("res://src/rendering/mountain_vein_sprite.gd")
const ProceduralOreSprite = preload("res://src/rendering/procedural_ore_sprite.gd")

var vein := MountainVeinSprite.new()


func _colored_pixels(image: Image) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				pixels.append(Vector2i(x, y))
	return pixels


func _bounds(pixels: Array[Vector2i]) -> Dictionary:
	var min_x := 999
	var max_x := -999
	var min_y := 999
	var max_y := -999
	for p in pixels:
		min_x = mini(min_x, p.x)
		max_x = maxi(max_x, p.x)
		min_y = mini(min_y, p.y)
		max_y = maxi(max_y, p.y)
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


func test_returns_an_image_of_exactly_procedural_ore_sprites_size():
	var image := vein.generate_image("iron", 1, 0.0)
	assert_eq(image.get_width(), ProceduralOreSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralOreSprite.SIZE.y)


## aspect=0 is due north, which this project's screen space renders as
## straight up -- see mountain_vein_sprite.gd's own doc comment on the
## sin/-cos conversion. A north-facing vein should therefore be a narrow
## VERTICAL strip (x tightly bunched near the centerline, y spanning most
## of the canvas), and the four corners -- far from that strip in every
## direction -- must stay untouched.
func test_north_facing_streak_runs_along_the_vertical_centerline():
	var image := vein.generate_image("iron", 7, 0.0)
	var pixels := _colored_pixels(image)
	assert_gt(pixels.size(), 0, "expected a real drawn streak, not an empty image")

	var b := _bounds(pixels)
	assert_lt(b["max_x"] - b["min_x"], 10, "a north-facing vein should stay narrow across x")
	assert_gt(b["max_y"] - b["min_y"], 20, "a north-facing vein should run most of the canvas height")

	for corner in [Vector2i(0, 0), Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31)]:
		assert_eq(image.get_pixel(corner.x, corner.y).a, 0.0, "canvas corners must stay transparent")


## aspect=90 is due east -- straight right on screen -- so the same streak
## should now run HORIZONTALLY instead: orientation actually rotates with
## aspect, not a fixed shape.
func test_east_facing_streak_runs_along_the_horizontal_centerline():
	var image := vein.generate_image("iron", 7, 90.0)
	var pixels := _colored_pixels(image)
	assert_gt(pixels.size(), 0)

	var b := _bounds(pixels)
	assert_lt(b["max_y"] - b["min_y"], 10, "an east-facing vein should stay narrow across y")
	assert_gt(b["max_x"] - b["min_x"], 20, "an east-facing vein should run most of the canvas width")


func test_colored_pixel_matches_the_ore_types_signature_fleck_color():
	var image := vein.generate_image("iron", 3, 45.0)
	var pixels := _colored_pixels(image)
	assert_gt(pixels.size(), 0)
	var sample := image.get_pixel(pixels[0].x, pixels[0].y)
	var expected: Color = ProceduralOreSprite.FLECK_COLOR["iron"]
	assert_almost_eq(sample.r, expected.r, 0.01)
	assert_almost_eq(sample.g, expected.g, 0.01)
	assert_almost_eq(sample.b, expected.b, 0.01)


## Mountain veins only ever spawn on real slopes (see
## MountainOrePlacement.MIN_SLOPE_FOR_VEINS_DEG), so aspect_deg's -1.0
## "undefined on flat ground" sentinel (see terrain_relief.gd's
## aspect_degrees_from_gradient) is defensive only -- but it must still
## produce a real image, not a crash or a NaN-poisoned/empty one.
func test_undefined_aspect_sentinel_does_not_crash_and_still_draws_something():
	var image := vein.generate_image("iron", 5, -1.0)
	assert_not_null(image)
	assert_gt(
		_colored_pixels(image).size(), 0, "the flat-ground sentinel must still fall back to a real drawn streak"
	)


## Seeded jitter (see mountain_vein_sprite.gd's own doc comment) so two
## veins of the same ore type/orientation don't render as the identical
## rigid line.
func test_different_seeds_produce_different_streaks_not_an_identical_rigid_line():
	var a := vein.generate_image("iron", 11, 0.0)
	var b := vein.generate_image("iron", 23, 0.0)
	assert_ne(a.get_data(), b.get_data())


func test_generate_texture_wraps_generate_image_as_an_image_texture():
	var texture := vein.generate_texture("copper", 9, 180.0)
	assert_true(texture is ImageTexture)
	assert_eq(texture.get_width(), ProceduralOreSprite.SIZE.x)
	assert_eq(texture.get_height(), ProceduralOreSprite.SIZE.y)
