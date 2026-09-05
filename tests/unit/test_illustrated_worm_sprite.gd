extends GutTest

## Real hand-illustrated worm sprite-sheet animation (assets/sprites/
## animals/worm.png) -- see docs/concept/soil_fauna.md's "Illustrated worm
## sprite: crawl, emerge, retreat, die". Mirrors IllustratedDecomposerSprite's
## own shape (a worm carries no CreatureMarker/AnimalAnatomy stack, same as
## ants/bugs) rather than IllustratedAnimalSprite's -- but skips the species
## dimension entirely, since there is only ever one kind of worm.
##
## The sheet is a known, perfectly regular 8-column x 4-row grid, sliced by
## grid arithmetic rather than SpriteSheetSlicer.detect_frames' content-gap
## heuristic (see the class's own doc comment and tools/probe_worm_sheet.gd
## for why: the die row's early coiled poses have an internal notch that
## heuristic misreads as a frame boundary).

const IllustratedWormSprite = preload("res://src/rendering/illustrated_worm_sprite.gd")
const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")

var sprite: IllustratedWormSprite


func before_each():
	sprite = IllustratedWormSprite.new()


func test_has_action_recognizes_all_four_animations():
	for action in ["crawl", "emerge", "retreat", "die"]:
		assert_true(sprite.has_action(action), action)


func test_has_action_rejects_unknown_actions():
	assert_false(sprite.has_action("fly"))
	assert_false(sprite.has_action(""))


func test_generate_textures_returns_eight_frames_per_action():
	for action in ["crawl", "emerge", "retreat", "die"]:
		assert_eq(sprite.generate_textures(action).size(), 8, action)


func test_generate_textures_is_empty_for_an_unknown_action():
	assert_eq(sprite.generate_textures("fly").size(), 0)


func test_every_frame_of_every_action_has_real_content():
	for action in ["crawl", "emerge", "retreat", "die"]:
		var frames := sprite.generate_textures(action)
		for i in frames.size():
			assert_true(_has_opaque_pixels(frames[i]), "%s frame %d is blank" % [action, i])


## Same regression shape as test_illustrated_animal_sprite.gd's sheep/wolf
## magenta-despill tests: one assertion that the corners read fully
## transparent, one full-image sweep for any surviving opaque magenta pixel.
func test_frames_have_no_leftover_magenta_background():
	for action in ["crawl", "emerge", "retreat", "die"]:
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
	for action in ["crawl", "emerge", "retreat", "die"]:
		for frame in sprite.generate_textures(action):
			assert_eq(frame.get_size(), reference, action)


func test_frames_are_cached_not_rebuilt_per_call():
	var a := sprite.generate_textures("crawl")
	var b := sprite.generate_textures("crawl")
	assert_same(a[0], b[0])


## The emerge row's own frame 0 (barely a nose above the soil) and frame 7
## (the whole body out) must actually differ -- a real growth, not 8 copies
## of one pose. Same for retreat (frame 0 fully out, frame 7 nearly gone)
## and die (frame 0 curled, frame 7 flattened).
func test_first_and_last_frames_differ_within_a_transitional_action():
	for action in ["emerge", "retreat", "die"]:
		var frames := sprite.generate_textures(action)
		assert_ne(frames[0].get_image().get_data(), frames[7].get_image().get_data(), action)


func test_world_scale_matches_the_procedural_worms_own_intended_length():
	# Switching to real art is a pure art upgrade, not a sudden size change
	# -- same reasoning the ant/beetle/wolf illustrated swaps already used.
	assert_almost_eq(
		sprite.world_scale() * _content_width_px(sprite.generate_textures("crawl")[0]),
		ProceduralWormSprite.WORLD_LENGTH_TILES * ProceduralWormSprite.TILE_SIZE,
		0.5
	)


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
