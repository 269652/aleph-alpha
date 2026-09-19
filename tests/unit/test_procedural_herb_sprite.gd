extends GutTest

## ProceduralHerbSprite: the herbalist's crop, drawn.
##
## docs/concept/village_farms.md carried this as an honest gap -- "A herb
## plot renders as bare tilled soil ... an asset question, not a logic one"
## -- and it was reported in play with the field in shot: "it plows the soil
## but then ... nothing gets planted, nothing grows and nothing gets
## harvested". Everything WAS happening; none of it was drawn (see
## tools/probe_village_farming.gd).
##
## No illustrated herb art exists, so this is a hand-drawn procedural sprite
## in exactly the ProceduralSoilSprite/ProceduralLandmarkSprite style this
## codebase already uses for art that has not been authored yet -- swappable
## for real art later behind IllustratedCropSprite's own has_crop seam, with
## no marker change needed.

const ProceduralHerbSprite = preload("res://src/rendering/procedural_herb_sprite.gd")
const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")

var generator := ProceduralHerbSprite.new()


func test_draws_one_image_per_growth_stage():
	assert_eq(ProceduralHerbSprite.STAGES, 3, "seedling, vegetative, mature")
	for stage in ProceduralHerbSprite.STAGES:
		var image := generator.generate_image(stage)
		assert_eq(
			Vector2i(image.get_width(), image.get_height()), ProceduralHerbSprite.SIZE,
			"stage %d" % stage
		)


func test_is_deterministic():
	for stage in ProceduralHerbSprite.STAGES:
		assert_eq(
			generator.generate_image(stage).get_data(),
			generator.generate_image(stage).get_data()
		)


func test_has_transparent_corners():
	for stage in ProceduralHerbSprite.STAGES:
		var image := generator.generate_image(stage)
		assert_eq(image.get_pixel(0, 0).a, 0.0, "stage %d" % stage)


## An out-of-range stage clamps rather than erroring -- the same contract
## IllustratedCropSprite.leaf_texture already offers its caller.
func test_an_out_of_range_stage_clamps_to_a_real_one():
	assert_eq(generator.generate_image(-5).get_data(), generator.generate_image(0).get_data())
	assert_eq(
		generator.generate_image(99).get_data(),
		generator.generate_image(ProceduralHerbSprite.STAGES - 1).get_data()
	)


## The three stages have to read as growth, not as three pictures of the
## same plant.
func test_every_growth_stage_looks_different_from_every_other():
	var seen: Array[PackedByteArray] = []
	for stage in ProceduralHerbSprite.STAGES:
		var data := generator.generate_image(stage).get_data()
		for other in seen:
			assert_ne(data, other, "stage %d" % stage)
		seen.append(data)


## ...and the growth has to go the right way: a ripe herb is a bigger plant
## than a seedling, measured in real drawn pixels rather than asserted.
func test_a_ripe_herb_is_a_bigger_plant_than_a_seedling():
	var seedling := _drawn_pixels(generator.generate_image(0))
	var ripe := _drawn_pixels(generator.generate_image(ProceduralHerbSprite.STAGES - 1))
	assert_gt(ripe, seedling, "a mature herb should cover more ground than a seedling")


## The herbalist's bed and the herbalist's own workspot prop must read as
## the same plant: ProceduralLandmarkSprite's garden already established
## what a herb looks like in this world, and a bed in its own second green
## would be two plants for one crop.
func test_a_herb_is_the_same_colour_the_herbalists_garden_prop_already_uses():
	assert_eq(ProceduralHerbSprite.HERB_COLOR, ProceduralLandmarkSprite.HERB_COLOR)
	assert_true(
		_has_color_near(generator.generate_image(ProceduralHerbSprite.STAGES - 1), ProceduralHerbSprite.HERB_COLOR),
		"a herb should be drawn in the herb colour"
	)


## The plant grows UP out of the bed it is rooted in, so its own bottom row
## has to carry the stem -- a sprite a marker pins by its root would
## otherwise float.
func test_the_stem_reaches_the_bottom_of_the_canvas():
	var image := generator.generate_image(ProceduralHerbSprite.STAGES - 1)
	var bottom := image.get_height() - 1
	var found := false
	for x in image.get_width():
		if image.get_pixel(x, bottom).a > 0.0:
			found = true
			break
	assert_true(found, "the stem has to reach the ground it is planted in")


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture(0)
	assert_eq(texture.get_width(), ProceduralHerbSprite.SIZE.x)


## How wide a herb reads ON THE GROUND -- the same world size an
## illustrated crop's leaves already use, so a herb bed and a carrot bed sit
## at one scale rather than two (see IllustratedCropSprite.LEAF_WORLD_SIZE,
## itself re-tuned once after "huge potato crops above soil" was reported).
func test_a_herb_reads_at_the_same_world_size_as_an_illustrated_crops_leaves():
	var IllustratedCropSprite = load("res://src/rendering/illustrated_crop_sprite.gd")
	assert_almost_eq(
		ProceduralHerbSprite.HERB_WORLD_WIDTH, IllustratedCropSprite.LEAF_WORLD_SIZE, 0.001
	)
	assert_almost_eq(
		ProceduralHerbSprite.world_scale() * float(ProceduralHerbSprite.SIZE.x),
		ProceduralHerbSprite.HERB_WORLD_WIDTH, 0.001
	)


func _drawn_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _has_color_near(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.04:
				return true
	return false
