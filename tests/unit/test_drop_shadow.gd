extends GutTest

## DropShadow: the shared soft-ellipse ground shadow under trees, creatures,
## stones, and the player. Without shadows every entity floats on the ground
## plane; a simple contact shadow is the single cheapest grounding cue in
## top-down pixel art.

const DropShadow = preload("res://src/rendering/drop_shadow.gd")

var shadow_maker := DropShadow.new()


func test_make_shadow_returns_a_sprite_drawn_behind_its_parent():
	var shadow := shadow_maker.make_shadow(16, 8.0)
	assert_true(shadow is Sprite2D)
	assert_true(shadow.show_behind_parent, "shadow must render under the entity, not over it")
	assert_eq(shadow.position, Vector2(0, 8.0))
	shadow.free()


func test_shadow_texture_is_a_flattened_ellipse():
	var shadow := shadow_maker.make_shadow(16, 0.0)
	var image: Image = shadow.texture.get_image()
	assert_eq(image.get_width(), 16)
	assert_lt(image.get_height(), image.get_width(), "a ground shadow is wider than tall")
	shadow.free()


func test_shadow_pixels_are_translucent_dark_not_opaque_black():
	var shadow := shadow_maker.make_shadow(16, 0.0)
	var image: Image = shadow.texture.get_image()
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert_gt(center.a, 0.0, "center of the shadow should be visible")
	assert_lte(center.a, DropShadow.SHADOW_ALPHA + 0.001, "shadows are soft hints, not black holes")
	# Corners of the bounding box lie outside the ellipse -- fully clear.
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	shadow.free()


func test_shadow_textures_are_cached_per_width():
	var a := shadow_maker.make_shadow(20, 0.0)
	var b := shadow_maker.make_shadow(20, 4.0)
	assert_eq(a.texture, b.texture, "same width should reuse one cached texture")
	a.free()
	b.free()
