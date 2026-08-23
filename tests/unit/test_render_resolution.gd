extends GutTest

## The graphics option that trades sharpness for frame rate (see
## docs/concept/art_resolution.md).
##
## Measured on this machine's integrated GPU at 1920x1080 with vsync off, the
## frame is dominated by per-pixel work: the grass blade field, the water
## overlay and the ground tint each roughly doubled the frame rate when
## removed. Once those are as cheap as they can reasonably be, the only lever
## left that scales the whole frame is how many pixels are drawn.

const RenderResolution = preload("res://src/rendering/render_resolution.gd")


func test_native_is_the_sharp_default():
	assert_eq(RenderResolution.default_option(), RenderResolution.NATIVE)


func test_every_option_has_a_label_a_player_can_choose_between():
	for option in RenderResolution.OPTIONS:
		assert_ne(RenderResolution.label_for(option), "", "option %s needs a label" % option)


## Native means "draw at the window's real size": the canvas_items mode that
## makes the HUD sharp (see DisplayScaling).
func test_native_draws_at_the_windows_own_resolution():
	assert_true(RenderResolution.is_native(RenderResolution.NATIVE))
	assert_false(RenderResolution.is_native(RenderResolution.HALF))


## The reduced options render fewer pixels and are upscaled, which is the
## whole point -- fewer fragments is the only lever that scales the entire
## frame at once.
func test_a_reduced_option_renders_fewer_pixels_than_the_window():
	var size := RenderResolution.render_size(RenderResolution.HALF, Vector2i(1920, 1080))
	assert_lt(size.x, 1920)
	assert_lt(size.y, 1080)


func test_the_options_are_ordered_from_sharpest_to_fastest():
	var previous := 99999999
	for option in RenderResolution.OPTIONS:
		var pixels := RenderResolution.pixel_count(option, Vector2i(1920, 1080))
		assert_lt(pixels, previous + 1, "options must get cheaper down the list")
		previous = pixels


## The saving has to be worth having: halving each axis is a 4x cut in
## fragments, which is what turns an unplayable frame rate into a playable one.
func test_the_cheapest_option_is_a_large_saving():
	var native := RenderResolution.pixel_count(RenderResolution.NATIVE, Vector2i(1920, 1080))
	var cheapest := RenderResolution.pixel_count(
		RenderResolution.OPTIONS[RenderResolution.OPTIONS.size() - 1], Vector2i(1920, 1080)
	)
	assert_lt(float(cheapest) / float(native), 0.3, "the fastest option must actually be fast")


## Pixel art must stay on a whole-pixel grid whatever the setting: an option
## that renders at a size the window is not a whole multiple of would put back
## exactly the uneven-pixel graininess the presentation pass removed.
func test_every_option_keeps_whole_pixels_on_a_1080p_screen():
	for option in RenderResolution.OPTIONS:
		assert_true(
			RenderResolution.is_pixel_perfect(option, Vector2i(1920, 1080)),
			"%s does not land on whole pixels at 1080p" % RenderResolution.label_for(option)
		)


func test_an_unknown_saved_option_falls_back_to_native():
	assert_eq(RenderResolution.sanitize("nonsense_from_an_old_config"), RenderResolution.NATIVE)


func test_a_known_option_survives_being_saved_and_reloaded():
	for option in RenderResolution.OPTIONS:
		assert_eq(RenderResolution.sanitize(option), option)
