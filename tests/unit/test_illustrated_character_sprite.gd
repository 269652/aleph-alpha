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


# -- hero_composite.png: 8 outfits x {arms, body, legs} -- what body/legs/ --
# -- arms now source from ------------------------------------------------
#
# body/legs/arms now source from here (see the file's own doc comment on
# HERO_COMPOSITE_PATH) instead of the old single-pose torso.png/leg.png/
# arms.png -- has_part/generate_textures correctly report nothing for them
# any more (the old machinery stays real and tested for a future simple
# part, it just isn't what these three use).

func test_has_part_no_longer_reports_body_legs_or_arms():
	for part_name in ["body", "legs", "arms"]:
		assert_false(sprite.has_part(part_name), part_name)


func test_has_composite_part_is_true_for_body_legs_and_arms():
	for part_name in ["body", "legs", "arms"]:
		assert_true(sprite.has_composite_part(part_name), part_name)


func test_has_composite_part_is_false_for_head_or_an_unknown_part():
	assert_false(sprite.has_composite_part("head"))
	assert_false(sprite.has_composite_part("totally_unknown_part"))


func test_outfit_variant_is_deterministic_and_in_range():
	for seed_value in [0, 1, 4242, 99999]:
		var a := sprite.outfit_variant_for(seed_value)
		var b := sprite.outfit_variant_for(seed_value)
		assert_eq(a, b, "seed %d" % seed_value)
		assert_between(a, 0, IllustratedCharacterSprite.HERO_COMPOSITE_ROWS - 1)


func test_different_seeds_can_pick_different_outfit_variants():
	var seen := {}
	for seed_value in range(20):
		seen[sprite.outfit_variant_for(seed_value)] = true
	assert_gt(seen.size(), 1, "20 different heroes should not all wear the same outfit")


## Body and legs are each ONE drawing per cell; arms are genuinely TWO
## (a real transparent gap splits them, unlike the fused legs) -- see the
## file's own doc comment on why arms alone splits.
func test_generate_composite_textures_returns_the_right_frame_count_per_part():
	for part_name in ["body", "legs"]:
		var textures := sprite.generate_composite_textures(part_name, 0)
		assert_eq(textures.size(), 1, part_name)
	var arm_textures := sprite.generate_composite_textures("arms", 0)
	assert_eq(arm_textures.size(), 2)
	for texture in arm_textures:
		assert_gt(texture.get_width(), 0)
		assert_gt(texture.get_height(), 0)


func test_generate_composite_textures_is_empty_for_an_unregistered_part():
	assert_eq(sprite.generate_composite_textures("totally_unknown_part", 0), [] as Array[ImageTexture])


## The whole point of a variant axis: two different outfit rows must
## actually look different from each other.
func test_different_variants_produce_different_art():
	var variant_a := sprite.generate_composite_textures("body", 0)[0].get_image().get_data()
	var variant_b := sprite.generate_composite_textures("body", 1)[0].get_image().get_data()
	assert_ne(variant_a, variant_b, "two different outfit rows should look different")


## Only "front" resolves to real art today (see the file's own doc comment)
## -- a caller asking for a facing that doesn't exist yet gets front-facing
## art back rather than nothing.
func test_an_unavailable_facing_falls_back_to_front_rather_than_nothing():
	var front := sprite.generate_composite_textures("body", 0, "front")
	var unavailable := sprite.generate_composite_textures("body", 0, "side")
	assert_eq(front.size(), unavailable.size())
	assert_gt(unavailable.size(), 0)
	assert_eq(front[0].get_image().get_data(), unavailable[0].get_image().get_data())


func test_composite_part_scale_for_maps_measured_content_to_the_target_world_height():
	var scale := sprite.composite_part_scale_for("body", 0, 19.0)
	var content_height := _measured_content_height(
		sprite.generate_composite_textures("body", 0)[0].get_image()
	)
	assert_almost_eq(content_height * scale, 19.0, 0.05)


