extends GutTest

## Real hand-illustrated grass frog sprite-sheet animation (assets/sprites/
## frogs/grass_frog.png) -- part of the seasonal-behavior epic's phase 10
## (docs/concept/seasonal_behavior.md): a grass frog is brand new to the
## game, built from art that had zero code references before this. Mirrors
## IllustratedCaterpillarSprite's own shape exactly: no CreatureMarker/
## AnimalAnatomy stack, and -- like the caterpillar/worm -- there is only
## ever one kind of frog in this game, so this skips the species dimension
## and keys everything by action alone.
##
## grass_frog.png shares caterpillar.png/worm.png's exact 1536x1024,
## 8-column x 4-row grid (confirmed dimension-identical), sliced by the same
## known-grid arithmetic rather than SpriteSheetSlicer.detect_frames'
## content-gap heuristic -- confirmed with a temporary probe script (deleted
## after use, never committed) that dumped every one of the 32 cells to disk
## and visually confirmed each row's real content before this shipped:
##   row 1 "idle" -- sitting, a slight turn across its 8 frames: the settled
##     resting pose ambient wander plays.
##   row 2 "hop" -- crouches, leaps into a stretched mid-air pose, lands back
##     in a crouch: real frog locomotion, not a walk cycle (frogs don't walk).
##   row 3 "eat" -- tongue shoots out to catch a fly mid-sequence: the real
##     feeding pose.
##   row 4 "croak" -- throat/vocal sac visibly inflates: a real frog call,
##     not decorative filler.

const IllustratedGrassFrogSprite = preload("res://src/rendering/illustrated_grass_frog_sprite.gd")

var sprite: IllustratedGrassFrogSprite


func before_each():
	sprite = IllustratedGrassFrogSprite.new()


func test_has_action_recognizes_all_four_animations():
	for action in ["idle", "hop", "eat", "croak"]:
		assert_true(sprite.has_action(action), action)


func test_has_action_rejects_unknown_actions():
	assert_false(sprite.has_action("fly"))
	assert_false(sprite.has_action(""))


func test_generate_textures_returns_eight_frames_per_action():
	for action in ["idle", "hop", "eat", "croak"]:
		assert_eq(sprite.generate_textures(action).size(), 8, action)


func test_generate_textures_is_empty_for_an_unknown_action():
	assert_eq(sprite.generate_textures("fly").size(), 0)


func test_every_frame_of_every_action_has_real_content():
	for action in ["idle", "hop", "eat", "croak"]:
		var frames := sprite.generate_textures(action)
		for i in frames.size():
			assert_true(_has_opaque_pixels(frames[i]), "%s frame %d is blank" % [action, i])


## Same regression shape as test_illustrated_caterpillar_sprite.gd's own
## magenta-despill tests.
func test_frames_have_no_leftover_magenta_background():
	for action in ["idle", "hop", "eat", "croak"]:
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
	var reference: Vector2 = sprite.generate_textures("idle")[0].get_size()
	for action in ["idle", "hop", "eat", "croak"]:
		for frame in sprite.generate_textures(action):
			assert_eq(frame.get_size(), reference, action)


func test_frames_are_cached_not_rebuilt_per_call():
	var a := sprite.generate_textures("idle")
	var b := sprite.generate_textures("idle")
	assert_same(a[0], b[0])


## hop/eat/croak must each actually look different from idle, not be 3
## copies of one pose wearing different names -- hop's mid-sequence frame is
## a stretched leap, eat's shows the tongue extended toward a fly, croak's
## shows an inflated throat sac (see the class's own doc comment for the
## visual confirmation this pins).
func test_hop_eat_and_croak_are_visually_distinct_from_idle():
	var idle_frame: PackedByteArray = sprite.generate_textures("idle")[4].get_image().get_data()
	for action in ["hop", "eat", "croak"]:
		var frame: PackedByteArray = sprite.generate_textures(action)[4].get_image().get_data()
		assert_ne(frame, idle_frame, action)


## A small real-world creature -- a common grass frog's body is bigger than
## a caterpillar/worm/earthworm (IllustratedCaterpillarSprite/
## IllustratedWormSprite's own WORLD_LENGTH_TILES is 0.32) but nowhere near
## a mouse-or-larger quadruped, so bounded a little above their band rather
## than pinned to one exact number (there is no earlier
## ProceduralGrassFrogSprite to preserve continuity with -- this is a brand
## new creature).
func test_world_scale_reads_as_a_small_creature_bigger_than_a_caterpillar():
	var world_width: float = sprite.world_scale() * _content_width_px(sprite.generate_textures("idle")[0])
	assert_between(world_width, 4.0, 10.0, "a grass frog should read a bit bigger than a caterpillar, not tiny or gigantic")


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
