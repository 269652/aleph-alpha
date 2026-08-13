extends GutTest

## ArtResolution: the single factor separating "how many pixels of art a
## thing is drawn with" from "how much world it occupies" (see
## docs/concept/art_resolution.md). Phase 1 learned this the hard way by
## conflating the two on the ground plane; every entity sprite now derives
## its world size from its art size through here instead of restating a
## scale number per renderer.

const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func test_detail_multiplier_is_the_4x_pass_factor():
	assert_eq(ArtResolution.DETAIL_MULTIPLIER, 4)


## The invariant every caller depends on: scaling art by SPRITE_SCALE
## undoes exactly the DETAIL_MULTIPLIER the art was authored at.
func test_sprite_scale_exactly_undoes_the_detail_multiplier():
	assert_almost_eq(ArtResolution.SPRITE_SCALE * ArtResolution.DETAIL_MULTIPLIER, 1.0, 0.0001)


func test_art_size_scales_a_world_size_up_by_the_multiplier():
	assert_eq(ArtResolution.art_size(Vector2i(20, 26)), Vector2i(80, 104))


func test_world_size_scales_an_art_size_back_down():
	assert_eq(ArtResolution.world_size(Vector2i(80, 104)), Vector2(20, 26))


func test_art_and_world_size_round_trip():
	var world := Vector2i(13, 19)
	assert_eq(ArtResolution.world_size(ArtResolution.art_size(world)), Vector2(world))


## The ground plane (Phase 1) must use the same factor as entity sprites --
## a mismatch would make terrain and the things standing on it disagree
## about how much detail a world unit carries.
func test_terrain_uses_the_same_multiplier_as_sprites():
	assert_eq(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER)
	assert_almost_eq(TerrainRenderer.LAYER_SCALE, ArtResolution.SPRITE_SCALE, 0.0001)
