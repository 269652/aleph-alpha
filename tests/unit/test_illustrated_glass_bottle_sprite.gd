extends GutTest

## Red-first spec for illustrated_glass_bottle_sprite.gd (docs/concept/
## capture_dsl.md's "Rendering a bottled catch"): reads the glass_bottle
## composite sheet's fixed 3x2 grid (condition columns x back/front row).
## A FIXED-position read, not composite_sheet_slicer.gd's blob detection --
## this grid is regular and known in advance, the same "fixed Y/X bands"
## shape item_illustrations.md's wooden_club sheet already uses.

const IllustratedGlassBottleSprite = preload("res://src/rendering/illustrated_glass_bottle_sprite.gd")

var sprite: IllustratedGlassBottleSprite


func before_each():
	sprite = IllustratedGlassBottleSprite.new()


func test_the_real_sheet_is_available():
	assert_true(sprite.is_available(), "assets/sprites/items/glass_bottle.png should load")


func test_back_texture_for_pristine_is_a_real_non_degenerate_image():
	var tex := sprite.back_texture_for("pristine")
	assert_not_null(tex)
	assert_gt(tex.get_width(), 100)
	assert_gt(tex.get_height(), 100)


func test_front_texture_for_pristine_is_a_real_non_degenerate_image():
	var tex := sprite.front_texture_for("pristine")
	assert_not_null(tex)
	assert_gt(tex.get_width(), 100)
	assert_gt(tex.get_height(), 100)


func test_back_and_front_are_different_images():
	var back := sprite.back_texture_for("pristine")
	var front := sprite.front_texture_for("pristine")
	assert_ne(_image_hash(back.get_image()), _image_hash(front.get_image()))


func test_every_condition_produces_a_real_texture_for_both_rows():
	for condition in ["pristine", "worn", "broken"]:
		assert_not_null(sprite.back_texture_for(condition), condition)
		assert_not_null(sprite.front_texture_for(condition), condition)


func test_pristine_and_broken_are_different_images():
	var pristine := sprite.back_texture_for("pristine")
	var broken := sprite.back_texture_for("broken")
	assert_ne(_image_hash(pristine.get_image()), _image_hash(broken.get_image()))


func test_an_unknown_condition_falls_back_to_pristine_rather_than_erroring():
	var fallback := sprite.back_texture_for("not_a_real_condition")
	var pristine := sprite.back_texture_for("pristine")
	assert_eq(_image_hash(fallback.get_image()), _image_hash(pristine.get_image()))


## A cheap way to compare two images for equality/inequality without a
## pixel-by-pixel loop -- the raw byte buffer differs iff the images do.
func _image_hash(image: Image) -> int:
	return hash(image.get_data())
