extends GutTest

## Real illustrated art for MushroomMarker's identified look (see
## docs/concept/mushrooms.md, docs/art/ai_sprite_prompts.md section 12) --
## a 5x5 grid of 25 independent individual specimens per species sheet, not
## an animation. Same "hand/AI-illustrated sheet -> SpriteSheetSlicer ->
## cached frames, picked per-instance by a seeded index" shape as
## IllustratedAntMoundSprite, across all 6 real delivered species sheets.
##
## Two real background conventions among the delivered sheets (see the
## class's own doc comment): fly_agaric needs no magenta despill (a
## genuinely transparent background); the other five do.

const IllustratedMushroomSprite = preload("res://src/rendering/illustrated_mushroom_sprite.gd")
const MushroomSpecies = preload("res://src/world/mushroom_species.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")

const EXPECTED_FRAME_COUNT := 25

var sprite: IllustratedMushroomSprite


func before_each():
	sprite = IllustratedMushroomSprite.new()


func test_has_variants_for_every_real_species():
	for id in MushroomSpecies.IDS:
		assert_true(sprite.has_variants(id), "%s should have real illustrated art" % id)


func test_an_unknown_species_has_no_variants():
	assert_false(sprite.has_variants("portobello"))
	assert_null(sprite.frame_for("portobello", 1))
	assert_eq(sprite.frame_count("portobello"), 0)


func test_every_species_slices_into_25_frames():
	for id in MushroomSpecies.IDS:
		assert_eq(sprite.frame_count(id), EXPECTED_FRAME_COUNT, "%s should slice into 25 variants" % id)


func test_frame_for_returns_a_real_non_blank_texture_for_every_species():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.frame_for(id, 0).get_image()
		var has_opaque_pixel := false
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					has_opaque_pixel = true
					break
			if has_opaque_pixel:
				break
		assert_true(has_opaque_pixel, "%s frame 0 should draw a real illustration, not a blank cell" % id)


## Covers both conventions: the five magenta-keyed sheets must have their
## chroma-key fully despilled, and fly_agaric's already-transparent sheet
## must never have accidentally picked up an opaque magenta-ish pixel
## either (a plain sanity check, since it never runs through despill at
## all).
func test_frame_for_has_no_leftover_magenta_for_any_species():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.frame_for(id, 0).get_image()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				assert_false(
					c.r > 0.85 and c.b > 0.85 and c.g < 0.3,
					"%s: an opaque pixel should never still read as magenta background" % id
				)


func test_frame_for_is_deterministic_per_seed():
	for id in MushroomSpecies.IDS:
		assert_eq(sprite.frame_for(id, 42), sprite.frame_for(id, 42))


func test_frame_for_spreads_across_variants():
	for id in MushroomSpecies.IDS:
		var seen := {}
		for i in 60:
			seen[sprite.frame_for(id, i)] = true
		assert_gt(seen.size(), 1, "%s: different seeds should pick different variants" % id)


func test_marker_scale_is_positive_for_every_species():
	for id in MushroomSpecies.IDS:
		assert_gt(sprite.marker_scale(id), 0.0)


## Illustrated art must land at the SAME real-world size the procedural
## mushroom already uses, so swapping the art in doesn't suddenly grow/
## shrink every mushroom already placed in the world (see
## MUSHROOM_WORLD_WIDTH's own doc comment).
func test_marker_scale_produces_the_procedural_mushrooms_own_world_width():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.frame_for(id, 0).get_image()
		var min_x := image.get_width()
		var max_x := -1
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
		var opaque_width := float(max_x - min_x + 1)
		assert_almost_eq(
			opaque_width * sprite.marker_scale(id), ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH, 0.5,
			"%s marker_scale should reproduce the procedural fallback's own world width" % id
		)
