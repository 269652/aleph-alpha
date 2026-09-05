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
# sprite -- never left to a marker to forget to scale down. ---------------

func test_mound_world_width_is_smaller_than_a_full_tile():
	assert_lt(ProceduralAntMoundSprite.MOUND_WORLD_WIDTH, TerrainRenderer.TILE_SIZE)


func test_mound_world_scale_actually_produces_the_declared_world_width():
	assert_almost_eq(
		ProceduralAntMoundSprite.MOUND_WORLD_SCALE * float(ProceduralAntMoundSprite.SIZE),
		ProceduralAntMoundSprite.MOUND_WORLD_WIDTH, 0.001
	)


## Halved from its old value (7.0 -> 3.5) -- reported oversized once mounds
## were actually visible in play (see docs/concept/soil_fauna.md "Ants at
## half their old size").
func test_mound_world_width_is_pinned_to_its_new_halved_value():
	assert_eq(ProceduralAntMoundSprite.MOUND_WORLD_WIDTH, 3.5)
