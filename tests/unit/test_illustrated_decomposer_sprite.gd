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


## Pinned at 4 until the art itself grew a real second pair of idle poses --
## see tools/probe_decomposer_sheets.gd's own doc comment for the git-
## history proof (pre-2026-09-06 ant.png/beetle.png blobs both still slice
## to 4 idle frames under this identical detect_frames call): not a slicer
## regression, the sheets' idle rows were deliberately extended from 4
## poses to 6, matching their own walk/carry rows' already-6-frame cadence.
func test_generate_textures_returns_six_idle_frames_for_ant():
	assert_eq(sprite.generate_textures("ant", "idle").size(), 6)


func test_generate_textures_returns_six_walk_frames_for_bug():
	assert_eq(sprite.generate_textures("bug", "walk").size(), 6)


func test_generate_textures_returns_six_idle_frames_for_bug():
	assert_eq(sprite.generate_textures("bug", "idle").size(), 6)


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


# -- ant/bug now have their OWN world width, not one shared constant: ants
# read smaller than their old size, and a carrion bug is a genuinely
# different, larger insect that was never reported as oversized alongside
# them (see docs/concept/soil_fauna.md "Ants at half their old size"). A
# literal halving (6.0 -> 3.0) overshot into genuinely invisible -- reported
# live as "I see no ant whatsoever" -- so the real pinned value is a 25%
# reduction, not 50% (see that doc's own 2026-09-05 follow-up). -------------

func test_ant_world_width_is_pinned_to_its_corrected_value():
	assert_eq(IllustratedDecomposerSprite.ANT_WORLD_WIDTH, 4.5)


func test_bug_world_width_is_unchanged_from_the_old_shared_constant():
	assert_eq(IllustratedDecomposerSprite.BUG_WORLD_WIDTH, 6.0)


func test_ant_is_smaller_than_bug_but_not_by_half():
	assert_lt(IllustratedDecomposerSprite.ANT_WORLD_WIDTH, IllustratedDecomposerSprite.BUG_WORLD_WIDTH)


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


# -- _prepared_for_slicing / _despill_image performance (mirrors
# IllustratedStoneSprite's own budgeted-timing tests; see docs/progress.md's
# "Still at 1fps" per-pixel art-loading investigation, 2026-09-10, and its
# own "separate, unaddressed ~44s" spawn-gap follow-up) -- this class's own
# despill loops are a SEPARATE, never-fixed duplicate of the exact naive
# per-pixel Image.get_pixel/set_pixel technique already fixed in
# SpriteSheetSlicer/IllustratedMushroomSprite/IllustratedAnimalSprite/
# IllustratedStoneSprite; nothing about THOSE fixes touches this file's own
# local reimplementation. Live-measured as a real, non-trivial slice of the
# first chunk a fresh game loads, inside the crops/mushrooms/decomposers/
# caterpillars/frogs/millipedes bundle of World._load_chunk -- and
## _despill_image's own CANVAS_SIZE (340x300) is ~100x IllustratedStoneSprite's
# (32x32), so this is plausibly the LARGER of the two per-frame costs despite
# sharing the same technique.

## Real sheet resolution (ant.png, 1698x926 -- see _SHEETS' own doc comment).
## Both sheets measure fully OPAQUE (alpha channel present but always 1.0,
## see _MAGENTA_RED_MIN's own doc comment) -- unlike IllustratedStoneSprite,
## there is no "already has real alpha" shortcut here, every pixel is always
## checked. Uniform non-magenta fill: no early-out or bounding box, so a
## solid fill is a faithful worst case (same reasoning as
## IllustratedStoneSprite's own equivalent test).
func test_prepared_for_slicing_completes_quickly_at_real_sheet_resolution():
	var width := 1698
	var height := 926
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var start_usec := Time.get_ticks_usec()
	sprite._prepared_for_slicing(image)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	# 850ms: this dev machine showed real contention noise wide enough that
	# a single-run absolute number alone was not trustworthy (the SAME fixed
	# code measured 220-786ms across separate isolated runs) -- calibrated
	# instead from 3 paired naive-vs-fixed rounds run back-to-back in one
	# process each (canceling cross-run contention, same technique
	# IllustratedAnimalSprite's own fix used): naive 1939-1975ms, fixed
	# 722-786ms every round. 850ms sits above every fixed round and below
	# every naive one, including this file's own earlier isolated-run
	# outliers (fixed as low as 220ms; naive as low as 899ms) on both sides.
	assert_lt(
		elapsed_ms, 850.0,
		(
			"despilling one %dx%d sheet took %.0fms -- a naive per-pixel get_pixel/set_pixel loop regressed back in"
			% [width, height, elapsed_ms]
		)
	)


## CANVAS_SIZE (340x300 -- far larger than IllustratedStoneSprite's 32x32,
## since decomposer art normalizes onto a bigger native canvas, see
## CANVAS_SIZE's own doc comment) -- the per-FRAME cleanup pass, called once
## per sliced frame across every action band (walk/carry/idle for ant,
## walk/idle for bug; 6 frames per band, see test_generate_textures_
## returns_six_walk_frames_for_ant).
func test_despill_image_completes_quickly_at_real_frame_resolution():
	var image := Image.create(
		IllustratedDecomposerSprite.CANVAS_SIZE.x, IllustratedDecomposerSprite.CANVAS_SIZE.y, false, Image.FORMAT_RGBA8
	)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var start_usec := Time.get_ticks_usec()
	sprite._despill_image(image)
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	# 65ms: same paired-measurement calibration as
	# test_prepared_for_slicing_completes_quickly_at_real_sheet_resolution
	# above -- 3 paired rounds measured naive 74.6-87.7ms, fixed 21.4-27.8ms
	# every round, comfortably clearing this budget on both sides even
	# against this file's own noisier single-run outliers (fixed as high as
	# 62.5ms in one contended full-suite run).
	assert_lt(
		elapsed_ms, 65.0,
		(
			"despilling one %dx%d frame took %.1fms -- a naive per-pixel get_pixel/set_pixel loop regressed back in"
			% [IllustratedDecomposerSprite.CANVAS_SIZE.x, IllustratedDecomposerSprite.CANVAS_SIZE.y, elapsed_ms]
		)
	)
