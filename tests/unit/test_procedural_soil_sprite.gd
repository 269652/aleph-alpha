extends GutTest

## The shared soil-mound sprite under a wild crop patch (see
## docs/concept/wild_crops.md's "Status" list -- no AI art exists yet for
## ai_sprite_prompts.md's 2b soil-pile prompt, so this is a hand-drawn
## procedural fallback in the same offline-art style as ProceduralBobberSprite
## and friends, swappable for real art later with no marker changes needed).

const ProceduralSoilSprite = preload("res://src/rendering/procedural_soil_sprite.gd")

var soil: ProceduralSoilSprite


func before_each():
	soil = ProceduralSoilSprite.new()


func test_generates_a_texture_of_the_declared_size():
	var texture := soil.generate_texture(false)
	assert_not_null(texture)
	assert_eq(texture.get_width(), ProceduralSoilSprite.SIZE)
	assert_eq(texture.get_height(), ProceduralSoilSprite.SIZE)


func test_the_mound_actually_draws_something_at_its_center():
	var image := soil.generate_image(false)
	var center := ProceduralSoilSprite.SIZE / 2
	assert_gt(image.get_pixel(center, center).a, 0.0, "the mound should not be blank at its own center")


func test_generation_is_deterministic():
	var a := soil.generate_image(false)
	var b := soil.generate_image(false)
	assert_eq(a.get_data(), b.get_data())


## The disturbed state (after a pull) must actually look different from the
## undisturbed mound -- it's what tells the player something was just
## pulled out of the ground.
func test_disturbed_state_looks_different_from_undisturbed():
	var undisturbed := soil.generate_image(false)
	var disturbed := soil.generate_image(true)
	assert_ne(undisturbed.get_data(), disturbed.get_data())


func test_disturbed_center_reads_darker_as_a_hollowed_crater():
	var undisturbed := soil.generate_image(false)
	var disturbed := soil.generate_image(true)
	var center := ProceduralSoilSprite.SIZE / 2
	assert_lt(disturbed.get_pixel(center, center).v, undisturbed.get_pixel(center, center).v)


# -- final on-screen size: reported live as rendering way too big (the raw
# SIZE=24 texture drawn with no scale applied at all, next to a 16px tile --
# visibly ~1.5 tiles wide). Never bigger than a tile, and sized so it can
# plausibly cover a planted root/leaves group sitting at the same origin.

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")


func test_soil_world_width_is_smaller_than_a_full_tile():
	assert_lt(ProceduralSoilSprite.SOIL_WORLD_WIDTH, TerrainRenderer.TILE_SIZE)


func test_soil_world_scale_actually_produces_the_declared_world_width():
	assert_almost_eq(
		ProceduralSoilSprite.SOIL_WORLD_SCALE * float(ProceduralSoilSprite.SIZE),
		ProceduralSoilSprite.SOIL_WORLD_WIDTH, 0.001
	)