## arms.png's two drawings are independent, not a mirrored copy of one --
## each must be measured (and therefore scaled) on its own frame_index.
func test_composite_part_scale_for_is_independent_per_arm_frame():
	for frame_index in [0, 1]:
		var scale := sprite.composite_part_scale_for("arms", 0, 9.0, frame_index)
		var content_height := _measured_content_height(
			sprite.generate_composite_textures("arms", 0)[frame_index].get_image()
		)
		assert_almost_eq(content_height * scale, 9.0, 0.05, "frame %d" % frame_index)


func test_composite_part_scale_for_falls_back_to_one_for_an_unregistered_part():
	assert_eq(sprite.composite_part_scale_for("totally_unknown_part", 0, 19.0), 1.0)


## Every one of the 8 outfit rows must produce EXACTLY one frame for
## body/legs -- checked across the whole grid, not just one row, after two
## separate real gaps this exact check caught: row 7's ornate-plate-armor
## shoulder cape casting a stray detached fragment a too-generous body
## x-range counted as a second "body" frame (reached the live game as a
## malformed portrait), and row 7's legs content starting further left than
## an assumed lower bound, so the whole frame fell OUTSIDE the range and
## silently vanished (see HERO_COMPOSITE_COLUMN_X's own doc comment on both).
## Arms is checked more loosely -- almost every row's two arms detach
## cleanly into two frames, but the source art doesn't guarantee it for
## every one (row 6 doesn't), and CharacterView/the portrait both already
## degrade gracefully to one shared frame when it happens (see
## CharacterView._apply_arms), so a row that fuses is a known, harmless
## shape, not a bug to pin out of existence here.
func test_every_outfit_row_produces_the_expected_frame_count():
	for variant in range(IllustratedCharacterSprite.HERO_COMPOSITE_ROWS):
		assert_eq(sprite.generate_composite_textures("body", variant).size(), 1, "body row %d" % variant)
		assert_eq(sprite.generate_composite_textures("legs", variant).size(), 1, "legs row %d" % variant)
		var arm_count: int = sprite.generate_composite_textures("arms", variant).size()
		assert_between(arm_count, 1, 2, "arms row %d" % variant)


## detect_frames only ever splits on COLUMN gaps (see its own doc comment) --
## it has no way to know a row's legs column also holds a second, unrelated
## drawing (a belt-buckle or shoulder-pauldron close-up) sitting BELOW the
## real garment at overlapping x-coordinates, so _content_rect's plain
## min/max bounding-box scan silently welds the two into one "frame" spanning
## from the garment's top to the fragment's bottom, with a real gap of fully
## transparent rows in between. Verified visually against a rendered dump
## (reported live: "still no legs" even after CharacterView.
## TARGET_HEIGHT_FRACTION_OF_TREE was raised -- the fragment was inflating
## composite_part_scale_for's measured content height, shrinking the real
## boots/trousers well below what that fraction alone would predict): 6 of
## the 8 legs rows carry this, only rows 0 and 7 are clean. A single
## contiguous drawing's own tight bounding box should never contain a fully
## empty row with real content both above AND below it -- that shape is only
## possible when two unrelated blobs got cropped together.
func test_every_outfit_rows_legs_have_no_fragment_stacked_below_a_gap():
	for variant in range(IllustratedCharacterSprite.HERO_COMPOSITE_ROWS):
		var trimmed := sprite.trimmed_composite_image("legs", variant)
		assert_true(_has_no_disconnected_fragment(trimmed), "legs row %d" % variant)


func test_every_outfit_rows_body_has_no_fragment_stacked_below_a_gap():
	for variant in range(IllustratedCharacterSprite.HERO_COMPOSITE_ROWS):
		var trimmed := sprite.trimmed_composite_image("body", variant)
		assert_true(_has_no_disconnected_fragment(trimmed), "body row %d" % variant)


func test_has_action_is_false_for_an_unregistered_part():
	assert_false(sprite.has_action("totally_unknown_part", "walk"))


func test_generate_textures_returns_empty_for_an_unregistered_part():
	assert_eq(sprite.generate_textures("totally_unknown_part", "idle"), [] as Array[ImageTexture])


