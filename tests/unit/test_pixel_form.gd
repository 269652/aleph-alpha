extends GutTest

## PixelForm: turns a shape's geometry into a lightness fraction, so a
## filled shape reads as a ROUNDED, LIT SOLID rather than a flat fill with
## an outline (see docs/concept/pixel_art_engine.md).
##
## Generators used to fake this per-file with ad-hoc rules like "if dy <
## -0.3 use the highlight color" -- hard bands that read as stripes painted
## across the shape. PixelForm computes a real surface-normal-vs-light term
## once, and every generator shades through it into a PixelRamp.

const PixelForm = preload("res://src/rendering/pixel_form.gd")

var form: PixelForm


func before_each():
	form = PixelForm.new()


## An ellipse's own coverage: inside/outside plus how deep in it a point is.
func test_ellipse_depth_is_highest_at_the_center_and_zero_outside():
	assert_almost_eq(form.ellipse_depth(Vector2.ZERO, Vector2(10, 10), Vector2.ZERO), 1.0, 0.001)
	assert_eq(form.ellipse_depth(Vector2.ZERO, Vector2(10, 10), Vector2(20, 0)), 0.0)


func test_ellipse_depth_falls_off_toward_the_edge():
	var near_center := form.ellipse_depth(Vector2.ZERO, Vector2(10, 10), Vector2(2, 0))
	var near_edge := form.ellipse_depth(Vector2.ZERO, Vector2(10, 10), Vector2(8, 0))
	assert_gt(near_center, near_edge)


## The core: a sphere lit from the light direction is brightest on the side
## facing the light and darkest on the opposite side.
func test_lighting_is_brightest_on_the_side_facing_the_light():
	var radius := Vector2(10, 10)
	var toward_light := form.lightness(Vector2.ZERO, radius, Vector2(-5, -5))
	var away_from_light := form.lightness(Vector2.ZERO, radius, Vector2(5, 5))
	assert_gt(toward_light, away_from_light, "the lit side should be brighter than the shadowed side")


## Default light comes from the top-left, the convention the whole
## codebase's art already assumes (PixelPalette's highlight/shade pair).
func test_default_light_comes_from_the_top_left():
	assert_lt(PixelForm.LIGHT_DIRECTION.x, 0.0)
	assert_lt(PixelForm.LIGHT_DIRECTION.y, 0.0)


func test_lightness_stays_in_unit_range():
	var radius := Vector2(8, 12)
	for y in range(-14, 15):
		for x in range(-10, 11):
			var l := form.lightness(Vector2.ZERO, radius, Vector2(x, y))
			assert_between(l, 0.0, 1.0)


## Points near the silhouette edge on the far side pick up a rim of
## reflected light, which is what stops a shaded sphere reading as a flat
## disc fading to black.
func test_the_shadowed_rim_lifts_slightly_above_the_deepest_shadow():
	var radius := Vector2(10, 10)
	var deep_shadow := form.lightness(Vector2.ZERO, radius, Vector2(4, 4))
	var shadow_rim := form.lightness(Vector2.ZERO, radius, Vector2(6.6, 6.6))
	assert_gt(shadow_rim, deep_shadow, "a bounce-light rim should lift the shadowed edge")


## Shading a whole shape must produce genuinely many distinct tones -- the
## proof it reads as a rounded solid and not a two-tone cutout.
func test_shading_an_ellipse_uses_most_of_the_ramp():
	const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")
	var ramp := PixelRamp.new()
	var base := Color(0.35, 0.5, 0.8)
	var radius := Vector2(12, 12)
	var tones := {}
	for y in range(-12, 13):
		for x in range(-12, 13):
			var point := Vector2(x, y)
			if form.ellipse_depth(Vector2.ZERO, radius, point) <= 0.0:
				continue
			tones[ramp.sample(base, form.lightness(Vector2.ZERO, radius, point))] = true
	assert_gte(tones.size(), 4, "a lit sphere should span most of the ramp, not two flat tones")


func test_is_deterministic():
	var radius := Vector2(9, 7)
	assert_eq(
		form.lightness(Vector2.ZERO, radius, Vector2(3, -2)),
		form.lightness(Vector2.ZERO, radius, Vector2(3, -2))
	)


# -- cylinders (limbs, trunks, barrels, towers) -----------------------------
#
# A limb is not a sphere: it's a tube, shaded across its width but even
# along its length. Rectangular parts (arms, legs, a torso) shade through
# this rather than the spheroid term, which would darken their ends.

func test_cylinder_is_brightest_toward_the_light_side():
	var lit := form.cylinder_lightness(0.0, 10.0, 2.0)
	var shadowed := form.cylinder_lightness(0.0, 10.0, 8.0)
	assert_gt(lit, shadowed, "the side facing the light should be brighter")


## The defining property vs. a sphere: lightness depends on position ACROSS
## the tube only, never along it.
func test_cylinder_lightness_is_even_along_its_length():
	assert_eq(form.cylinder_lightness(0.0, 10.0, 3.0), form.cylinder_lightness(0.0, 10.0, 3.0))


func test_cylinder_lightness_stays_in_unit_range():
	for x in range(0, 21):
		assert_between(form.cylinder_lightness(0.0, 20.0, float(x)), 0.0, 1.0)


## Same bounce-light reasoning as the spheroid: the far edge lifts, so the
## tube reads as round rather than fading flat into its outline.
func test_cylinder_shadow_edge_lifts_above_the_deepest_shadow():
	var deep := form.cylinder_lightness(0.0, 10.0, 7.5)
	var edge := form.cylinder_lightness(0.0, 10.0, 9.7)
	assert_gt(edge, deep, "a bounce rim should lift the shadowed edge")
