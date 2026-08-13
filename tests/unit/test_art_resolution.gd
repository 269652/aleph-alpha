extends GutTest

## ArtResolution: the single factor separating "how many pixels of art a
## thing is drawn with" from "how much world it occupies" (see
## docs/concept/art_resolution.md). Phase 1 learned this the hard way by
## conflating the two on the ground plane; every entity sprite now derives
## its world size from its art size through here instead of restating a
## scale number per renderer.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


## Pinned exactly, because both directions matter: raising it collapses art
## pixels onto single screen pixels (see the chunky-pixel test below),
## lowering it loses the detail the pass exists for.
func test_detail_multiplier_is_the_pinned_pass_factor():
	assert_eq(ArtResolution.DETAIL_MULTIPLIER, 2)


## The invariant every caller depends on: scaling art by SPRITE_SCALE
## undoes exactly the DETAIL_MULTIPLIER the art was authored at.
func test_sprite_scale_exactly_undoes_the_detail_multiplier():
	assert_almost_eq(ArtResolution.SPRITE_SCALE * ArtResolution.DETAIL_MULTIPLIER, 1.0, 0.0001)


func test_art_size_scales_a_world_size_up_by_the_multiplier():
	var world := Vector2i(20, 26)
	assert_eq(ArtResolution.art_size(world), world * ArtResolution.DETAIL_MULTIPLIER)


func test_world_size_scales_an_art_size_back_down():
	var world := Vector2i(20, 26)
	assert_eq(ArtResolution.world_size(world * ArtResolution.DETAIL_MULTIPLIER), Vector2(world))


func test_art_and_world_size_round_trip():
	var world := Vector2i(13, 19)
	assert_eq(ArtResolution.world_size(ArtResolution.art_size(world)), Vector2(world))


## The ground plane (Phase 1) must use the same factor as entity sprites --
## a mismatch would make terrain and the things standing on it disagree
## about how much detail a world unit carries.
func test_terrain_uses_the_same_multiplier_as_sprites():
	assert_eq(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER)
	assert_almost_eq(TerrainRenderer.LAYER_SCALE, ArtResolution.SPRITE_SCALE, 0.0001)


# -- chunky pixels (docs/concept/pixel_art_engine.md) ------------------------
#
# The point that a first version of this pass missed: authoring art at 4x
# and scaling it back down made ONE ART PIXEL land on ONE SCREEN PIXEL, so
# nothing looked pixelated at all -- reported as "the char doesn't look like
# pixel art". 16-bit art has CHUNKY pixels: each art pixel must cover
# several screen pixels.

const Player = preload("res://scenes/player.gd")


## How many screen pixels one art pixel covers, at the game's own camera
## zoom. Must be >= 2 or the art stops reading as pixel art.
func test_one_art_pixel_covers_several_screen_pixels():
	var world_units_per_art_pixel := ArtResolution.SPRITE_SCALE
	var screen_px_per_art_pixel := world_units_per_art_pixel * Player.CAMERA_ZOOM.x
	assert_gte(
		screen_px_per_art_pixel, 2.0,
		"art pixels must stay visibly chunky, not collapse to single screen pixels"
	)


## ...but still finer than the pre-pass art, which is the whole reason for
## the resolution bump.
func test_art_is_still_more_detailed_than_before_the_pass():
	assert_gt(ArtResolution.DETAIL_MULTIPLIER, 1)
