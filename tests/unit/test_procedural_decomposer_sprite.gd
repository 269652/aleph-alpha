extends GutTest

const ProceduralDecomposerSprite = preload("res://src/rendering/procedural_decomposer_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var generator := ProceduralDecomposerSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("ant")
	assert_eq(image.get_width(), ProceduralDecomposerSprite.SIZE)
	assert_eq(image.get_height(), ProceduralDecomposerSprite.SIZE)


func test_has_transparent_corners_and_an_opaque_center():
	var image := generator.generate_image("ant")
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := ProceduralDecomposerSprite.SIZE / 2
	assert_gt(image.get_pixel(mid, mid).a, 0.0)


func test_is_deterministic():
	var a := generator.generate_image("ant")
	var b := generator.generate_image("ant")
	assert_eq(a.get_data(), b.get_data())


func test_ant_and_bug_look_different():
	var ant := generator.generate_image("ant")
	var bug := generator.generate_image("bug")
	assert_ne(ant.get_data(), bug.get_data())


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("bug")
	assert_eq(texture.get_width(), ProceduralDecomposerSprite.SIZE)


func test_unknown_species_falls_back_to_a_valid_texture():
	var texture := generator.generate_texture("mystery_bug")
	assert_not_null(texture)


# -- readable against the outline, not a black blob -------------------------
#
# ANT_COLOR (0.08, 0.06, 0.05) used to sit almost exactly on top of
# PixelPalette.OUTLINE (0.08, 0.06, 0.1) -- the shared near-black silhouette
# ring every other creature generator in this codebase uses to separate
# itself from the ground. With the fill and the (never-drawn) outline this
# close, a whole ant/bug read as one undifferentiated black blob rather than
# a small dark creature (reported live, from a real screenshot: "these black
# blobs"). Both halves of the fix are pinned separately: the fill must
# actually be distinguishable from the outline color, and the outline must
# actually be drawn.

## How far apart (Euclidean RGB distance) a body color must be from
## PixelPalette.OUTLINE to read as its own color once ringed by that
## outline, rather than melting into it. Comfortably below what either
## ANT_COLOR or BUG_COLOR actually measures, so this only catches a genuine
## regression back toward outline-black, not a false failure over a minor
## palette tweak.
const _MIN_DISTANCE_FROM_OUTLINE := 0.15


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func test_ant_color_is_distinguishable_from_the_shared_outline():
	assert_gt(
		_rgb_distance(ProceduralDecomposerSprite.ANT_COLOR, PixelPalette.new().outline_color()),
		_MIN_DISTANCE_FROM_OUTLINE
	)


func test_bug_color_is_distinguishable_from_the_shared_outline():
	assert_gt(
		_rgb_distance(ProceduralDecomposerSprite.BUG_COLOR, PixelPalette.new().outline_color()),
		_MIN_DISTANCE_FROM_OUTLINE
	)


## The silhouette must actually be rung in the shared outline color (see
## every other procedural creature generator's own _outline_silhouette) --
## without it, a body color that merely differs from OUTLINE in the abstract
## still has no visible edge separating it from the grass behind it.
func test_ant_silhouette_is_outlined():
	var image := generator.generate_image("ant")
	assert_true(_contains_color(image, PixelPalette.new().outline_color()), "expected an outline ring around the ant")


func test_bug_silhouette_is_outlined():
	var image := generator.generate_image("bug")
	assert_true(_contains_color(image, PixelPalette.new().outline_color()), "expected an outline ring around the bug")


## Tolerance-based, not is_equal_approx: the image is FORMAT_RGBA8, so
## painting a float Color quantizes it to 8 bits per channel and the value
## read back is never exactly the value written (same reasoning as
## ProceduralTreeSprite.is_leaf_highlight's own _TONE_EPSILON).
const _TONE_EPSILON := 1.0 / 255.0


func _contains_color(image: Image, color: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if (
				absf(pixel.r - color.r) < _TONE_EPSILON
				and absf(pixel.g - color.g) < _TONE_EPSILON
				and absf(pixel.b - color.b) < _TONE_EPSILON
			):
				return true
	return false


# -- readable at six world pixels, not a slab --------------------------------
#
# See docs/concept/carrion.md "Readable at six world pixels, not a black
# blob". The outline ring above was only half the fix: with the ring grown
# around the LEGS as well as the body, every 1-px gap between the ant's six
# leg strokes was filled in, and body + legs + ring fused into one solid
# slab (reported live, again, from a real screenshot: "some black moving
# blobs"). And a near-black fill inside a near-black ring still had no
# internal form at all. Both halves are pinned here.

## Count of separate opaque runs along one image row -- two legs with
## ground showing between them are two runs; a fused slab is one.
func _opaque_runs_in_row(image: Image, y: int) -> int:
	var runs := 0
	var inside := false
	for x in image.get_width():
		var opaque := image.get_pixel(x, y).a > 0.0
		if opaque and not inside:
			runs += 1
		inside = opaque
	return runs


func test_ant_legs_are_separated_by_ground_not_fused_into_a_slab():
	var image := generator.generate_image("ant")
	var mid := ProceduralDecomposerSprite.SIZE / 2
	# The leg rows above and below the body: three legs a side, so each of
	# these rows must carry at least two separate opaque runs -- a solid
	# slab carries exactly one.
	assert_gte(_opaque_runs_in_row(image, mid - 3), 2, "legs above the body should be separate strokes")
	assert_gte(_opaque_runs_in_row(image, mid + 3), 2, "legs below the body should be separate strokes")


## Minimum luminance step a body marking must sit above the body fill to
## still read as a marking once quantized to 8 bits and drawn at ~6 world
## pixels. Comfortably below what ANT_THORAX_COLOR / BUG_BAND_COLOR actually
## measure, so this only catches a marking sinking back into the fill.
const _MIN_MARKING_LUMINANCE_STEP := 0.12


func _max_luminance(image: Image) -> float:
	var best := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			best = maxf(best, pixel.get_luminance())
	return best


## Wood ant (Formica rufa group): near-black head and gaster, red-brown
## thorax -- the body has a lighter region, not one flat tone.
func test_ant_body_carries_a_lighter_marking_than_its_fill():
	var image := generator.generate_image("ant")
	assert_gt(
		_max_luminance(image),
		ProceduralDecomposerSprite.ANT_COLOR.get_luminance() + _MIN_MARKING_LUMINANCE_STEP
	)


## Burying beetle (Nicrophorus): black with orange bands across the elytra.
func test_bug_elytra_carry_a_lighter_marking_than_its_fill():
	var image := generator.generate_image("bug")
	assert_gt(
		_max_luminance(image),
		ProceduralDecomposerSprite.BUG_COLOR.get_luminance() + _MIN_MARKING_LUMINANCE_STEP
	)
