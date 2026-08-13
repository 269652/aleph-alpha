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
