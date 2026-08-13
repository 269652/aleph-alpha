extends GutTest

## PixelRamp: the shared shading ramp every procedural generator colors
## with (see docs/concept/pixel_art_engine.md).
##
## Before this, generators shaded by calling Color.darkened()/lightened()
## on a base color. That only moves VALUE, which is why the art read flat
## and slightly muddy: real pixel art shifts HUE along the ramp too --
## shadows toward cool blues/purples (skylight fills shadow), highlights
## toward warm yellows (direct sun) -- and increases saturation in the
## midtones. These tests pin that behaviour, since it is the single change
## that lifts every generator's look at once.

const PixelRamp = preload("res://src/rendering/pixel_ramp.gd")

var ramp: PixelRamp

const BASE := Color(0.2, 0.55, 0.25)  # a mid green, like foliage


func before_each():
	ramp = PixelRamp.new()


func test_ramp_has_the_pinned_number_of_stops():
	assert_eq(ramp.build(BASE).size(), PixelRamp.STOPS)


func test_ramp_runs_dark_to_light():
	var stops := ramp.build(BASE)
	for i in range(1, stops.size()):
		var previous: Color = stops[i - 1]
		var current: Color = stops[i]
		assert_gt(current.v, previous.v, "stop %d should be lighter than stop %d" % [i, i - 1])


## The core of the technique: shadow stops shift toward cool hues and
## highlight stops toward warm ones, rather than every stop sharing the
## base hue at different brightness.
func test_shadows_shift_cool_and_highlights_shift_warm():
	var stops := ramp.build(BASE)
	var shadow: Color = stops[0]
	var highlight: Color = stops[PixelRamp.STOPS - 1]
	assert_ne(shadow.h, BASE.h, "the shadow stop should shift hue, not just darken")
	assert_ne(highlight.h, BASE.h, "the highlight stop should shift hue, not just lighten")
	# Hue is a wheel: measure the signed shortest distance from the base.
	assert_gt(ramp.hue_shift_from(BASE, shadow), 0.0, "shadows shift toward cooler (higher) hues")
	assert_lt(ramp.hue_shift_from(BASE, highlight), 0.0, "highlights shift toward warmer (lower) hues")


## A flat fill plus two shades reads as paper; a ramp with real spread
## reads as a lit surface.
func test_ramp_spans_a_wide_value_range():
	var stops := ramp.build(BASE)
	var spread: float = stops[PixelRamp.STOPS - 1].v - stops[0].v
	assert_gt(spread, 0.35, "the ramp should span a wide value range, not a narrow wash")


## Midtones stay the most saturated -- pushing saturation at both ends
## instead makes shadows look like black paint and highlights like glare.
func test_midtones_are_more_saturated_than_the_extremes():
	var stops := ramp.build(BASE)
	var mid: Color = stops[PixelRamp.STOPS / 2]
	assert_gt(mid.s, stops[0].s, "midtone should be more saturated than the deepest shadow")
	assert_gt(mid.s, stops[PixelRamp.STOPS - 1].s, "midtone should be more saturated than the brightest highlight")


func test_is_deterministic_for_the_same_base():
	assert_eq(ramp.build(BASE), ramp.build(BASE))


## Callers index the ramp by a 0..1 lightness fraction rather than by raw
## index, so a shape's shading maths never has to know how many stops
## exist.
func test_sample_maps_a_unit_fraction_across_the_whole_ramp():
	var stops := ramp.build(BASE)
	assert_eq(ramp.sample(BASE, 0.0), stops[0])
	assert_eq(ramp.sample(BASE, 1.0), stops[PixelRamp.STOPS - 1])


func test_sample_clamps_out_of_range_fractions():
	assert_eq(ramp.sample(BASE, -5.0), ramp.sample(BASE, 0.0))
	assert_eq(ramp.sample(BASE, 5.0), ramp.sample(BASE, 1.0))


## A near-grey base (stone, metal, bone) has no meaningful hue of its own,
## so the ramp gives it one -- cool shadows, warm highlights -- which is
## what stops grey art reading as lifeless.
func test_a_grey_base_still_gets_cool_shadows_and_warm_highlights():
	var grey := Color(0.5, 0.5, 0.5)
	var stops := ramp.build(grey)
	assert_gt(stops[0].b, stops[0].r, "grey shadows should lean blue")
	assert_gt(stops[PixelRamp.STOPS - 1].r, stops[PixelRamp.STOPS - 1].b, "grey highlights should lean warm")


func test_every_stop_stays_a_valid_opaque_color():
	for base in [BASE, Color(0.9, 0.2, 0.2), Color(0.1, 0.1, 0.4), Color(0.5, 0.5, 0.5)]:
		for stop in ramp.build(base):
			assert_between(stop.r, 0.0, 1.0)
			assert_between(stop.g, 0.0, 1.0)
			assert_between(stop.b, 0.0, 1.0)
			assert_eq(stop.a, 1.0)
