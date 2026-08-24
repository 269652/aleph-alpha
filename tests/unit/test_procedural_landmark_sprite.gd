extends GutTest

## ProceduralLandmarkSprite: art for a settlement's well/stall/gate (see
## VillageRenderer) -- previously invisible positions NPCs walked to.

const ProceduralLandmarkSprite = preload("res://src/rendering/procedural_landmark_sprite.gd")

var generator := ProceduralLandmarkSprite.new()


func test_every_landmark_id_renders_at_its_pinned_size():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var size: Vector2i = ProceduralLandmarkSprite.SIZES[landmark_id]
		var image := generator.generate_image(landmark_id)
		assert_eq(Vector2i(image.get_width(), image.get_height()), size, "wrong size for %s" % landmark_id)


func test_is_deterministic():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		assert_eq(
			generator.generate_image(landmark_id).get_data(),
			generator.generate_image(landmark_id).get_data()
		)


func test_the_three_landmarks_look_different_from_each_other():
	var well := generator.generate_image("well")
	var stall := generator.generate_image("stall")
	var gate := generator.generate_image("gate")
	assert_ne(well.get_data(), stall.get_data())
	assert_ne(stall.get_data(), gate.get_data())
	assert_ne(well.get_data(), gate.get_data())


func test_has_transparent_corners():
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var image := generator.generate_image(landmark_id)
		assert_eq(image.get_pixel(0, 0).a, 0.0, "%s should have a transparent corner" % landmark_id)


## The well must read as a well: stone ring AND dark water core, not one
## flat blob.
func test_well_has_both_stone_and_water_pixels():
	var image := generator.generate_image("well")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.STONE_COLOR), "well should have stone pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WATER_COLOR), "well should have water pixels")


## The stall must carry both awning stripe colors.
func test_stall_awning_is_striped_in_two_colors():
	var image := generator.generate_image("stall")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.AWNING_A))
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.AWNING_B))


# -- per-occupation workspot props (see VillageRenderer, npc_planner.gd's
# FakeNpcPlanner._WORK_LOCATION_BY_OCCUPATION -- reported: "the houses...
# maybe we need... enough different blueprints", and the same follow-up ask
# to close the remaining gap: a farmer/blacksmith/fisher/herbalist's own
# workspot was an invisible position they walked to and stood on empty
# grass, unlike merchant (personal stall) and guard (shared gate), which
# both already had something real there) ---------------------------------

## field (farmer), forge (blacksmith), dock (fisher), garden (herbalist) --
## the same tag names FakeNpcPlanner._WORK_LOCATION_BY_OCCUPATION already
## uses for these occupations' work location_tag, so the prop a player sees
## is literally the place the schedule sends that villager.
func test_every_occupation_workspot_prop_exists_in_the_catalog():
	for landmark_id in ["field", "forge", "dock", "garden"]:
		assert_true(ProceduralLandmarkSprite.LANDMARK_IDS.has(landmark_id), landmark_id)


func test_every_landmark_looks_different_from_every_other():
	var seen: Array[PackedByteArray] = []
	for landmark_id in ProceduralLandmarkSprite.LANDMARK_IDS:
		var data := generator.generate_image(landmark_id).get_data()
		for other in seen:
			assert_ne(data, other, landmark_id)
		seen.append(data)


## The field must read as tilled soil with real crop growth on it, not a
## bare dirt rectangle -- a farmer's plot should look worked.
func test_field_has_both_soil_and_crop_pixels():
	var image := generator.generate_image("field")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.SOIL_COLOR), "field should have soil pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.CROP_COLOR), "field should have crop pixels")


## The forge must read as a forge: a stone furnace AND glowing embers, not
## just a grey block.
func test_forge_has_both_stone_and_ember_pixels():
	var image := generator.generate_image("forge")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.STONE_COLOR), "forge should have stone pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.EMBER_COLOR), "forge should have ember pixels")


## The dock must read as real wooden planking over water, not a plain plank
## on grass.
func test_dock_has_both_wood_and_water_pixels():
	var image := generator.generate_image("dock")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WOOD_COLOR), "dock should have wood pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.WATER_COLOR), "dock should have water pixels")


## The garden must read as a real herb bed: tilled soil AND herb foliage,
## and that foliage must be its OWN colour, not the same green a farmer's
## crop uses (they should not read as the same plot).
func test_garden_has_both_soil_and_its_own_herb_color():
	var image := generator.generate_image("garden")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.SOIL_COLOR), "garden should have soil pixels")
	assert_true(_has_color_near(image, ProceduralLandmarkSprite.HERB_COLOR), "garden should have herb pixels")
	assert_false(
		_has_color_near(image, ProceduralLandmarkSprite.CROP_COLOR),
		"garden herbs should read as their own thing, not a farmer's crop"
	)


func test_unknown_id_falls_back_to_the_well():
	assert_eq(
		generator.generate_image("not_a_landmark").get_data(),
		generator.generate_image("well").get_data()
	)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("gate")
	assert_eq(texture.get_width(), ProceduralLandmarkSprite.SIZES["gate"].x)


func _has_color_near(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.04:
				return true
	return false
