extends GutTest

## Real illustrated art for an AntColony mound (see AntMoundMarker,
## docs/concept/soil_fauna.md) -- a 3x3 grid of independent hand-illustrated
## mound-with-entrance variants, not an animation. Same "hand-drawn sheet ->
## SpriteSheetSlicer -> cached frames, picked per-instance by a seeded
## index" shape as IllustratedStoneSprite, scoped to this one sheet.

const IllustratedAntMoundSprite = preload("res://src/rendering/illustrated_ant_mound_sprite.gd")

const EXPECTED_FRAME_COUNT := 9

var sprite: IllustratedAntMoundSprite


func before_each():
	sprite = IllustratedAntMoundSprite.new()


func test_has_variants_is_true():
	assert_true(sprite.has_variants())


func test_frame_for_returns_a_real_texture():
	assert_not_null(sprite.frame_for(0))


func test_frame_for_returns_a_non_blank_frame():
	var image: Image = sprite.frame_for(0).get_image()
	var has_opaque_pixel := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				has_opaque_pixel = true
				break
		if has_opaque_pixel:
			break
	assert_true(has_opaque_pixel, "a mound frame should draw a real illustration, not a blank cell")


func test_frame_for_has_no_leftover_magenta():
	var image: Image = sprite.frame_for(0).get_image()
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a <= 0.5:
				continue
			assert_false(
				c.r > 0.85 and c.b > 0.85 and c.g < 0.3,
				"an opaque pixel should never still read as magenta background"
			)


func test_sheet_slices_into_nine_frames():
	assert_eq(sprite.frame_count(), EXPECTED_FRAME_COUNT)


func test_frame_for_is_deterministic_per_seed():
	assert_eq(sprite.frame_for(42), sprite.frame_for(42))


func test_frame_for_spreads_across_variants():
	var seen := {}
	for i in 60:
		seen[sprite.frame_for(i)] = true
	assert_gt(seen.size(), 1, "different seeds should pick different mound variants")


func test_marker_scale_is_positive():
	assert_gt(sprite.marker_scale(), 0.0)


## Illustrated art must land at the SAME real-world size the procedural
## mound already uses, so swapping the art in doesn't suddenly grow/shrink
## every mound already placed in the world (see MOUND_WORLD_WIDTH's own
## doc comment).
func test_marker_scale_produces_the_procedural_mounds_own_world_width():
	const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")
	var image: Image = sprite.frame_for(0).get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var opaque_width := float(max_x - min_x + 1)
	assert_almost_eq(
		opaque_width * sprite.marker_scale(), ProceduralAntMoundSprite.MOUND_WORLD_WIDTH, 1.0
	)
