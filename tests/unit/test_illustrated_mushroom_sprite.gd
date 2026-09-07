extends GutTest

## Real illustrated art for MushroomMarker's identified look (see
## docs/concept/mushrooms.md, docs/art/ai_sprite_prompts.md section 12) --
## a 5x5 grid of 25 independent individual specimens per species sheet, not
## an animation. Same "hand/AI-illustrated sheet -> SpriteSheetSlicer ->
## cached frames, picked per-instance by a seeded index" shape as
## IllustratedAntMoundSprite, across all 8 real delivered species sheets.
##
## Two real background conventions among the delivered NORMAL-look sheets
## (see the class's own doc comment): fly_agaric needs no magenta despill
## (a genuinely transparent background); the other seven do -- including
## fly_agaric's OWN crushed/bitten sheets, which (confirmed directly by
## pixel-sampling, not assumed) use magenta same as everything else.

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


# -- crushed/bitten variants (see docs/concept/mushrooms.md's "Crushed
# underfoot" / soil_fauna.md's decomposer-bite follow-up) -- reported
# live: "I added all missing mushroom spritesheets... wire them". All 8
# species now have real crushed AND bitten art delivered -- no more
# has_X()-false roster gap (the has_X() gate itself stays, the same
# "safe for an unknown/future-missing species" contract has_variants()
## already has for the normal look -- see the unknown-species test below).


func test_has_crushed_variant_for_every_real_species():
	for id in MushroomSpecies.IDS:
		assert_true(sprite.has_crushed_variant(id), "%s should have real crushed art" % id)


func test_has_bitten_variant_for_every_real_species():
	for id in MushroomSpecies.IDS:
		assert_true(sprite.has_bitten_variant(id), "%s should have real bitten art" % id)


func test_has_crushed_and_bitten_variant_false_for_an_unknown_species():
	assert_false(sprite.has_crushed_variant("portobello"))
	assert_null(sprite.crushed_frame_for("portobello", 0))
	assert_eq(sprite.crushed_frame_count("portobello"), 0)
	assert_false(sprite.has_bitten_variant("portobello"))
	assert_null(sprite.bitten_frame_for("portobello", 0))
	assert_eq(sprite.bitten_frame_count("portobello"), 0)


func test_crushed_frame_for_returns_a_real_non_blank_texture():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.crushed_frame_for(id, 0).get_image()
		var has_opaque_pixel := false
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					has_opaque_pixel = true
					break
			if has_opaque_pixel:
				break
		assert_true(has_opaque_pixel, "%s crushed frame 0 should draw a real illustration" % id)


func test_crushed_frame_for_has_no_leftover_magenta():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.crushed_frame_for(id, 0).get_image()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				assert_false(
					c.r > 0.85 and c.b > 0.85 and c.g < 0.3,
					"%s: an opaque crushed pixel should never still read as magenta background" % id
				)


func test_crushed_frame_for_is_deterministic_per_seed():
	for id in MushroomSpecies.IDS:
		assert_eq(sprite.crushed_frame_for(id, 42), sprite.crushed_frame_for(id, 42))


## Every species has exactly one delivered crushed sheet -- unlike bitten
## (see below), there is no multi-sheet combination on the crushed side
## yet, so this stays a flat 25 across the whole roster.
func test_crushed_frame_count_is_25_for_every_species():
	for id in MushroomSpecies.IDS:
		assert_eq(sprite.crushed_frame_count(id), EXPECTED_FRAME_COUNT, id)


func test_bitten_frame_for_returns_a_real_non_blank_texture():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.bitten_frame_for(id, 0).get_image()
		var has_opaque_pixel := false
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					has_opaque_pixel = true
					break
			if has_opaque_pixel:
				break
		assert_true(has_opaque_pixel, "%s bitten frame 0 should draw a real illustration" % id)


func test_bitten_frame_for_has_no_leftover_magenta():
	for id in MushroomSpecies.IDS:
		var image: Image = sprite.bitten_frame_for(id, 0).get_image()
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a <= 0.5:
					continue
				assert_false(
					c.r > 0.85 and c.b > 0.85 and c.g < 0.3,
					"%s: an opaque bitten pixel should never still read as magenta background" % id
				)


