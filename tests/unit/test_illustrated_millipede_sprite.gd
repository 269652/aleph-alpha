extends GutTest

## Real hand-illustrated millipede sprite-sheet animation (assets/sprites/
## animals/millipede.png) -- see docs/concept/soil_fauna.md "Millipedes: a
## dedicated autumn leaf-litter decomposer". Mirrors IllustratedCaterpillar
## Sprite/IllustratedWormSprite's own shape exactly: a millipede carries no
## CreatureMarker/AnimalAnatomy stack, and there is only ever one kind of
## millipede in this game, so this skips the species dimension
## IllustratedDecomposerSprite/IllustratedAnimalSprite both carry and keys
## everything by action alone.
##
## The sheet shares worm.png/caterpillar.png's exact 1536x1024, 8-column x
## 4-row grid (confirmed directly against the PNG header), sliced by the
## same known-grid arithmetic rather than SpriteSheetSlicer.detect_frames'
## content-gap heuristic.

const IllustratedMillipedeSprite = preload("res://src/rendering/illustrated_millipede_sprite.gd")

var sprite: IllustratedMillipedeSprite


func before_each():
	sprite = IllustratedMillipedeSprite.new()


func test_has_action_recognizes_all_four_animations():
	for action in ["crawl", "alert", "curl", "crushed"]:
		assert_true(sprite.has_action(action), action)


func test_has_action_rejects_unknown_actions():
	assert_false(sprite.has_action("fly"))
	assert_false(sprite.has_action(""))


func test_generate_textures_returns_eight_frames_per_action():
	for action in ["crawl", "alert", "curl", "crushed"]:
		assert_eq(sprite.generate_textures(action).size(), 8, action)


func test_generate_textures_is_empty_for_an_unknown_action():
	assert_eq(sprite.generate_textures("fly").size(), 0)


func test_every_frame_of_every_action_has_real_content():
	for action in ["crawl", "alert", "curl", "crushed"]:
		var frames := sprite.generate_textures(action)
		for i in frames.size():
			assert_true(_has_opaque_pixels(frames[i]), "%s frame %d is blank" % [action, i])


## Same regression shape as test_illustrated_caterpillar_sprite.gd's own
## magenta-despill tests.
func test_frames_have_no_leftover_magenta_background():
	for action in ["crawl", "alert", "curl", "crushed"]:
		var frame: Image = sprite.generate_textures(action)[0].get_image()
		assert_almost_eq(frame.get_pixel(0, 0).a, 0.0, 0.01, "%s top-left corner should be transparent" % action)
		assert_almost_eq(
			frame.get_pixel(frame.get_width() - 1, 0).a, 0.0, 0.01,
			"%s top-right corner should be transparent" % action
		)
		var magenta_survivors := 0
		for y in frame.get_height():
			for x in frame.get_width():
				var c := frame.get_pixel(x, y)
				if c.a > 0.5 and c.r >= 0.85 and c.b >= 0.85 and c.g <= 0.15:
					magenta_survivors += 1
		assert_eq(magenta_survivors, 0, "%s: no opaque magenta pixel should survive chroma-keying" % action)


func test_every_generated_frame_shares_one_canvas_size():
	var reference: Vector2 = sprite.generate_textures("crawl")[0].get_size()
	for action in ["crawl", "alert", "curl", "crushed"]:
		for frame in sprite.generate_textures(action):
			assert_eq(frame.get_size(), reference, action)


func test_frames_are_cached_not_rebuilt_per_call():
	var a := sprite.generate_textures("crawl")
	var b := sprite.generate_textures("crawl")
	assert_same(a[0], b[0])


## alert/curl/crushed must each actually look different from a flat crawl,
## not be 3 copies of one pose wearing different names.
func test_alert_curl_and_crushed_are_visually_distinct_from_crawl():
	var crawl_frame: PackedByteArray = sprite.generate_textures("crawl")[4].get_image().get_data()
	for action in ["alert", "curl", "crushed"]:
		var frame: PackedByteArray = sprite.generate_textures(action)[4].get_image().get_data()
		assert_ne(frame, crawl_frame, action)


## A small, real-world creature size -- comfortably in the same tiny-
## invertebrate range this codebase already uses for its other small ground
## crawlers (IllustratedCaterpillarSprite/IllustratedWormSprite), bounded
## rather than pinned to one number since there is no prior art to match
## continuity against.
func test_world_scale_reads_as_a_small_creature():
	var world_width: float = sprite.world_scale() * _content_width_px(sprite.generate_textures("crawl")[0])
	assert_between(world_width, 2.0, 8.0, "a millipede should read about worm-sized, not gigantic or invisible")


func _content_width_px(texture: Texture2D) -> float:
	var image := texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1)


func _has_opaque_pixels(texture: Texture2D) -> bool:
	var image := texture.get_image()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				return true
	return false
