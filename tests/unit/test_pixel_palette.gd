extends GutTest

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

var palette: PixelPalette


func before_each():
	palette = PixelPalette.new()


func _saturation(c: Color) -> float:
	return c.s


func test_outline_const_is_very_dark_and_slightly_cool():
	var o: Color = PixelPalette.OUTLINE
	assert_lt(o.v, 0.15, "outline should be near-black")
	assert_gt(o.b, o.r, "outline should be slightly cool (blue over red)")


func test_outline_color_returns_the_outline_const():
	assert_eq(palette.outline_color(), PixelPalette.OUTLINE)


func test_saturate_raises_hsv_saturation():
	var base := Color(0.4, 0.55, 0.3)
	var out := palette.saturate(base, 0.3)
	assert_gt(_saturation(out), _saturation(base), "saturate should increase HSV s")


func test_saturate_clamps_saturation_to_one():
	var base := Color(0.4, 0.55, 0.3)
	var out := palette.saturate(base, 5.0)
	assert_lte(out.s, 1.0, "saturation must stay clamped at 1.0")


func test_saturate_preserves_alpha():
	var base := Color(0.4, 0.55, 0.3, 0.5)
	var out := palette.saturate(base, 0.3)
	assert_almost_eq(out.a, 0.5, 0.001)


func test_shade_is_darker_than_input():
	var base := Color(0.5, 0.6, 0.4)
	assert_lt(palette.shade(base).v, base.v, "shade should darken")


func test_highlight_is_lighter_than_input():
	var base := Color(0.5, 0.6, 0.4)
	assert_gt(palette.highlight(base).v, base.v, "highlight should lighten")


func test_is_deterministic():
	var base := Color(0.3, 0.7, 0.2)
	assert_eq(palette.saturate(base, 0.4), palette.saturate(base, 0.4))
	assert_eq(palette.shade(base), palette.shade(base))
	assert_eq(palette.highlight(base), palette.highlight(base))
