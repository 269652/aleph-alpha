extends GutTest

## IllustratedCharacterSprite: the character-rig counterpart to
## IllustratedAnimalSprite -- see that module's tests for the exhaustive
## coverage of the shared slicing/chroma-key machinery.
##
## body/legs/arms are real registered art now (see docs/concept/
## character_art_brief.md): body.png and leg.png are each a single neutral
## idle pose (no left/right split -- legs are a fused PAIR, drawn and worn as
## one part rather than two independently-swinging sprites, see
## CharacterView's own legs-fusion handling); arms.png is two poses side by
## side, sliced by an exact rect pair rather than the usual divider-column
## scan because the sheet's own divider is an OPAQUE line, not a transparent
## gap (see idle_rects).
##
## head is still a different mechanism entirely (has_head/
## generate_head_texture, not has_part/generate_textures) -- see the "head
## art" tests below for why.

const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")

var sprite: IllustratedCharacterSprite


func before_each():
	sprite = IllustratedCharacterSprite.new()


func test_has_part_is_false_for_an_unregistered_part():
	assert_false(sprite.has_part("totally_unknown_part"))


func test_has_action_is_false_for_an_unregistered_part():
	assert_false(sprite.has_action("totally_unknown_part", "walk"))


func test_generate_textures_returns_empty_for_an_unregistered_part():
	assert_eq(sprite.generate_textures("totally_unknown_part", "idle"), [] as Array[ImageTexture])


# -- body/legs/arms: registered, single-rect or exact-rect-pair sheets -------

func test_body_legs_and_arms_are_registered_parts_with_an_idle_action():
	for part_name in ["body", "legs", "arms"]:
		assert_true(sprite.has_part(part_name), part_name)
		assert_true(sprite.has_action(part_name, "idle"), part_name)


func test_body_and_legs_generate_exactly_one_idle_frame():
	for part_name in ["body", "legs"]:
		var frames := sprite.generate_textures(part_name, "idle")
		assert_eq(frames.size(), 1, part_name)
		assert_gt(frames[0].get_width(), 0, part_name)
		assert_gt(frames[0].get_height(), 0, part_name)


## arms.png is one sheet holding two poses side by side -- exactly what
## CharacterView needs for ArmLeft/ArmRight (see _apply_paperdoll_part's
## frame_index argument).
func test_arms_generate_exactly_two_idle_frames():
	var frames := sprite.generate_textures("arms", "idle")
	assert_eq(frames.size(), 2)
	for frame in frames:
		assert_gt(frame.get_width(), 0)
		assert_gt(frame.get_height(), 0)


func test_generated_frames_are_cached_not_rebuilt_every_call():
	var first := sprite.generate_textures("body", "idle")
	var second := sprite.generate_textures("body", "idle")
	assert_eq(first[0], second[0], "repeated calls should reuse the same cached texture")


# -- part_scale_for: measure the actual art, not the shared working canvas ---
#
# CANVAS_SIZE is one shared WORKING resolution every part is normalized onto
# (see the file's own doc comment) -- it is not a claim that a torso and a
# leg pair are the same real size, so CharacterView must scale each part by
# its OWN measured content, not a flat constant (see
# IllustratedAnimalSprite.marker_scale, the same pattern one rig over).

func test_part_scale_for_maps_measured_content_to_the_target_world_height():
	var scale := sprite.part_scale_for("body", 19.0)
	var content_height := _measured_content_height(sprite.generate_textures("body", "idle")[0].get_image())
	assert_almost_eq(content_height * scale, 19.0, 0.05)


func test_part_scale_for_is_independent_per_arm_frame():
	# arms.png's two poses are independent crops, not a mirrored copy of one
	# -- each must be measured (and therefore scaled) on its own frame_index.
	for frame_index in [0, 1]:
		var scale := sprite.part_scale_for("arms", 9.0, frame_index)
		var content_height := _measured_content_height(
			sprite.generate_textures("arms", "idle")[frame_index].get_image()
		)
		assert_almost_eq(content_height * scale, 9.0, 0.05, "frame %d" % frame_index)


func test_part_scale_for_falls_back_to_one_for_an_unregistered_part():
	assert_eq(sprite.part_scale_for("totally_unknown_part", 19.0), 1.0)


