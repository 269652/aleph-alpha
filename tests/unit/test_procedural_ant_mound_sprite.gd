extends GutTest

## The visible mound over one AntColony entrance (see docs/concept/
## soil_fauna.md's "Ants: myrmecochory" -- a colony was previously a pure
## background population effect with no rendered presence at all). Same
## offline hand-drawn procedural style as ProceduralSoilSprite/
## ProceduralDecomposerSprite -- a small dirt dome, distinguished from a
## plain tilled-soil mound by a dark entrance hole so it reads as "something
## lives here", not just disturbed ground.

const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var mound: ProceduralAntMoundSprite


func before_each():
	mound = ProceduralAntMoundSprite.new()


func test_generates_a_texture_of_the_declared_size():
	var texture := mound.generate_texture()
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralAntMoundSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralAntMoundSprite.SIZE)


func test_the_mound_actually_draws_something_at_its_center():
	var image := mound.generate_image()
	var center := ProceduralAntMoundSprite.SIZE / 2
	assert_gt(image.get_pixel(center, center).a, 0.0, "the mound should not be blank at its own center")


func test_generation_is_deterministic():
	var a := mound.generate_image()
	var b := mound.generate_image()
	assert_eq(a.get_data(), b.get_data())


## The one thing distinguishing this from a plain soil mound: a real,
## visibly-darker entrance hole, not just a uniformly-lit dome.
func test_the_entrance_reads_darker_than_the_mound_body():
	var image := mound.generate_image()
	var center := Vector2(ProceduralAntMoundSprite.SIZE / 2.0, ProceduralAntMoundSprite.SIZE / 2.0)
	var entrance_pixel := center + ProceduralAntMoundSprite.ENTRANCE_OFFSET
	var body_pixel := center + Vector2(-ProceduralAntMoundSprite.ENTRANCE_OFFSET.x, -ProceduralAntMoundSprite.ENTRANCE_OFFSET.y)
	assert_lt(
		image.get_pixel(int(entrance_pixel.x), int(entrance_pixel.y)).v,
		image.get_pixel(int(body_pixel.x), int(body_pixel.y)).v
	)


## Same "black blob" failure mode ProceduralDecomposerSprite's ant/bug fill
## once fell into (fill color landing on top of PixelPalette.OUTLINE) -- the
## entrance is DELIBERATELY dark, but it must not be so dark it becomes
## indistinguishable from the silhouette's own outline ring.
func test_entrance_color_is_distinguishable_from_the_outline():
	var palette := PixelPalette.new()
	var outline := palette.outline_color()
	var distance := (
		absf(ProceduralAntMoundSprite.ENTRANCE_COLOR.r - outline.r)
		+ absf(ProceduralAntMoundSprite.ENTRANCE_COLOR.g - outline.g)
		+ absf(ProceduralAntMoundSprite.ENTRANCE_COLOR.b - outline.b)
	)
	assert_gt(distance, 0.05)


# -- final on-screen size: the exact "gigantic" failure class already hit
# once for ProceduralSoilSprite and once for DecomposerMarker's own ant/bug
# sprite -- never left to a marker to forget to scale down. A mound's own
# size is no longer one flat constant -- it grows with the colony (see
# docs/concept/soil_fauna.md "Mound size grows with the colony"),
# world_width_for(growth_fraction) taking AntColony.growth_fraction_at's
# own [0,1] output. -----------------------------------------------------

func test_mound_world_width_is_smaller_than_a_full_tile_even_at_max_growth():
	assert_lt(ProceduralAntMoundSprite.world_width_for(1.0), TerrainRenderer.TILE_SIZE)


func test_mound_world_scale_actually_produces_the_declared_world_width():
	var fraction := 0.6
	assert_almost_eq(
		ProceduralAntMoundSprite.world_scale_for(fraction) * float(ProceduralAntMoundSprite.SIZE),
		ProceduralAntMoundSprite.world_width_for(fraction), 0.001
	)


## A founding colony (growth_fraction 0) still reads as a real, visible
## dirt pile -- close to the previous pass's own flat 5.25, not a step
## backward at the weakest end (see that pass's own 2026-09-05 follow-up:
## a literal halving of the ORIGINAL size overshot into invisible).
func test_mound_world_width_at_zero_growth_is_pinned_to_the_founding_size():
	assert_eq(ProceduralAntMoundSprite.world_width_for(0.0), ProceduralAntMoundSprite.MOUND_WORLD_WIDTH_MIN)
	assert_almost_eq(ProceduralAntMoundSprite.MOUND_WORLD_WIDTH_MIN, 4.0, 0.001)


## Requested directly: mounds should "grow with the colony" -- clamped to
## [0,1], so a growth_fraction beyond 1.0 (should never happen, but not
## trusted blindly) never draws a mound bigger than the real maximum.
func test_mound_world_width_grows_with_growth_fraction():
	assert_gt(
		ProceduralAntMoundSprite.world_width_for(1.0),
		ProceduralAntMoundSprite.world_width_for(0.0),
		"a thriving colony's mound should read bigger than a founding one's"
	)
	assert_almost_eq(
		ProceduralAntMoundSprite.world_width_for(1.0), ProceduralAntMoundSprite.world_width_for(2.0), 0.001
	)


## Requested directly: "it should be half a human high" -- pinned to
## CharacterView's own real player height (the same "read against the
## player" convention StoneSize/ProceduralFlowerSprite already establish),
## not an independently-eyeballed number, and cross-checked here so the
## two can't silently drift apart.
func test_mound_world_width_at_max_growth_is_half_the_player_height():
	assert_almost_eq(
		ProceduralAntMoundSprite.world_width_for(1.0),
		ProceduralAntMoundSprite.PLAYER_WORLD_HEIGHT_PX * 0.5, 0.001
	)


## Growth reads fastest early and flattens out approaching full size --
## the exact same `pow` exaggeration technique and reasoning
## StoneSize.world_height_px already uses (below 1.0 front-loads the
## visual range onto the early part of growth). Pinned as a real
## inequality (not GROWTH_EXAGGERATION's own literal value, which is a
## tuned constant, not a load-bearing one) so the CURVE SHAPE stays
## correct even if that constant is re-tuned later.
func test_growth_reads_faster_early_than_late():
	var early_gain := ProceduralAntMoundSprite.world_width_for(0.5) - ProceduralAntMoundSprite.world_width_for(0.0)
	var late_gain := ProceduralAntMoundSprite.world_width_for(1.0) - ProceduralAntMoundSprite.world_width_for(0.5)
	assert_gt(early_gain, late_gain, "the first half of growth should read as a bigger visual jump than the second half")