func test_bitten_frame_for_is_deterministic_per_seed():
	for id in MushroomSpecies.IDS:
		assert_eq(sprite.bitten_frame_for(id, 42), sprite.bitten_frame_for(id, 42))


## Most species had 3 independent bitten sheets delivered (not just 1) --
## a "path" entry can now be a whole Array of sheets to combine into one
## bigger pool, the same way _SHEETS/_CRUSHED_SHEETS' single-path entries
## still work unchanged. death_cap has only 1 delivered bitten sheet so
## far, same as every crushed entry -- the mixed counts here are the real,
## honest reflection of what's actually been delivered per species, not a
## uniform assumption.
func test_bitten_frame_count_reflects_every_delivered_sheet_combined():
	for id in ["fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol", "false_death_cap"]:
		assert_eq(
			sprite.bitten_frame_count(id), EXPECTED_FRAME_COUNT * 3,
			"%s has 3 delivered bitten sheets, should combine into 75 frames" % id
		)
	assert_eq(sprite.bitten_frame_count("death_cap"), EXPECTED_FRAME_COUNT, "death_cap has only 1 delivered bitten sheet so far")


## Spreading across a combined multi-sheet pool, not just the first sheet
## in the list -- a caller that only ever loaded sheet 1 and ignored 2/3
## would still pass every test above (frame 0 of sheet 1 is a real,
## non-blank, correctly-keyed frame regardless).
func test_bitten_frame_for_spreads_across_every_combined_sheet():
	for id in ["fly_agaric", "psylo", "black_trumpet", "champignon", "chanterelle", "parasol", "false_death_cap"]:
		var seen := {}
		for i in 300:
			seen[sprite.bitten_frame_for(id, i)] = true
		assert_gt(seen.size(), EXPECTED_FRAME_COUNT, "%s: should pick variants beyond just the first sheet's own 25" % id)


## The crushed/bitten look must actually differ from the normal look --
## a caller that got the wrong sheet by mistake would still pass every
## other test above.
func test_crushed_and_bitten_frames_differ_from_the_normal_frame():
	for id in MushroomSpecies.IDS:
		var normal: PackedByteArray = sprite.frame_for(id, 0).get_image().get_data()
		var crushed: PackedByteArray = sprite.crushed_frame_for(id, 0).get_image().get_data()
		var bitten: PackedByteArray = sprite.bitten_frame_for(id, 0).get_image().get_data()
		assert_ne(normal, crushed, "%s crushed should look different from normal" % id)
		assert_ne(normal, bitten, "%s bitten should look different from normal" % id)


# -- warm_cache (see docs/concept/soil_fauna.md's fps round 6 write-up) --
# frame_for/crushed_frame_for/bitten_frame_for are each lazily cached on
# first use per species -- real, measured, whole-image chroma-key+slice
# work (a bitten sheet in particular can combine up to 3 separate full-
# resolution images), expensive enough that paying it on whichever live
# gameplay frame happens to be the first bite of a not-yet-touched species
# is a real, measured stutter (up to ~1.6s for a single bite on this
# session's own machine), not a one-off. warm_cache() front-loads every
# species' normal/crushed/bitten cache eagerly instead of leaving it to
# chance which gameplay frame pays the bill.


## Resets to a genuinely COLD cache first -- otherwise an earlier test in
## this same file (or an earlier warm_cache() call) may have already
## warmed some/all of these species via ordinary lazy use, and this test
## would pass even if warm_cache() were a no-op. Same static-state-reset
## shape DecomposerMarker's own tests already use for
## _food_group_refresh_at_msec (see decomposer_marker.gd).
func test_warm_cache_fills_a_cold_cache_for_every_species():
	IllustratedMushroomSprite._frames_cache = {}
	IllustratedMushroomSprite._crushed_frames_cache = {}
	IllustratedMushroomSprite._bitten_frames_cache = {}
	sprite.warm_cache()
	for id in MushroomSpecies.IDS:
		assert_true(IllustratedMushroomSprite._frames_cache.has(id), "%s normal cache should be warm" % id)
		assert_true(IllustratedMushroomSprite._crushed_frames_cache.has(id), "%s crushed cache should be warm" % id)
		assert_true(IllustratedMushroomSprite._bitten_frames_cache.has(id), "%s bitten cache should be warm" % id)
