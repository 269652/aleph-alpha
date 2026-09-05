extends GutTest

## Player's Camera2D zoom -- a tuned value (CLAUDE.md: tuned values/thresholds
## must be tested/pinned constants, never eyeballed comments), so it lives as
## Player.CAMERA_ZOOM and is applied in _ready() rather than sitting as a bare
## number buried in player.tscn.
##
## CAMERA_ZOOM is DERIVED from Player.TARGET_TILE_SCREEN_PX (the actual
## tuned/eyeballed value) divided by TerrainRenderer.TILE_SIZE, not a bare
## zoom number -- a source art resolution bump (see docs/concept/
## art_resolution.md) changes TILE_SIZE, and a fixed zoom number would then
## silently show more/less of each tile than intended (exactly what
## happened when TILE_SIZE went 16->64 with zoom left at a now-stale 4:
## tiles rendered 4x too big on screen, "everything is zoomed in 4x too
## much" -- see the regression test below).

const PlayerScene = preload("res://scenes/player.tscn")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var player: Player


func before_each():
	player = PlayerScene.instantiate()
	add_child(player)


func after_each():
	remove_child(player)
	player.free()


func test_camera_zoom_is_wired_from_the_tuned_constant():
	var camera := player.get_node("Camera2D") as Camera2D
	assert_eq(camera.zoom, Player.CAMERA_ZOOM)


## Pins the actual eyeballed value (TARGET_TILE_SCREEN_PX), not zoom itself --
## zoom is a derived quantity, see the file header comment. The art-resolution
## pass does NOT change how much world fits on screen, only how many art
## pixels are painted per tile (see TerrainRenderer.ART_TILE_SIZE /
## LAYER_SCALE) -- this constant is the one deliberate exception, a real
## framing/composition tuning asked for directly.
##
## Was briefly 83.2 (2026-09-05): asked directly to "zoom in 30% so trees
## become relatively bigger" alongside shrinking the character (see
## CharacterView.TARGET_HEIGHT_FRACTION_OF_TREE). Reverted the same day,
## reported live as real, visible blur: at exactly 64.0 (CAMERA_ZOOM 4.0x),
## ArtResolution.SPRITE_SCALE(0.5) * CAMERA_ZOOM.x lands on a whole 2.0
## screen pixels per source texel for every SPRITE_SCALE-path entity
## (terrain, the tree canopy, the bobber); at 83.2 (5.2x) that ratio is a
## non-whole 2.6, which nearest-neighbour filtering shows as soft, uneven
## edges rather than clean blocks -- the same failure mode this codebase
## already fixed once for the character-creator portrait
## (STANDARD_PORTRAIT_SCALE, docs/progress.md). With ArtResolution.
## DETAIL_MULTIPLIER=2, the only zoom values that stay whole are multiples
## of 4x, so there is no "close to 30%" alternative -- see player.gd's own
## comment for the 4x/8x tradeoff this ruled out. "Trees relatively bigger"
## survives the revert intact: that ratio comes entirely from
## TARGET_HEIGHT_FRACTION_OF_TREE, never from zoom (zoom scales the
## character and every tree by the identical factor, so it cancels out of
## their ratio) -- confirmed by rendering a real frame at both zoom levels.
func test_target_tile_screen_size_matches_the_current_tuning():
	assert_almost_eq(Player.TARGET_TILE_SCREEN_PX, 64.0, 0.001)


## Pins the property the revert exists to restore: a whole number of screen
## pixels per source texel for every ArtResolution.SPRITE_SCALE-path entity,
## at the actual live zoom -- not just re-asserting the literal 64.0 above,
## which could pass by coincidence if SPRITE_SCALE or DETAIL_MULTIPLIER ever
## moved too.
func test_camera_zoom_keeps_sprite_scale_path_art_pixel_aligned():
	var art_resolution := load("res://src/rendering/art_resolution.gd")
	var screen_px_per_texel: float = art_resolution.SPRITE_SCALE * Player.CAMERA_ZOOM.x
	assert_almost_eq(
		screen_px_per_texel, roundf(screen_px_per_texel), 0.0001,
		"screen pixels per source texel is %.4f, not a whole number -- nearest-neighbour will show soft, uneven edges" % screen_px_per_texel
	)


## Regression: TILE_SIZE going 16->64 (see docs/concept/art_resolution.md)
## must NOT change how big a tile looks on screen -- only how much real
## pixel detail is packed into that same footprint. A bare zoom number left
## over from before the resolution bump made every tile render 4x too big
## ("everything is zoomed in 4x too much, water tiles are huge").
func test_camera_zoom_keeps_the_on_screen_tile_size_constant_across_a_resolution_bump():
	var on_screen_tile_px: float = TerrainRenderer.TILE_SIZE * Player.CAMERA_ZOOM.x
	assert_almost_eq(on_screen_tile_px, Player.TARGET_TILE_SCREEN_PX, 0.01)