func test_head_scale_for_maps_the_chosen_faces_measured_height_to_the_target():
	var seed_value := 4242
	var scale := sprite.head_scale_for(seed_value, 12.0)
	# Recoloring must not change the geometry it was measured from.
	var image := sprite.generate_head_texture(seed_value, Color.WHITE).get_image()
	var content_height := _measured_content_height(image)
	assert_almost_eq(content_height * scale, 12.0, 0.05)


func _measured_content_height(image: Image) -> float:
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	return float(max_y - min_y + 1)


# -- trimmed content images: for callers compositing raw Images rather than -
# -- Sprite2D nodes (see ProceduralCharacterSprite's illustrated portrait) --

func test_trimmed_part_image_has_a_tight_bounding_box():
	assert_true(_bbox_is_tight(sprite.trimmed_part_image("body")))


## At least ONE dimension must shrink -- content can legitimately fill the
## canvas exactly in the dimension that BOUNDS the aspect-preserving fit
## (measured: body's content is exactly CANVAS_SIZE.x wide), so this checks
## that trimming did something, not that both dimensions shrink.
func test_trimmed_part_image_is_smaller_than_the_padded_shared_canvas():
	var trimmed := sprite.trimmed_part_image("body")
	assert_true(
		trimmed.get_width() < IllustratedCharacterSprite.CANVAS_SIZE.x
		or trimmed.get_height() < IllustratedCharacterSprite.CANVAS_SIZE.y
	)


func test_trimmed_part_image_returns_null_for_an_unregistered_part():
	assert_null(sprite.trimmed_part_image("totally_unknown_part"))


func test_trimmed_part_image_respects_frame_index():
	var left := sprite.trimmed_part_image("arms", 0)
	var right := sprite.trimmed_part_image("arms", 1)
	assert_ne(left.get_data(), right.get_data())


## Measured directly against the real sheet (see head_edge_probe.js, run
## during debugging): the transition from head.png's background to a face
## is a WIDE, gradual blur -- 20-30 pixels of ramp between near-black and
## clearly-face brightness, not a crisp cut. A flat per-pixel
## distance-from-black chroma-key (what this used to be) either left a
## visible dark halo around every face (too tight a tolerance) or risked
## punching a hole through a genuinely dark part of the face itself -- an
## eye, wherever it happens to also fall within tolerance of black -- since
## a flat tolerance cannot tell "background" apart from "coincidentally
## dark pixel in the middle of the face"; it never looks at what a pixel is
## CONNECTED to. A border flood fill can: starting from the four canvas
## edges (guaranteed background) and stepping only to a neighbour that is
## itself close to the pixel that reached it, it rides the background's own
## gradual blur all the way to where the face genuinely begins, and can
## never cross INTO the face's interior no matter how dark a pixel there is
## -- reaching it would require one big step across the face's own edge,
## which the per-step tolerance refuses.
func test_flood_removes_a_gradient_background_but_preserves_a_dark_island_inside_content():
	var image := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 10:
			var ring := mini(mini(x, 9 - x), mini(y, 9 - y))
			if ring == 0:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
			elif ring == 1:
				image.set_pixel(x, y, Color(0.15, 0.15, 0.15, 1.0))  # the blurred edge
			else:
				image.set_pixel(x, y, Color(0.8, 0.7, 0.6, 1.0))  # the "face"
	image.set_pixel(5, 5, Color(0.0, 0.0, 0.0, 1.0))  # a dark "eye" inside the face

	var result := sprite._remove_background_by_flood(image, 0.2)

	assert_almost_eq(result.get_pixel(0, 0).a, 0.0, 0.01, "the border should become transparent")
	assert_almost_eq(result.get_pixel(1, 1).a, 0.0, 0.01, "the blurred ring should become transparent")
	assert_gt(result.get_pixel(5, 5).a, 0.5, "a dark pixel surrounded by content should stay opaque")
	assert_gt(result.get_pixel(4, 4).a, 0.5, "the face content itself should stay opaque")


func test_trimmed_head_image_has_a_tight_bounding_box():
	assert_true(_bbox_is_tight(sprite.trimmed_head_image(4242, Color(0.8, 0.6, 0.44))))


func test_trimmed_head_image_is_smaller_than_the_padded_head_canvas():
	var trimmed := sprite.trimmed_head_image(4242, Color(0.8, 0.6, 0.44))
	assert_true(
		trimmed.get_width() < IllustratedCharacterSprite.HEAD_CANVAS_SIZE.x
		or trimmed.get_height() < IllustratedCharacterSprite.HEAD_CANVAS_SIZE.y
	)