## part_scale_for/trimmed_part_image are still real, functional machinery
## for a future part that only ever needs one neutral pose (see _PARTS' own
## doc comment) -- with `_PARTS` currently empty, only the "unregistered
## part" fail-safe shape is exercisable here; a future caller registering a
## real part will want to add the equivalent of the coverage this class's
## git history shows for body/legs/arms before hero_composite.png replaced
## them (measured-content scale, per-frame independence, cached frames).

func test_part_scale_for_falls_back_to_one_for_an_unregistered_part():
	assert_eq(sprite.part_scale_for("totally_unknown_part", 19.0), 1.0)


func test_head_scale_for_maps_the_chosen_faces_measured_height_to_the_target():
	var cell_index := 42
	var scale := sprite.head_scale_for(cell_index, 12.0)
	# Recoloring must not change the geometry it was measured from.
	var image := sprite.generate_head_texture(cell_index, Color.WHITE).get_image()
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

func test_trimmed_part_image_returns_null_for_an_unregistered_part():
	assert_null(sprite.trimmed_part_image("totally_unknown_part"))


# -- trimmed_composite_image: the portrait's counterpart for hero_composite --

func test_trimmed_composite_image_has_a_tight_bounding_box():
	assert_true(_bbox_is_tight(sprite.trimmed_composite_image("body", 0, "front")))


func test_trimmed_composite_image_is_smaller_than_the_padded_shared_canvas():
	var trimmed := sprite.trimmed_composite_image("legs", 0, "front")
	assert_true(
		trimmed.get_width() < IllustratedCharacterSprite.CANVAS_SIZE.x
		or trimmed.get_height() < IllustratedCharacterSprite.CANVAS_SIZE.y
	)


func test_trimmed_composite_image_returns_null_for_an_unknown_part():
	assert_null(sprite.trimmed_composite_image("totally_unknown_part", 0, "front"))


## An unavailable facing falls back to "front" (see _resolved_facing) rather
## than returning null -- a caller asking for "side" before that art exists
## gets a facing hero back, not a blank one.
func test_trimmed_composite_image_falls_back_to_front_for_an_unavailable_facing():
	assert_not_null(sprite.trimmed_composite_image("body", 0, "totally_unknown_facing"))


# -- composite_leg_segments: a real hip+knee joint on the fused leg pair ----
#
# Reported live: "add proper walk animation by morphing the leg sprites and
# include a knee joint animated motion" -- the fused pair (see this file's
# own doc comment on why legs are one connected drawing, not two
# independently-swinging sprites) has no thigh/shin split baked into the
# source art at all, so CharacterView cuts the SAME real pixels into a
# thigh (top) and shin (bottom) crop at KNEE_LINE_FRACTION of the leg's own
# measured height, and hinges them on a real hip+knee pivot chain (see
# CharacterView._apply_legs/leg_gait_cycle.gd) -- a genuine two-piece
# crop-and-hinge rig, not a full weight-painted mesh skin (see
# CharacterView's own doc comment for why a Polygon2D/Skeleton2D bone-weight
# skin was evaluated and set aside this pass).

func test_composite_leg_segments_returns_two_images_for_a_registered_variant():
	var segments := sprite.composite_leg_segments(0)
	assert_eq(segments.size(), 2)


## The thigh (top) crop and shin (bottom) crop must together cover more than
## the full trimmed leg's own height -- they OVERLAP across the knee line on
## purpose (see KNEE_OVERLAP_PX's own doc comment: several outfit rows draw
## a belt/banner bridging straight across the knee line, and a bare,
## non-overlapping cut would tear it the moment the shin rotates
## independently), so neither crop alone should equal the full height, and
## their sum should exceed it by roughly 2x the overlap.
func test_composite_leg_segments_overlap_across_the_knee_line():
	var trimmed := sprite.trimmed_composite_image("legs", 0)
	var segments := sprite.composite_leg_segments(0)
	var thigh: Image = segments[0]
	var shin: Image = segments[1]
	assert_lt(thigh.get_height(), trimmed.get_height())
	assert_lt(shin.get_height(), trimmed.get_height())
	var combined := thigh.get_height() + shin.get_height()
	assert_almost_eq(
		combined, trimmed.get_height() + 2 * IllustratedCharacterSprite.KNEE_OVERLAP_PX, 1
	)


