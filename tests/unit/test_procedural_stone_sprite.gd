extends GutTest

const ProceduralStoneSprite = preload("res://src/rendering/procedural_stone_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator: ProceduralStoneSprite


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: the boulder silhouette is ringed with the shared
## near-black cool outline so it pops against the ground.
func test_boulder_uses_the_shared_dark_outline():
	var image := generator.generate_image(42)
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "boulder should use the shared outline color")


func before_each():
	generator = ProceduralStoneSprite.new()


func test_image_matches_the_generators_canvas_size():
	var image := generator.generate_image(42)
	assert_eq(image.get_width(), ProceduralStoneSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralStoneSprite.SIZE.y)


func test_image_has_transparent_background_and_opaque_boulder():
	var image := generator.generate_image(42)
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


func test_boulder_pixels_are_grey():
	var image := generator.generate_image(7)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.5:
				assert_almost_eq(color.r, color.g, 0.05)
				assert_almost_eq(color.g, color.b, 0.05)


func test_same_seed_produces_identical_image():
	var a := generator.generate_image(123)
	var b := generator.generate_image(123)
	assert_eq(a.get_data(), b.get_data())


func test_different_seeds_produce_different_images():
	var a := generator.generate_image(1)
	var b := generator.generate_image(2)
	assert_ne(a.get_data(), b.get_data())


func test_boulder_is_shaded_with_multiple_grey_tones():
	var image := generator.generate_image(42)
	var tones := {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.5:
				tones[color.to_html()] = true
	assert_gt(tones.size(), 2)


func test_generate_texture_wraps_image():
	var texture := generator.generate_texture(42)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralStoneSprite.SIZE.x)
	assert_eq(texture.get_height(), ProceduralStoneSprite.SIZE.y)


## "Semi-procedural" surface grain (see docs/concept -- reported: "the stones
## look unnatural"): the base fill used to be exactly ONE flat colour across
## the whole boulder body (plus a handful of speckle pixels), which is what
## read as unnatural -- a real rock surface has continuous per-pixel tonal
## variation (mineral grain, weathering), not a flat fill. This measures the
## PLAIN base-fill zone specifically (excluding the outline ring, the
## highlight corner, the shade band, and the seeded speckle pixels, all of
## which already varied) so the assertion is actually about the fill, not
## about zones that were never flat.
## Reported: "they all have the same shape". The old silhouette was a
## near-perfect ellipse with at most a ~1.5px horizontal wobble on a 32px
## canvas -- visually indistinguishable seed to seed. Measures the alpha
## MASK (not colour) so this is purely about outline shape, not texture.
func _alpha_mask(image: Image) -> Array:
	var mask := []
	for y in image.get_height():
		for x in image.get_width():
			mask.append(image.get_pixel(x, y).a > 0.5)
	return mask


## Averaged across many seed pairs rather than demanding every single pair
## differ by a lot: real natural variation can have an occasional
## coincidentally-similar pair (two seeds landing on a similar noise phase),
## same as two real pebbles occasionally looking alike. What must hold is
## that rocks are DIVERSE OVERALL, not that no two are ever close.
func test_different_seeds_produce_meaningfully_different_silhouettes_on_average():
	var reference := _alpha_mask(generator.generate_image(1))
	var total_difference := 0
	var sample_count := 10
	for seed_value in range(2, 2 + sample_count):
		var mask := _alpha_mask(generator.generate_image(seed_value))
		for i in reference.size():
			if reference[i] != mask[i]:
				total_difference += 1
	var average_difference := total_difference / sample_count
	assert_gt(
		average_difference, ProceduralStoneSprite.MIN_SILHOUETTE_PIXEL_DIFFERENCE,
		"seeds should differ from a reference by a real number of edge pixels on average, not a sliver"
	)


## Irregularity must only ever carve INTO the base ellipse, never bulge past
## its 1px margin -- otherwise a jagged boulder could touch/exceed the
## canvas edge (see the existing 1px margin in radius_x/radius_y).
func test_a_jagged_silhouette_never_exceeds_the_original_margin():
	for seed_value in range(20):
		var image := generator.generate_image(seed_value)
		for y in image.get_height():
			assert_eq(image.get_pixel(0, y).a, 0.0, "seed %d touches the left edge" % seed_value)
			assert_eq(
				image.get_pixel(image.get_width() - 1, y).a, 0.0,
				"seed %d touches the right edge" % seed_value
			)


func test_boulder_surface_has_real_grain_not_a_flat_fill():
	var image := generator.generate_image(42)
	var size := ProceduralStoneSprite.SIZE
	var boulder_height := float(size.y) * ProceduralStoneSprite.BOULDER_HEIGHT_FRAC
	var boulder_top := float(size.y) - boulder_height
	var center := Vector2(size.x / 2.0, boulder_top + boulder_height / 2.0)
	var radius_x := size.x / 2.0 - 1.0
	var radius_y := boulder_height / 2.0 - 0.5
	var tones := {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a <= 0.5:
				continue
			var dx := (x + 0.5 - center.x) / radius_x
			var dy := (y + 0.5 - center.y) / radius_y
			var dist_sq := dx * dx + dy * dy
			# Plain base fill only: not outline, not highlight corner, not
			# shade band -- the zones that were always allowed to differ.
			if dist_sq > 0.78 or (dx < -0.15 and dy < -0.2) or dy > 0.35:
				continue
			tones[color.to_html()] = true
	assert_gt(
		tones.size(), ProceduralStoneSprite.MIN_BASE_FILL_GRAIN_TONES,
		"the plain fill area should show real per-pixel grain, not one flat colour"
	)
