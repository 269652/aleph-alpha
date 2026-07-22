extends GutTest

const AnimScript := preload("res://src/rendering/procedural_animal_animation.gd")

var anim


func before_each() -> void:
	anim = AnimScript.new()


func _pixel_diff(a: Image, b: Image) -> int:
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				diff += 1
	return diff


func test_actions_constant_lists_all_five() -> void:
	assert_eq(AnimScript.ACTIONS, ["walk", "attack", "eat", "swim", "drink"])


func test_every_action_produces_declared_frame_count() -> void:
	for action in AnimScript.ACTIONS:
		var frames: Array = anim.generate_frames("boar", action, 7)
		assert_eq(frames.size(), AnimScript.FRAME_COUNTS[action],
			"frame count for %s" % action)
		assert_gte(frames.size(), 2, "at least 2 frames for %s" % action)


func test_frames_within_action_differ() -> void:
	for action in AnimScript.ACTIONS:
		var frames: Array = anim.generate_frames("lynx", action, 3)
		for i in range(1, frames.size()):
			assert_gt(_pixel_diff(frames[0], frames[i]), 0,
				"frame %d differs from frame 0 for %s" % [i, action])


func test_deterministic_per_species_action_seed() -> void:
	var a: Array = anim.generate_frames("predator", "walk", 42)
	var b: Array = anim.generate_frames("predator", "walk", 42)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(_pixel_diff(a[i], b[i]), 0, "frame %d identical" % i)


func test_swim_frames_have_blue_pixels_in_lower_half() -> void:
	var frames: Array = anim.generate_frames("herbivore", "swim", 1)
	for f in frames.size():
		var frame: Image = frames[f]
		var found_blue := false
		for y in range(frame.get_height() / 2, frame.get_height()):
			for x in frame.get_width():
				var c: Color = frame.get_pixel(x, y)
				if c.a > 0.5 and c.b > c.r and c.b > c.g:
					found_blue = true
		assert_true(found_blue, "swim frame %d has blue lower-half pixels" % f)


func test_unknown_action_falls_back_to_walk() -> void:
	var unknown: Array = anim.generate_frames("boar", "moonwalk", 5)
	var walk: Array = anim.generate_frames("boar", "walk", 5)
	assert_eq(unknown.size(), walk.size())
	for i in walk.size():
		assert_eq(_pixel_diff(unknown[i], walk[i]), 0, "frame %d matches walk" % i)


func test_generate_textures_returns_image_textures() -> void:
	var textures: Array = anim.generate_textures("lynx", "eat", 9)
	assert_eq(textures.size(), AnimScript.FRAME_COUNTS["eat"])
	for t in textures:
		assert_true(t is ImageTexture)