## The split point itself: thigh's own height should land at
## KNEE_LINE_FRACTION of the full leg's height, plus the overlap band.
func test_composite_leg_segments_splits_at_the_knee_line_fraction():
	var trimmed := sprite.trimmed_composite_image("legs", 0)
	var segments := sprite.composite_leg_segments(0)
	var thigh: Image = segments[0]
	var expected_knee_y := roundi(trimmed.get_height() * IllustratedCharacterSprite.KNEE_LINE_FRACTION)
	var expected_thigh_height := mini(
		trimmed.get_height(), expected_knee_y + IllustratedCharacterSprite.KNEE_OVERLAP_PX
	)
	assert_eq(thigh.get_height(), expected_thigh_height)


func test_composite_leg_segments_same_width_as_the_full_leg():
	var trimmed := sprite.trimmed_composite_image("legs", 0)
	var segments := sprite.composite_leg_segments(0)
	var thigh: Image = segments[0]
	var shin: Image = segments[1]
	assert_eq(thigh.get_width(), trimmed.get_width())
	assert_eq(shin.get_width(), trimmed.get_width())


# -- pure geometry for placing the thigh/shin crops on the hip/knee pivots --

func test_leg_thigh_offset_y_centers_the_top_edge_on_the_hip_position():
	# Sprite2D draws centred on `.position` by default; offsetting by half
	# the crop's own height shifts its TOP edge onto `.position` instead.
	assert_almost_eq(sprite.leg_thigh_offset_y(40.0), 20.0, 0.0001)


func test_leg_knee_pivot_local_y_is_the_knee_line_fraction_of_the_full_leg():
	assert_almost_eq(
		sprite.leg_knee_pivot_local_y(100.0), 100.0 * IllustratedCharacterSprite.KNEE_LINE_FRACTION, 0.0001
	)


## The shin crop's own top edge sits KNEE_OVERLAP_PX above the real knee
## point (see composite_leg_segments) -- the offset must land THAT point,
## not the crop's bare top edge, on the knee pivot's own position.
func test_leg_shin_offset_y_lands_the_knee_point_on_the_pivot():
	var offset := sprite.leg_shin_offset_y(50.0, 10.0)
	assert_almost_eq(offset, 50.0 * 0.5 - 10.0, 0.0001)


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


## True if `image` is one single contiguous blob top-to-bottom: once a row
## reading as a real GAP is crossed, no later row may read as real content
## again. A real single drawing (a leg, a torso) never has a genuine gap
## like this -- the garment fills continuously from top to bottom -- so a
## gap followed by more content below it can only mean two unrelated pieces
## got cropped into one frame together (see
## test_every_outfit_rows_legs_have_no_fragment_stacked_below_a_gap).
##
## A row's own max alpha, not a flat >0 check, and 0.5 rather than the usual
## near-zero content threshold: `trimmed_composite_image` has already gone
## through normalize_frames' LANCZOS resize by the time a caller can see it,
## which blurs what was a hard 0%-alpha gap on the source sheet into a soft
## multi-row ramp -- measured directly (see the row-by-row max-alpha dump
## behind this pass): every known-contaminated row's gap bottoms out at
## <=39% at its lowest point, while every real content row (including the
## two clean rows' own edge-antialiasing) never drops below 73%. 0.5 sits
## in the middle of that gap with margin on both sides.
func _has_no_disconnected_fragment(image: Image) -> bool:
	var seen_gap_after_content := false
	var seen_content := false
	for y in image.get_height():
		var max_alpha := 0.0
		for x in image.get_width():
			max_alpha = maxf(max_alpha, image.get_pixel(x, y).a)
		var row_has_content := max_alpha >= 0.5
		if row_has_content:
			seen_content = true
			if seen_gap_after_content:
				return false
		elif seen_content:
			seen_gap_after_content = true
	return true


