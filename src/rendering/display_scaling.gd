extends RefCounted

## How an art pixel lands on a physical screen pixel (see
## docs/concept/art_resolution.md).
##
## ## The bug this exists to prevent
##
## The game used `window/stretch/mode="viewport"`: everything rendered into a
## 1280x720 framebuffer, which was then blitted to the monitor. At 1080p that
## is a 1.5x upscale, so one art pixel covered two screen pixels in some
## places and one in others. Uneven pixel sizes ARE what reads as "coarse and
## grainy" -- nearest filtering was already on, and it cannot help with an
## upscale that lands art pixels between screen pixels.
##
## The mode is now `canvas_items`: the world and the HUD are drawn at the
## window's real resolution, so text is sharp and an art pixel's size on
## screen is decided by the canvas scale rather than by a blit.
##
## ## Why the art size is not a free parameter
##
## Screen pixels per art pixel is `(tile_screen_px / art_tile_px) * canvas_scale`,
## and it has to come out a WHOLE number at every resolution the game runs at.
## That is a real constraint on how detailed the art may be, because the canvas
## scales between common resolutions are not integer multiples of each other
## (1080p to 1440p is 4/3). For the magnification to survive that step it has
## to be divisible by 3 at 1080p, which given this game's framing means 32 art
## pixels per tile -- DETAIL_MULTIPLIER 2.
##
## Raising the multiplier to 3 (48px tiles) is pixel-perfect at 1080p and 4K
## and uneven at 720p and 1440p, which would put back exactly the graininess
## this pass removed. is_pixel_perfect_for_art_size exists so that trade is
## something a test can state rather than something a future change discovers
## in a screenshot.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")

## The layout reference the UI is designed against, and what the canvas scale
## is measured from. NOT a framebuffer size any more -- see the note above.
const DESIGN_WIDTH := 1280.0
const DESIGN_HEIGHT := 720.0

## World units per tile, and how many of those units a tile occupies on screen
## at the design height. Shares its value with Player.TARGET_TILE_SCREEN_PX
## because both trace back to the same "a tile should read this big" intent
## -- but they answer genuinely different questions and are NOT meant to be
## kept in sync by hand if a future change pulls them apart again (as one
## briefly did on 2026-09-05 -- see below).
##
## This one is load-bearing for PIXEL-PERFECT ART SCALING: is_pixel_perfect
## needs (TILE_SCREEN_PX / (ArtResolution.DETAIL_MULTIPLIER * WORLD_TILE_SIZE))
## to land on a whole number at every canvas scale the game actually hits
## (1.0/1.5/2.0/3.0 for 720p/1080p/1440p/4K) -- 64.0 is the smallest value
## that works, and the next one up is 128.0, not some 64 * 1.1-shaped
## number. Player.TARGET_TILE_SCREEN_PX is a live GAMEPLAY framing knob with
## no such constraint -- changing it changes how zoomed in the camera
## feels, not whether art lands on whole screen pixels. It briefly moved to
## 83.2 (a 30% zoom-in, asked directly) while this constant deliberately
## stayed at 64.0, which would have left every consumer of
## visible_tiles_across (decoration LOD, the snow-onset-viewport-scale fix)
## measuring a stale, slightly-larger view than the real camera actually
## framed -- confirmed safe-direction at the time (over-provisions a
## little, never under) but moot now: that zoom was reverted the same day,
## reported live as visible blur (see Player.TARGET_TILE_SCREEN_PX's own
## doc comment), so the two constants coincide again.
const WORLD_TILE_SIZE := 16
const TILE_SCREEN_PX := 64.0


## How much `canvas_items` stretch magnifies everything drawn, for a window of
## this height.
static func canvas_scale(window_height: float) -> float:
	if DESIGN_HEIGHT <= 0.0:
		return 1.0
	return window_height / DESIGN_HEIGHT


static func screen_pixels_per_art_pixel(window_height: float) -> float:
	return screen_pixels_per_art_pixel_for_art_size(
		window_height, ArtResolution.DETAIL_MULTIPLIER * WORLD_TILE_SIZE
	)


## The same figure for a hypothetical art size, so a proposed change to the
## art resolution can be checked before it is made.
static func screen_pixels_per_art_pixel_for_art_size(
	window_height: float, art_tile_pixels: int
) -> float:
	if art_tile_pixels <= 0:
		return 0.0
	return (TILE_SCREEN_PX / float(art_tile_pixels)) * canvas_scale(window_height)


## Whether art pixels land squarely on screen pixels at this window height.
## Anything else means some art pixels are drawn a pixel wider than their
## neighbours, which is visible as shimmer and mush.
static func is_pixel_perfect(window_height: float) -> bool:
	return _is_whole(screen_pixels_per_art_pixel(window_height))


static func is_pixel_perfect_for_art_size(window_height: float, art_tile_pixels: int) -> bool:
	return _is_whole(screen_pixels_per_art_pixel_for_art_size(window_height, art_tile_pixels))


## How much world the player can see. Independent of window size by design:
## a bigger window renders the same view at higher fidelity rather than
## revealing more map, so a player on a 4K monitor has no advantage over one
## on a laptop.
static func visible_tiles_across(window_width: float, window_height: float) -> float:
	var scale := canvas_scale(window_height)
	if scale <= 0.0 or TILE_SCREEN_PX <= 0.0:
		return 0.0
	return window_width / (TILE_SCREEN_PX * scale)


static func _is_whole(value: float) -> bool:
	return absf(value - roundf(value)) < 0.001 and value >= 1.0
