extends GutTest

const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator: ProceduralCharacterSprite


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: body parts are outlined with the shared near-black cool
## outline so the character pops against the ground (Hammerwatch readability).
func test_body_part_uses_the_shared_dark_outline():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "body part should use the shared outline color")


func before_each():
	generator = ProceduralCharacterSprite.new()


func test_body_part_image_has_the_requested_size():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_eq(image.get_width(), 10)
	assert_eq(image.get_height(), 14)


func test_body_part_image_is_not_a_single_flat_color():
	var image := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	var distinct := {}
	for y in image.get_height():
		for x in image.get_width():
			distinct[image.get_pixel(x, y)] = true
	assert_gt(distinct.size(), 1, "expected shading/outline to introduce color variety")


func test_body_part_image_is_deterministic():
	var a := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	var b := generator.generate_body_part_image(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	for y in a.get_height():
		for x in a.get_width():
			assert_eq(a.get_pixel(x, y), b.get_pixel(x, y))


func test_head_image_has_the_requested_size():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(image.get_width(), 8)
	assert_eq(image.get_height(), 8)


func test_head_image_is_shaded_not_flat():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	var distinct := {}
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0:
				distinct[p] = true
	assert_gt(distinct.size(), 2, "expected shading + eyes to introduce color variety")


func test_head_image_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_head_image(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_gt(image.get_pixel(4, 4).a, 0.0)


func test_generate_body_part_texture_returns_an_image_texture():
	var texture := generator.generate_body_part_texture(Vector2i(10, 14), Color(0.2, 0.4, 0.8))
	assert_eq(texture.get_width(), 10)


func test_generate_head_texture_returns_an_image_texture():
	var texture := generator.generate_head_texture(Vector2i(8, 8), Color(0.9, 0.75, 0.6), Color(0.1, 0.1, 0.1))
	assert_eq(texture.get_width(), 8)


## _fit_to_box downscales a hero_composite.png crop (large, hand-drawn
## pixel art -- flat colour blocks, not fine photographic detail) into the
## portrait's own tiny per-part boxes (as small as 14x14 -- see
## PORTRAIT_SIZE's own doc comment: "scaled up by the UI (nearest-neighbour)
## so it stays crisp pixel art"). It used Image.INTERPOLATE_LANCZOS -- a
## smoothing resize correct for downscaling fine per-pixel detail (see
## TerrainRenderer._normalized_for_compositing's own doc comment on exactly
## that trade-off, applied there to noise-based ground textures) but wrong
## for blocky character art, where it blends flat colour regions into new,
## soft in-between colours that never existed in the source -- and no
## amount of correct NEAREST upscaling downstream can undo blur already
## baked into those pixels (reported live, with a screenshot: "char preview
## is super blurry", after the display-scale fix alone hadn't resolved it).
## Checked directly: resizing a hard 2-colour source down must produce a
## result containing ONLY those two colours, never a blended third.
func test_fit_to_box_downscales_with_nearest_not_a_smoothing_filter():
	var source := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	var red := Color(1, 0, 0, 1)
	var blue := Color(0, 0, 1, 1)
	for y in 20:
		for x in 20:
			source.set_pixel(x, y, red if x < 10 else blue)
	var fitted: Image = generator.call("_fit_to_box", source, Vector2i(6, 6))
	for y in fitted.get_height():
		for x in fitted.get_width():
			var p := fitted.get_pixel(x, y)
			var matches_red := p.is_equal_approx(red)
			var matches_blue := p.is_equal_approx(blue)
			assert_true(
				matches_red or matches_blue,
				"pixel (%d,%d) is %s -- neither source colour, so it was blended/smoothed" % [x, y, p]
			)


## NEAREST alone fixed the BLUR, but a caller magnifying a still-tiny
## PORTRAIT_SIZE (26x40) up several times over reads as "super pixelated"
## instead -- coarse, obviously-square blocks, not detailed pixel art
## (reported live, with a screenshot, right after the blur fix: "now less
## blurry but super pixelated"). NEAREST can only preserve WHATEVER detail
## _fit_to_box was actually handed; a bigger target box gives it more of
## the source's own real detail to keep, which is what actually reduces
## the "blocky" look at a given final on-screen size (see PORTRAIT_SIZE's
## own doc comment on _PORTRAIT_DETAIL_SCALE for the full reasoning) --
## checked here directly: fitting the SAME richly-detailed source into a
## LARGER box must keep more of its distinct colours, not just re-run the
## same few blocks bigger.
func test_fit_to_box_preserves_more_detail_when_given_a_larger_target():
	var source := Image.create(40, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 40:
			# A real per-pixel gradient, not flat blocks -- the fine detail
			# a bigger target box should be able to keep more of.
			source.set_pixel(x, y, Color(float(x) / 39.0, float(y) / 39.0, 0.5, 1.0))

	var small: Image = generator.call("_fit_to_box", source, Vector2i(8, 8))
	var large: Image = generator.call("_fit_to_box", source, Vector2i(16, 16))

	var small_colors := {}
	for y in small.get_height():
		for x in small.get_width():
			small_colors[small.get_pixel(x, y)] = true
	var large_colors := {}
	for y in large.get_height():
		for x in large.get_width():
			large_colors[large.get_pixel(x, y)] = true

	assert_gt(
		large_colors.size(), small_colors.size(),
		"a larger target box (%d distinct colours) should preserve more source detail than a smaller one (%d)" % [large_colors.size(), small_colors.size()]
	)


## The actual fix: PORTRAIT_SIZE itself grew (see its own doc comment on
## _PORTRAIT_DETAIL_SCALE), giving _fit_to_box more real room to work with
## per the property just proven above -- while keeping the SAME 26:40
## aspect ratio, since main_menu.gd's own STANDARD_PORTRAIT_DISPLAY_SIZE
## derives its final on-screen scale from this size and expects that shape
## to hold.
func test_portrait_size_grew_for_more_detail_but_kept_its_own_aspect_ratio():
	assert_gt(ProceduralCharacterSprite.PORTRAIT_SIZE.x, 26, "portrait detail should have increased beyond the original 26x40")
	var aspect: float = float(ProceduralCharacterSprite.PORTRAIT_SIZE.x) / float(ProceduralCharacterSprite.PORTRAIT_SIZE.y)
	assert_almost_eq(aspect, 26.0 / 40.0, 0.001)
