extends GutTest

## Real illustrated art for ants and carrion bugs -- see DecomposerMarker,
## docs/concept/carrion.md. Same "hand-drawn sheet -> SpriteSheetSlicer ->
## cached frames" shape as IllustratedAnimalSprite/IllustratedStoneSprite,
## without the CreatureMarker/AnimalAnatomy coupling neither is built on.

const IllustratedDecomposerSprite = preload("res://src/rendering/illustrated_decomposer_sprite.gd")

var sprite: IllustratedDecomposerSprite


func before_each():
	sprite = IllustratedDecomposerSprite.new()


func test_has_species_true_for_ant_and_bug():
	assert_true(sprite.has_species("ant"))
	assert_true(sprite.has_species("bug"))


func test_has_species_false_for_an_unregistered_species():
	assert_false(sprite.has_species("beetle"))
	assert_false(sprite.has_species("spider"))


func test_both_species_face_left():
	assert_true(sprite.faces_left("ant"))
	assert_true(sprite.faces_left("bug"))


func test_faces_left_is_false_for_an_unregistered_species():
	assert_false(sprite.faces_left("spider"))


func test_ant_has_walk_carry_and_idle_art():
	assert_true(sprite.has_action("ant", "walk"))
	assert_true(sprite.has_action("ant", "carry"))
	assert_true(sprite.has_action("ant", "idle"))


func test_bug_has_walk_and_idle_but_no_carry_art():
	assert_true(sprite.has_action("bug", "walk"))
	assert_true(sprite.has_action("bug", "idle"))
	assert_false(sprite.has_action("bug", "carry"))


func test_has_action_false_for_an_unregistered_species():
	assert_false(sprite.has_action("spider", "walk"))


func test_generate_textures_returns_six_walk_frames_for_ant():
	assert_eq(sprite.generate_textures("ant", "walk").size(), 6)


func test_generate_textures_returns_six_carry_frames_for_ant():
	assert_eq(sprite.generate_textures("ant", "carry").size(), 6)


func test_generate_textures_returns_four_idle_frames_for_ant():
	assert_eq(sprite.generate_textures("ant", "idle").size(), 4)


func test_generate_textures_returns_six_walk_frames_for_bug():
	assert_eq(sprite.generate_textures("bug", "walk").size(), 6)


func test_generate_textures_returns_four_idle_frames_for_bug():
	assert_eq(sprite.generate_textures("bug", "idle").size(), 4)


func test_generate_textures_returns_empty_for_an_action_with_no_art():
	assert_eq(sprite.generate_textures("bug", "carry").size(), 0)


func test_generate_textures_returns_empty_for_an_unregistered_species():
	assert_eq(sprite.generate_textures("spider", "walk").size(), 0)


func test_every_frame_shares_the_same_canvas_size():
	for frame in sprite.generate_textures("ant", "walk"):
		assert_eq(Vector2i(frame.get_width(), frame.get_height()), IllustratedDecomposerSprite.CANVAS_SIZE)
	for frame in sprite.generate_textures("bug", "idle"):
		assert_eq(Vector2i(frame.get_width(), frame.get_height()), IllustratedDecomposerSprite.CANVAS_SIZE)


func test_generate_textures_returns_the_same_cached_instance_on_repeated_calls():
	var first := sprite.generate_textures("ant", "walk")
	var second := sprite.generate_textures("ant", "walk")
	assert_eq(first[0], second[0])


func test_every_walk_frame_actually_draws_something():
	for frame in sprite.generate_textures("ant", "walk"):
		var image := frame.get_image()
		var has_opaque_pixel := false
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					has_opaque_pixel = true
					break
			if has_opaque_pixel:
				break
		assert_true(has_opaque_pixel, "every sliced walk frame should draw a real silhouette, not a blank cell")


## The whole point of chroma-keying: no sliced frame should still carry the
## sheet's own magenta background as opaque content.
func test_no_frame_carries_leftover_magenta():
	for frame in sprite.generate_textures("ant", "carry"):
		var image := frame.get_image()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				assert_false(
					c.r > 0.85 and c.b > 0.85 and c.g < 0.3,
					"an opaque pixel should never still read as magenta background"
				)


func test_marker_scale_is_positive_for_every_registered_action():
	assert_gt(sprite.marker_scale("ant", "walk"), 0.0)
	assert_gt(sprite.marker_scale("ant", "carry"), 0.0)
	assert_gt(sprite.marker_scale("ant", "idle"), 0.0)
	assert_gt(sprite.marker_scale("bug", "walk"), 0.0)


func test_marker_scale_falls_back_to_one_for_an_unregistered_species():
	assert_eq(sprite.marker_scale("spider", "walk"), 1.0)


## The carry pose (body + cargo) draws a visibly wider silhouette than plain
## walking, so normalize_frames fits it to the canvas at a smaller internal
## scale -- marker_scale must compensate so the two still read as the same
## real-world creature size (see its own doc comment).
func test_walk_and_carry_render_at_the_same_apparent_size():
	var walk_frame: Image = sprite.generate_textures("ant", "walk")[0].get_image()
	var carry_frame: Image = sprite.generate_textures("ant", "carry")[0].get_image()
	var walk_world_width := _opaque_width(walk_frame) * sprite.marker_scale("ant", "walk")
	var carry_world_width := _opaque_width(carry_frame) * sprite.marker_scale("ant", "carry")
	assert_almost_eq(walk_world_width, carry_world_width, 0.5)


func _opaque_width(image: Image) -> float:
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1)