## True when every one of the image's four edges carries at least one opaque
## pixel -- the precise "no padding left" check: a loose crop could still
## have SOME opaque pixel somewhere near an edge while leaving a padding row
## on, say, only the left side, which a looser check would miss.
func _bbox_is_tight(image: Image) -> bool:
	var w := image.get_width()
	var h := image.get_height()
	var top := false
	var bottom := false
	var left := false
	var right := false
	for x in w:
		if image.get_pixel(x, 0).a > 0.01:
			top = true
		if image.get_pixel(x, h - 1).a > 0.01:
			bottom = true
	for y in h:
		if image.get_pixel(0, y).a > 0.01:
			left = true
		if image.get_pixel(w - 1, y).a > 0.01:
			right = true
	return top and bottom and left and right


# -- head art: a 10x10 grid of full illustrated faces, a different shape ------
#
# A single flat modulate can't separate a head's skin/hair/eye color (see
# this file's own doc comment above and character_art_brief.md), so unlike
## body/legs/arms this ONE registered sheet is not exposed through has_part/
## generate_textures at all: has_head()/generate_head_texture() pick exactly
## one of its 100 painted faces per DNA seed and recolor it to the caller's
## own skin tone by luminance (the same shading-only recolor already proven
## on illustrated flower blooms), discarding the sheet's own baked tone.

func test_has_head_is_true_now_that_head_art_is_registered():
	assert_true(sprite.has_head())


func test_has_part_does_not_report_head_head_uses_its_own_surface():
	assert_false(sprite.has_part("head"))


## Same seed, same face, every time -- a hero must not change which of the
## 100 faces it wears from one frame to the next.
func test_head_cell_index_is_deterministic():
	var a := sprite.head_cell_index_for(4242)
	var b := sprite.head_cell_index_for(4242)
	assert_eq(a, b)


func test_head_cell_index_always_lands_inside_the_10x10_grid():
	for seed_value in range(50):
		var index := sprite.head_cell_index_for(seed_value)
		assert_between(index, 0, 99, "seed %d picked an out-of-grid cell" % seed_value)


func test_different_seeds_can_pick_different_head_cells():
	var seen := {}
	for seed_value in range(30):
		seen[sprite.head_cell_index_for(seed_value)] = true
	assert_gt(seen.size(), 1, "30 different heroes should not all wear the same face")


func test_generate_head_texture_returns_a_real_texture():
	var texture := sprite.generate_head_texture(4242, Color(0.9, 0.7, 0.55))
	assert_not_null(texture)
	assert_gt(texture.get_width(), 0)
	assert_gt(texture.get_height(), 0)


func test_generate_head_texture_is_deterministic_for_the_same_seed_and_tone():
	var tone := Color(0.66, 0.47, 0.32)
	var a := sprite.generate_head_texture(11, tone)
	var b := sprite.generate_head_texture(11, tone)
	assert_eq(a.get_image().get_data(), b.get_image().get_data())


## The whole point of the recolor: two heroes with the SAME face cell but
## DIFFERENT DNA skin tones must actually look different, not both wear the
## sheet's own single baked-in tone.
func test_generate_head_texture_actually_recolors_toward_the_given_skin_tone():
	var seed_value := 4242
	var pale := sprite.generate_head_texture(seed_value, Color(0.96, 0.82, 0.69))
	var deep := sprite.generate_head_texture(seed_value, Color(0.36, 0.25, 0.18))
	assert_ne(pale.get_image().get_data(), deep.get_image().get_data())

	var pale_avg := _average_opaque_color(pale.get_image())
	var deep_avg := _average_opaque_color(deep.get_image())
	assert_gt(
		pale_avg.r, deep_avg.r,
		"the paler skin tone should read visibly lighter than the deep one"
	)


## Recoloring must not paint the whole head a flat, shadeless block of the
## tint -- it should still carry the source art's own light/shade variation
## (see the flower recolor precedent this mirrors).
func test_generate_head_texture_keeps_shading_not_a_flat_tint():
	var image := sprite.generate_head_texture(4242, Color(0.8, 0.6, 0.44)).get_image()
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				seen[c.to_html()] = true
	assert_gt(seen.size(), 3, "a recolored head should still show multiple shades")


func _average_opaque_color(image: Image) -> Color:
	var total := Vector3.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				total += Vector3(c.r, c.g, c.b)
				count += 1
	if count == 0:
		return Color.BLACK
	total /= float(count)
	return Color(total.x, total.y, total.z)
