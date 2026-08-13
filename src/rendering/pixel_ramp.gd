extends RefCounted

## The shared shading ramp every procedural generator colors with (see
## docs/concept/pixel_art_engine.md).
##
## Before this, generators shaded by calling Color.darkened()/lightened() on
## a base color. That only moves VALUE, which is why the art read flat and
## slightly muddy -- a "shaded" shape was the same hue three times over at
## different brightness, which no real surface looks like.
##
## Real pixel art shifts HUE along the ramp:
##   - Shadows shift COOLER (toward blue/purple). A shadow isn't the surface
##     with less light on it; it's the surface lit by the blue sky instead
##     of by the sun.
##   - Highlights shift WARMER (toward yellow), because that's the color of
##     the direct light doing the lighting.
##   - Saturation peaks in the MIDTONES and falls off at both ends: pushing
##     saturation into the shadows makes them look like black paint, and
##     into the highlights makes them look like glare.
##
## Applying that consistently is the single change that lifts every
## generator's look at once, which is why it lives here rather than being
## re-derived per sprite.

## How many discrete steps a ramp has. Few enough to stay honest pixel art
## (a hand-picked palette, not a photographic gradient), enough to model a
## rounded surface.
const STOPS := 5

## How far, in hue turns, the darkest shadow and brightest highlight shift
## away from the base hue. Small -- this should read as light temperature,
## not as a different-colored object.
const SHADOW_HUE_SHIFT := 0.055
const HIGHLIGHT_HUE_SHIFT := 0.04

## Value (brightness) at the ramp's two ends, relative to the base's own
## value. The spread is wide enough that a shaded shape reads as lit rather
## than as a flat fill with a slight edge (pinned by
## test_ramp_spans_a_wide_value_range).
const SHADOW_VALUE_SCALE := 0.45
const HIGHLIGHT_VALUE_BOOST := 0.42

## Saturation multipliers at the ends vs. the midtone peak.
const END_SATURATION_SCALE := 0.72
const MIDTONE_SATURATION_BOOST := 1.12

## Saturation floor applied when the base is essentially grey (stone, metal,
## bone). Without it a grey ramp stays grey and reads as lifeless; with it,
## grey still picks up cool shadows and warm highlights.
const GREY_SATURATION := 0.16
const GREY_THRESHOLD := 0.08

## Hues the ends bias toward for a grey base, in turns (Godot hue space:
## ~0.08 is a warm orange-yellow, ~0.58 a cool blue).
const WARM_HUE := 0.08
const COOL_HUE := 0.58


## The full ramp for `base`, darkest first. Index 0 is the deepest shadow,
## STOPS - 1 the brightest highlight; the base's own midtone sits in the
## middle.
func build(base: Color) -> Array:
	var stops := []
	for i in STOPS:
		stops.append(_stop(base, float(i) / float(STOPS - 1)))
	return stops


## The ramp color at `lightness` (0 = deepest shadow, 1 = brightest
## highlight). Callers shade by a 0..1 fraction so their maths never needs
## to know how many stops exist.
func sample(base: Color, lightness: float) -> Color:
	var t := clampf(lightness, 0.0, 1.0)
	return _stop(base, t)


## Signed shortest hue distance from `from` to `to`, in turns: positive
## means `to` sits at a higher hue (cooler, toward blue), negative lower
## (warmer, toward red/yellow). Exposed because "did the hue shift the
## right way" is otherwise awkward to assert on a wheel.
func hue_shift_from(from: Color, to: Color) -> float:
	var delta := to.h - from.h
	if delta > 0.5:
		delta -= 1.0
	elif delta < -0.5:
		delta += 1.0
	return delta


func _stop(base: Color, t: float) -> Color:
	var hue := base.h
	var saturation := base.s
	# A near-grey base has no meaningful hue to shift, so give it one.
	if saturation < GREY_THRESHOLD:
		saturation = GREY_SATURATION
		hue = COOL_HUE if t < 0.5 else WARM_HUE

	# t: 0 = deepest shadow, 0.5 = base midtone, 1 = brightest highlight.
	var from_mid := (t - 0.5) * 2.0  # -1 at the shadow end, +1 at the highlight end
	if from_mid < 0.0:
		hue = _wrap_hue(hue + SHADOW_HUE_SHIFT * -from_mid)
	else:
		hue = _wrap_hue(hue - HIGHLIGHT_HUE_SHIFT * from_mid)

	# Saturation peaks at the midtone and eases off toward both ends.
	var saturation_curve: float = lerp(MIDTONE_SATURATION_BOOST, END_SATURATION_SCALE, absf(from_mid))
	saturation = clampf(saturation * saturation_curve, 0.0, 1.0)

	var value: float
	if from_mid < 0.0:
		value = lerp(base.v * SHADOW_VALUE_SCALE, base.v, 1.0 + from_mid)
	else:
		value = lerp(base.v, minf(base.v + HIGHLIGHT_VALUE_BOOST, 1.0), from_mid)

	return Color.from_hsv(hue, saturation, clampf(value, 0.0, 1.0), 1.0)


func _wrap_hue(hue: float) -> float:
	return fposmod(hue, 1.0)
