extends GutTest

## How an art pixel lands on a physical screen pixel (see
## docs/concept/art_resolution.md).
##
## The game rendered everything into a 1280x720 framebuffer and blitted that
## to the monitor. At 1080p that is a 1.5x upscale, so one art pixel covered
## two screen pixels in places and one in others -- and uneven pixel sizes are
## what "coarse and grainy" actually is. Nearest filtering was already on; the
## upscale was the problem.
##
## These pin the property that fixes it: at every resolution the game is
## likely to run at, one art pixel must cover a WHOLE number of screen pixels.

const DisplayScaling = preload("res://src/rendering/display_scaling.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The resolutions this has to be right at: the dev window, and the three
## common fullscreen sizes.
const COMMON_HEIGHTS := [720, 1080, 1440, 2160]


func test_the_canvas_scale_is_the_window_over_the_design_height():
	assert_almost_eq(DisplayScaling.canvas_scale(1080), 1.5, 0.001)
	assert_almost_eq(DisplayScaling.canvas_scale(1440), 2.0, 0.001)
	assert_almost_eq(DisplayScaling.canvas_scale(720), 1.0, 0.001)


## The whole point of the pass.
func test_an_art_pixel_covers_a_whole_number_of_screen_pixels_everywhere():
	for height in COMMON_HEIGHTS:
		assert_true(
			DisplayScaling.is_pixel_perfect(height),
			"%dp gives %.3f screen pixels per art pixel -- uneven pixels are the graininess" % [
				height, DisplayScaling.screen_pixels_per_art_pixel(height)
			]
		)


## ...and it must stay CHUNKY. An art pixel collapsing to a single screen
## pixel is not pixel art any more, it is just a small picture (the resolution
## pass learned this the first time: "the char doesn't look like pixel art").
func test_art_pixels_stay_visibly_chunky_at_every_resolution():
	for height in COMMON_HEIGHTS:
		assert_gte(
			DisplayScaling.screen_pixels_per_art_pixel(height), 2.0,
			"%dp draws art pixels too small to read as pixel art" % height
		)


## Rendering at the window's real resolution is what makes the HUD sharp, so
## the design height is a LAYOUT reference, not the framebuffer size.
func test_a_bigger_window_shows_the_same_amount_of_world():
	assert_almost_eq(
		DisplayScaling.visible_tiles_across(1280, 720),
		DisplayScaling.visible_tiles_across(2560, 1440),
		0.001,
		"scaling the window must not change how much world the player can see"
	)


## The framing this game is actually built around -- creature sense radii and
## the lasso's reach are all tuned against how much the player can see.
func test_the_view_still_frames_about_twenty_tiles_across():
	assert_almost_eq(DisplayScaling.visible_tiles_across(1280, 720), 20.0, 0.5)


## The guard rail: this is exactly the property that breaks if the art
## resolution is raised without re-checking, which is why it is a test rather
## than a comment. 48 art pixels per tile (DETAIL_MULTIPLIER 3) is pixel
## perfect at 1080p and 4K but NOT at 720p or 1440p.
func test_the_pixel_perfect_check_actually_rejects_a_bad_art_size():
	assert_false(
		DisplayScaling.is_pixel_perfect_for_art_size(1440, 48),
		"48px tiles are uneven at 1440p -- the check has to catch that"
	)
	assert_true(DisplayScaling.is_pixel_perfect_for_art_size(1080, 48))
	assert_true(
		DisplayScaling.is_pixel_perfect_for_art_size(1440, 32),
		"32px tiles are what actually works everywhere"
	)


func test_the_current_art_size_is_the_one_being_checked():
	assert_eq(
		DisplayScaling.screen_pixels_per_art_pixel(1080),
		DisplayScaling.screen_pixels_per_art_pixel_for_art_size(
			1080, ArtResolution.DETAIL_MULTIPLIER * DisplayScaling.WORLD_TILE_SIZE
		)
	)