# -- head art: a 10x10 grid of full illustrated faces, a different shape ------
#
# A single flat modulate can't separate a head's skin/hair/eye color (see
# this file's own doc comment above and character_art_brief.md), so unlike
## body/legs/arms this ONE registered sheet is not exposed through has_part/
## generate_textures at all: has_head()/generate_head_texture() take a real,
## directly-chosen grid cell index -- which face a hero wears is now a
## genuine customization axis (HeroAppearance.AXES' "head", DNA-rolled by
## default but directly cyclable in the creator, see appearance_from_choices'
## "head_index") -- and recolor it to the caller's own skin tone by
## luminance (the same shading-only recolor already proven on illustrated
## flower blooms), discarding the sheet's own baked tone.

func test_has_head_is_true_now_that_head_art_is_registered():
	assert_true(sprite.has_head())


func test_has_part_does_not_report_head_head_uses_its_own_surface():
	assert_false(sprite.has_part("head"))


## Measured directly (see the survey behind this pass): 7 of the 100 cells
## have their background-removal flood erode almost the entire face (opaque
## fraction <=0.083 for every one), leaving a huge, near-blank, wildly
## oversized texture once head_scale_for divides a target height by that
## tiny measured content height -- reached the live game as a floating
## translucent smear where a face should be. has_usable_head is the same
## has-X-then-fallback safety net body/legs/arms already lean on for their
## own per-row gaps (see HERO_COMPOSITE_COLUMN_X's doc comment), applied to
## head art instead of chasing down the flood-fill's own root cause per cell.
func test_has_usable_head_is_false_for_a_known_near_empty_cell():
	assert_false(sprite.has_usable_head(51, Color(0.5, 0.35, 0.24)))


func test_has_usable_head_is_true_for_a_normal_cell():
	assert_true(sprite.has_usable_head(42, Color(0.5, 0.35, 0.24)))


## The flood's OTHER failure mode (see HEAD_MAXIMUM_OPAQUE_FRACTION's own
## doc comment): 12 cells' backgrounds were never removed at all, leaving
## the whole square cell opaque -- reported live as a dark rectangle where
## a face should be.
func test_has_usable_head_is_false_for_a_known_fully_opaque_cell():
	assert_false(sprite.has_usable_head(23, Color(0.5, 0.35, 0.24)))


## Out-of-range cell indices wrap rather than crash -- defense in depth,
## since HeroAppearance is expected to hand this an already-wrapped index
## (see _wrap_cell_index's own doc comment).
func test_out_of_range_cell_indices_wrap_into_the_grid():
	var texture := sprite.generate_head_texture(137, Color(0.8, 0.6, 0.44))
	assert_not_null(texture)
	var negative := sprite.generate_head_texture(-1, Color(0.8, 0.6, 0.44))
	assert_not_null(negative)


func test_generate_head_texture_returns_a_real_texture():
	var texture := sprite.generate_head_texture(42, Color(0.9, 0.7, 0.55))
	assert_not_null(texture)
	assert_gt(texture.get_width(), 0)
	assert_gt(texture.get_height(), 0)


func test_generate_head_texture_is_deterministic_for_the_same_cell_and_tone():
	var tone := Color(0.66, 0.47, 0.32)
	var a := sprite.generate_head_texture(11, tone)
	var b := sprite.generate_head_texture(11, tone)
	assert_eq(a.get_image().get_data(), b.get_image().get_data())


## The whole point of the recolor: two heroes with the SAME face cell but
## DIFFERENT DNA skin tones must actually look different, not both wear the
## sheet's own single baked-in tone.
func test_generate_head_texture_actually_recolors_toward_the_given_skin_tone():
	var cell_index := 42
	var pale := sprite.generate_head_texture(cell_index, Color(0.96, 0.82, 0.69))
	var deep := sprite.generate_head_texture(cell_index, Color(0.36, 0.25, 0.18))
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
