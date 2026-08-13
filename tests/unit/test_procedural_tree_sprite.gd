extends GutTest

const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator := ProceduralTreeSprite.new()


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false


## Art-direction pass: the tree silhouette is ringed with the shared near-black
## cool outline so it pops against the ground.
func test_tree_uses_the_shared_dark_outline():
	var image := generator.generate_image(0.5, 1)
	assert_true(_has_pixel(image, PixelPalette.OUTLINE), "tree should use the shared outline color")


func test_generates_an_image_of_the_expected_size():
	var image := generator.generate_image(0.5, 1)
	assert_eq(image.get_width(), ProceduralTreeSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralTreeSprite.SIZE.y)


func test_canopy_area_is_greenish_and_opaque():
	var image := generator.generate_image(0.5, 1)
	# Sampled proportionally, not at a fixed row: row 2 sat mid-canopy on the
	# old 26px-tall tree but lands on the outlined apex once the art is
	# authored 4x taller (see docs/concept/art_resolution.md).
	var canopy_pixel := image.get_pixel(
		ProceduralTreeSprite.SIZE.x / 2, int(ProceduralTreeSprite.SIZE.y * 0.25)
	)
	assert_gt(canopy_pixel.a, 0.0)
	assert_gt(canopy_pixel.g, canopy_pixel.r)
	assert_gt(canopy_pixel.g, canopy_pixel.b)


func test_trunk_area_is_brownish_and_opaque():
	var image := generator.generate_image(0.5, 1)
	var trunk_pixel := image.get_pixel(ProceduralTreeSprite.SIZE.x / 2, ProceduralTreeSprite.SIZE.y - 2)
	assert_gt(trunk_pixel.a, 0.0)
	assert_gt(trunk_pixel.r, trunk_pixel.b)


func test_is_deterministic_for_the_same_inputs():
	var a := generator.generate_image(0.5, 7)
	var b := generator.generate_image(0.5, 7)
	assert_eq(a.get_data(), b.get_data())


func test_differs_for_a_different_seed():
	var a := generator.generate_image(0.5, 7)
	var b := generator.generate_image(0.5, 8)
	assert_ne(a.get_data(), b.get_data())


func test_a_fruit_leaning_tree_looks_different_from_a_nut_leaning_tree():
	var nut_leaning := generator.generate_image(0.0, 3)
	var fruit_leaning := generator.generate_image(1.0, 3)
	assert_ne(nut_leaning.get_data(), fruit_leaning.get_data())


func test_zero_ripe_fruit_matches_the_plain_canopy():
	var plain := generator.generate_image(1.0, 7)
	var no_fruit := generator.generate_image_with_fruit(1.0, 7, 0)
	assert_eq(no_fruit.get_data(), plain.get_data(), "no ripe fruit should look identical to the plain tree")


func _fruit_dot_pixel_count(image: Image) -> int:
	# Ripe fruit dots are drawn in a distinctly warm (reddish) colour unlike the
	# green canopy / brown trunk -- count pixels where red clearly dominates.
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.r > 0.55 and c.r > c.g + 0.2 and c.r > c.b + 0.2:
				count += 1
	return count


func test_ripe_fruit_adds_warm_fruit_dots_to_the_canopy():
	var some := generator.generate_image_with_fruit(1.0, 7, 3)
	assert_gt(_fruit_dot_pixel_count(some), 0, "ripe fruit should paint warm dots on the canopy")


func test_more_ripe_fruit_shows_at_least_as_many_dots_up_to_the_cap():
	var few := _fruit_dot_pixel_count(generator.generate_image_with_fruit(1.0, 7, 1))
	var many := _fruit_dot_pixel_count(generator.generate_image_with_fruit(1.0, 7, 6))
	assert_gte(many, few, "more ripe fruit should render at least as many dots")
	assert_gt(many, 0)


func test_fruit_rendering_is_deterministic():
	var a := generator.generate_image_with_fruit(0.8, 42, 4)
	var b := generator.generate_image_with_fruit(0.8, 42, 4)
	assert_eq(a.get_data(), b.get_data())


# -- painted detail, not just a bigger canvas -------------------------------
#
# docs/concept/art_resolution.md's first pillar: 4x the pixels only counts
# if the generator PAINTS more information into them. A canopy drawn as one
# flat ellipse looks identical at any resolution, just smoother-edged.

## The crown stays ROUND -- a clean rounded silhouette read better than a
## lumpy cluster-of-blobs outline, so detail belongs INSIDE the crown (see
## the leaf test below), not in a broken edge. Measured as: the row-width
## profile rises then falls with almost no direction reversals.
func test_canopy_silhouette_stays_round():
	var image := generator.generate_image(0.5, 7)
	var widths := []
	var canopy_bottom := int(ProceduralTreeSprite.SIZE.y * ProceduralTreeSprite.CANOPY_HEIGHT_FRAC)
	for y in range(4, canopy_bottom - 4):
		var w := 0
		for x in ProceduralTreeSprite.SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				w += 1
		widths.append(w)
	var reversals := 0
	for i in range(2, widths.size()):
		var prev_delta: int = widths[i - 1] - widths[i - 2]
		var delta: int = widths[i] - widths[i - 1]
		if (prev_delta > 0 and delta < 0) or (prev_delta < 0 and delta > 0):
			reversals += 1
	assert_lte(reversals, 2, "the crown should read as one round mass, not a lumpy cluster of blobs")


## Individual leaves are actually drawn inside the crown, rather than the
## canopy being a flat fill plus noise -- this is the detail the 4x canvas
## exists to carry (docs/concept/art_resolution.md). Counted as separate
## horizontal runs of leaf-highlight pixels: one run per leaf edge crossed.
func test_canopy_renders_many_individual_leaves():
	var image := generator.generate_image(0.5, 7)
	var canopy_bottom := int(ProceduralTreeSprite.SIZE.y * ProceduralTreeSprite.CANOPY_HEIGHT_FRAC)
	var runs := 0
	for y in canopy_bottom:
		var in_run := false
		for x in ProceduralTreeSprite.SIZE.x:
			var is_leaf := generator.is_leaf_highlight(image.get_pixel(x, y))
			if is_leaf and not in_run:
				runs += 1
			in_run = is_leaf
	assert_gt(runs, 40, "the crown should be made of many individually drawn leaves")


## Real foliage has depth: multiple distinct green tones (shadowed underside
## through sunlit top), not one flat fill plus an outline.
func test_canopy_has_layered_green_tones_for_depth():
	var image := generator.generate_image(0.5, 3)
	var greens := {}
	for y in int(ProceduralTreeSprite.SIZE.y * ProceduralTreeSprite.CANOPY_HEIGHT_FRAC):
		for x in ProceduralTreeSprite.SIZE.x:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.g > pixel.r and pixel.g > pixel.b:
				greens[pixel] = true
	assert_gte(greens.size(), 4, "canopy should layer several green tones, not read as one flat fill")


## The trunk should show bark texture rather than being flat brown columns.
func test_trunk_has_bark_texture():
	var image := generator.generate_image(0.5, 5)
	var trunk_top := int(ProceduralTreeSprite.SIZE.y * ProceduralTreeSprite.CANOPY_HEIGHT_FRAC)
	var browns := {}
	for y in range(trunk_top, ProceduralTreeSprite.SIZE.y):
		for x in ProceduralTreeSprite.SIZE.x:
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.r > pixel.b:
				browns[pixel] = true
	assert_gte(browns.size(), 3, "trunk should have bark shading, not one flat brown")
