extends RefCounted

## The graphics option that trades sharpness for frame rate.
##
## Measured on this machine's integrated GPU at 1920x1080 with vsync off, the
## frame is dominated by per-pixel work -- the grass blade field, the water
## overlay and the ground tint each roughly doubled the frame rate when
## removed. Once those are individually as cheap as they can reasonably be,
## the only lever left that scales the WHOLE frame at once is how many pixels
## get drawn, and that is a decision about how the game should look, so it
## belongs to the player rather than to a constant.
##
## `NATIVE` is the sharp default: the `canvas_items` content-scale mode, where
## the world and the HUD are rasterised at the window's true resolution (see
## DisplayScaling). Every other option switches to the `viewport` mode and
## renders into a smaller framebuffer that is then scaled up to the window,
## which costs the sharpness back but scales the entire frame cost with it.
##
## ## Why the sizes are fractions of the window rather than fixed resolutions
##
## A fixed list like "1280x720 / 1600x900" would land on non-integer scales on
## most monitors, and uneven pixel sizes are exactly the graininess the
## presentation pass removed (see docs/concept/art_resolution.md). Whole
## fractions of the player's OWN window always land on whole pixels, whatever
## that window happens to be.

## Draw at the window's real resolution -- sharpest, most expensive.
const NATIVE := "native"
## Halves and thirds of each axis: a quarter and a ninth of the fragments.
##
## Only WHOLE divisors are offered. Three quarters was tried and dropped
## because 1920 / (1920 * 0.75) is 1.333 -- the framebuffer would scale up to
## the window by a fraction of a pixel, which is exactly the uneven-pixel
## graininess the presentation pass removed. Caught by
## test_every_option_keeps_whole_pixels_on_a_1080p_screen.
const HALF := "half"
const THIRD := "third"

## Ordered sharpest first, which is also the order they appear to the player.
const OPTIONS: Array[String] = [NATIVE, HALF, THIRD]

const _LABELS := {
	NATIVE: "Native (sharpest)",
	HALF: "Half (4x fewer pixels)",
	THIRD: "Third (9x fewer pixels)",
}

## Axis scale per option. NATIVE is 1.0 but is handled by mode rather than by
## size, so it never divides the window at all.
const _AXIS_SCALE := {
	NATIVE: 1.0,
	HALF: 0.5,
	THIRD: 1.0 / 3.0,
}


static func default_option() -> String:
	return NATIVE


static func label_for(option: String) -> String:
	return _LABELS.get(option, _LABELS[NATIVE])


static func is_native(option: String) -> bool:
	return sanitize(option) == NATIVE


## Guards against a config file written by an older build, or edited by hand:
## an unrecognised value falls back to the sharp default rather than leaving
## the game in an undefined display mode.
static func sanitize(option: String) -> String:
	return option if OPTIONS.has(option) else NATIVE


## The framebuffer this option renders into for a given window. NATIVE returns
## the window itself -- it does not render into a smaller buffer at all.
static func render_size(option: String, window_size: Vector2i) -> Vector2i:
	var scale: float = _AXIS_SCALE.get(sanitize(option), 1.0)
	return Vector2i(
		maxi(1, int(round(float(window_size.x) * scale))),
		maxi(1, int(round(float(window_size.y) * scale)))
	)


static func pixel_count(option: String, window_size: Vector2i) -> int:
	var size := render_size(option, window_size)
	return size.x * size.y


## Whether this option's framebuffer scales up to the window by a whole
## number of pixels per rendered pixel. Uneven scaling is what "coarse and
## grainy" was, so an option that reintroduces it is not worth offering.
static func is_pixel_perfect(option: String, window_size: Vector2i) -> bool:
	if is_native(option):
		return true
	var size := render_size(option, window_size)
	if size.x <= 0 or size.y <= 0:
		return false
	return _divides_wholly(window_size.x, size.x) and _divides_wholly(window_size.y, size.y)


static func _divides_wholly(window_axis: int, render_axis: int) -> bool:
	if render_axis <= 0:
		return false
	var ratio := float(window_axis) / float(render_axis)
	return absf(ratio - roundf(ratio)) < 0.001
