extends GutTest

## The hero-appearance engine: (class archetype, dna seed) -> a deterministic
## visual identity (skin tone, hair color/style, class-colored tunic + trim),
## rendered by ProceduralCharacterSprite's hero generators -- so the player
## reads as a distinct Hammerwatch-style hero, not a generic blue rectangle
## person, and two heroes of the same class still differ by their DNA seed.

const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")
const IllustratedCharacterSprite = preload("res://src/rendering/illustrated_character_sprite.gd")
## The player archetypes the character creator actually offers -- the classes
## whose icons must be told apart (see the class-portrait tests below).
const ClassArchetype = preload("res://src/gameplay/class_archetype.gd")

var appearance_maker := HeroAppearance.new()
var sprite := ProceduralCharacterSprite.new()


func test_appearance_is_deterministic():
	var a := appearance_maker.appearance_for("warrior", 42)
	var b := appearance_maker.appearance_for("warrior", 42)
	assert_eq(a, b)


func test_each_class_has_its_own_tunic_palette():
	var warrior := appearance_maker.appearance_for("warrior", 1)
	var mage := appearance_maker.appearance_for("mage", 1)
	var ranger := appearance_maker.appearance_for("ranger", 1)
	assert_ne(warrior.tunic, mage.tunic, "warrior and mage should dress differently")
	assert_ne(mage.tunic, ranger.tunic)
	assert_ne(warrior.tunic, ranger.tunic)


func test_dna_seed_varies_look_within_a_class():
	# Across a handful of seeds, at least two heroes of the same class must
	# differ in skin or hair -- DNA individuality, not one cloned face.
	var seen := {}
	for seed_value in 8:
		var a := appearance_maker.appearance_for("warrior", seed_value)
		seen["%s_%s_%d" % [a.skin, a.hair, a.hair_style]] = true
	assert_gt(seen.size(), 1, "different dna seeds should produce visibly different heroes")


func test_appearance_values_come_from_the_pinned_pools():
	var a := appearance_maker.appearance_for("ranger", 7)
	assert_has(HeroAppearance.SKIN_TONES, a.skin)
	assert_has(HeroAppearance.HAIR_COLORS, a.hair)
	assert_between(a.hair_style, 0, HeroAppearance.HAIR_STYLE_COUNT - 1)


## Villager occupations (see VillageRenderer) share this same engine -- every
## NpcIdentity.OCCUPATIONS entry should resolve to its own outfit rather than
## silently falling back to the warrior palette.
func test_every_npc_occupation_has_its_own_tunic_palette():
	const NpcIdentity = preload("res://src/world/npc_identity.gd")
	var seen_tunics := {}
	for occupation in NpcIdentity.OCCUPATIONS:
		assert_true(HeroAppearance.CLASS_PALETTES.has(occupation), "missing outfit palette for %s" % occupation)
		seen_tunics[appearance_maker.appearance_for(occupation, 1).tunic] = true
	assert_eq(seen_tunics.size(), NpcIdentity.OCCUPATIONS.size(), "every occupation should dress differently")


func test_unknown_class_falls_back_to_a_valid_appearance():
	var a := appearance_maker.appearance_for("not_a_class", 0)
	assert_has(HeroAppearance.SKIN_TONES, a.skin)
	assert_true(a.tunic is Color)


func test_hero_head_has_hair_pixels_distinct_from_skin():
	var appearance := appearance_maker.appearance_for("warrior", 3)
	var image := sprite.generate_hero_head_image(Vector2i(8, 8), appearance)
	var hair_pixels := 0
	for y in 8:
		for x in 8:
			if _close(image.get_pixel(x, y), appearance.hair):
				hair_pixels += 1
	assert_gt(hair_pixels, 0, "the hero head should show hair, not a bald skin ellipse")


func test_hero_tunic_carries_the_class_trim_color():
	var appearance := appearance_maker.appearance_for("warrior", 3)
	var image := sprite.generate_hero_tunic_image(Vector2i(10, 14), appearance)
	var trim_pixels := 0
	for y in 14:
		for x in 10:
			if _close(image.get_pixel(x, y), appearance.trim):
				trim_pixels += 1
	assert_gt(trim_pixels, 0, "the tunic should carry the class trim/belt accent")


# -- customization axes (the character creator's cycling) --------------------

func test_every_axis_reports_a_positive_option_count():
	for axis in HeroAppearance.AXES:
		assert_gt(appearance_maker.option_count(axis), 1, "axis %s should offer real choices" % axis)


func test_unknown_axis_reports_zero_options_rather_than_erroring():
	assert_eq(appearance_maker.option_count("not_an_axis"), 0)


func test_appearance_from_choices_uses_the_picked_options():
	var a := appearance_maker.appearance_from_choices("mage", {
		"skin": 2, "hair_color": 3, "hair_style": 1, "beard": 2, "eyes": 1,
	})
	assert_eq(a.skin, HeroAppearance.SKIN_TONES[2])
	assert_eq(a.hair, HeroAppearance.HAIR_COLORS[3])
	assert_eq(a.hair_style, 1)
	assert_eq(a.beard, 2)
	assert_eq(a.eyes, HeroAppearance.EYE_COLORS[1])
	assert_eq(a.tunic, HeroAppearance.CLASS_PALETTES["mage"].tunic)


## The creator increments/decrements freely and lets the engine normalize --
## going past the end wraps to the start, and below zero wraps to the end.
func test_choice_indices_wrap_in_both_directions():
	var past_end := appearance_maker.appearance_from_choices("warrior", {"skin": HeroAppearance.SKIN_TONES.size()})
	assert_eq(past_end.skin, HeroAppearance.SKIN_TONES[0])

	var below_zero := appearance_maker.appearance_from_choices("warrior", {"skin": -1})
	assert_eq(below_zero.skin, HeroAppearance.SKIN_TONES[HeroAppearance.SKIN_TONES.size() - 1])


func test_missing_choices_fall_back_to_the_first_option():
	var a := appearance_maker.appearance_from_choices("warrior", {})
	assert_eq(a.skin, HeroAppearance.SKIN_TONES[0])
	assert_eq(a.hair_style, 0)


## The seed carries through onto the appearance dict for any caller that
## wants a stable per-hero value not tied to a cyclable axis (village NPCs'
## own DNA seed, say) -- no live consumer of the bare "seed" field remains
## after "head" became a real axis (see below), but keeping it costs nothing
## and other per-seed variation may want it later.
func test_appearance_for_carries_the_seed_it_was_rolled_from():
	var a := appearance_maker.appearance_for("warrior", 4242)
	assert_eq(a.seed, 4242)


func test_appearance_from_choices_carries_the_seed_passed_to_it():
	var a := appearance_maker.appearance_from_choices("warrior", {}, 777)
	assert_eq(a.seed, 777)


func test_appearance_from_choices_defaults_the_seed_when_none_is_given():
	# The creator's live-preview rebuild doesn't always have a seed to hand
	# (see main_menu.gd's _current_appearance) -- a missing seed must still
	# produce a valid, usable appearance rather than erroring.
	var a := appearance_maker.appearance_from_choices("warrior", {})
	assert_eq(a.seed, 0)


## Which of IllustratedCharacterSprite's 100 illustrated heads a hero wears
## is a real customization axis like every other -- DNA-rolled by default,
## directly cyclable in the creator (reported, after "derive it from the DNA
## seed with no new UI" shipped and was actually tried: "you can't choose
## different heads"). option_count reads the grid size from
## IllustratedCharacterSprite rather than a second hardcoded 100, so the two
## can never drift if the sheet's own layout ever changes.
func test_head_is_a_real_customization_axis():
	assert_has(HeroAppearance.AXES, "head")
	assert_eq(
		appearance_maker.option_count("head"),
		IllustratedCharacterSprite.HEAD_GRID_COLUMNS * IllustratedCharacterSprite.HEAD_GRID_ROWS
	)


func test_appearance_for_rolls_a_head_index_in_range():
	for seed_value in [0, 1, 4242, 99999]:
		var a := appearance_maker.appearance_for("warrior", seed_value)
		assert_between(a.head_index, 0, appearance_maker.option_count("head") - 1)


func test_appearance_from_choices_uses_the_picked_head_index():
	var a := appearance_maker.appearance_from_choices("warrior", {"head": 37})
	assert_eq(a.head_index, 37)


func test_head_choice_wraps_like_every_other_axis():
	var past_end := appearance_maker.appearance_from_choices(
		"warrior", {"head": appearance_maker.option_count("head")}
	)
	assert_eq(past_end.head_index, 0)


## A rolled hero must be resumable in the creator: reading its choices back
## and rebuilding must reproduce the same look.
func test_choices_round_trip_through_an_appearance():
	var rolled := appearance_maker.appearance_for("ranger", 4242)
	var rebuilt := appearance_maker.appearance_from_choices(
		"ranger", appearance_maker.choices_from_appearance(rolled)
	)
	assert_eq(rebuilt.skin, rolled.skin)
	assert_eq(rebuilt.hair, rolled.hair)
	assert_eq(rebuilt.hair_style, rolled.hair_style)
	assert_eq(rebuilt.beard, rolled.beard)
	assert_eq(rebuilt.eyes, rolled.eyes)


func test_rolled_appearances_span_every_axis_across_seeds():
	var seen := {"skin": {}, "hair": {}, "hair_style": {}, "beard": {}, "eyes": {}}
	for seed_value in range(60):
		var a := appearance_maker.appearance_for("warrior", seed_value)
		seen.skin[a.skin] = true
		seen.hair[a.hair] = true
		seen.hair_style[a.hair_style] = true
		seen.beard[a.beard] = true
		seen.eyes[a.eyes] = true
	for axis in seen:
		assert_gt(seen[axis].size(), 1, "rolled heroes should vary in %s" % axis)


# -- face rendering ----------------------------------------------------------

## A bald hero must actually be bald -- no hair pixels anywhere on the head.
func test_bald_style_paints_no_hair():
	var bald_index := HeroAppearance.HAIR_STYLES.find("bald")
	var appearance := appearance_maker.appearance_from_choices("warrior", {
		"hair_style": bald_index, "hair_color": 3, "skin": 0,
	})
	var image := sprite.generate_hero_head_image(Vector2i(14, 14), appearance)
	var hair_pixels := 0
	for y in 14:
		for x in 14:
			if _close(image.get_pixel(x, y), appearance.hair):
				hair_pixels += 1
	assert_eq(hair_pixels, 0, "a bald hero shouldn't have hair-colored pixels")


func test_different_hair_styles_render_differently():
	var seen := {}
	for style in HeroAppearance.HAIR_STYLE_COUNT:
		var appearance := appearance_maker.appearance_from_choices("warrior", {"hair_style": style})
		seen[sprite.generate_hero_head_image(Vector2i(14, 14), appearance).get_data()] = true
	assert_eq(seen.size(), HeroAppearance.HAIR_STYLE_COUNT, "each hair style should look distinct")


func test_different_beard_styles_render_differently():
	var seen := {}
	for beard in HeroAppearance.BEARD_STYLE_COUNT:
		var appearance := appearance_maker.appearance_from_choices("warrior", {"beard": beard})
		seen[sprite.generate_hero_head_image(Vector2i(14, 14), appearance).get_data()] = true
	assert_eq(seen.size(), HeroAppearance.BEARD_STYLE_COUNT, "each beard style should look distinct")


func test_head_carries_the_chosen_eye_color():
	var appearance := appearance_maker.appearance_from_choices("warrior", {"eyes": 2, "hair_style": 0})
	var image := sprite.generate_hero_head_image(Vector2i(14, 14), appearance)
	var found := false
	for y in 14:
		for x in 14:
			if _close(image.get_pixel(x, y), appearance.eyes):
				found = true
	assert_true(found, "the head should show the chosen eye color")


# -- full-body portrait (character creator preview) ---------------------------

func test_portrait_is_the_pinned_size():
	var image := sprite.generate_hero_portrait_image(appearance_maker.appearance_for("warrior", 1))
	assert_eq(Vector2i(image.get_width(), image.get_height()), ProceduralCharacterSprite.PORTRAIT_SIZE)


## One cohesive figure, not a floating head: the portrait must have opaque
## pixels through the head band, the torso band, AND the legs band.
func test_portrait_has_a_head_a_torso_and_legs():
	var image := sprite.generate_hero_portrait_image(appearance_maker.appearance_for("warrior", 1))
	var height := ProceduralCharacterSprite.PORTRAIT_SIZE.y
	for band in [[0, int(height * 0.3)], [int(height * 0.4), int(height * 0.6)], [int(height * 0.85), height]]:
		var opaque := 0
		for y in range(band[0], band[1]):
			for x in ProceduralCharacterSprite.PORTRAIT_SIZE.x:
				if image.get_pixel(x, y).a > 0.0:
					opaque += 1
		assert_gt(opaque, 0, "portrait band %s should contain the figure" % [band])


## Class identity is checked by HUE, not by an exact RGB match: the torso
## is shaded through PixelRamp (see docs/concept/pixel_art_engine.md),
## which deliberately shifts hue and value along the ramp, so the flat base
## color no longer appears literally anywhere. Matching it exactly would
## only pin the old flat-fill technique back in place.
func test_portrait_shows_the_class_tunic_color():
	var appearance := appearance_maker.appearance_for("mage", 1)
	var image := sprite.generate_hero_portrait_image(appearance)
	var tunic: Color = appearance.tunic
	var found := false
	for y in ProceduralCharacterSprite.PORTRAIT_SIZE.y:
		for x in ProceduralCharacterSprite.PORTRAIT_SIZE.x:
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 or pixel.s < 0.15:
				continue
			var hue_gap: float = absf(pixel.h - tunic.h)
			hue_gap = minf(hue_gap, 1.0 - hue_gap)  # hue is a wheel
			if hue_gap < 0.06:
				found = true
	assert_true(found, "the portrait should wear the class tunic color")


func test_portrait_is_deterministic():
	var appearance := appearance_maker.appearance_for("ranger", 8)
	assert_eq(
		sprite.generate_hero_portrait_image(appearance).get_data(),
		sprite.generate_hero_portrait_image(appearance).get_data()
	)


func test_portraits_of_different_heroes_differ():
	var a := sprite.generate_hero_portrait_image(appearance_maker.appearance_for("warrior", 1))
	var b := sprite.generate_hero_portrait_image(appearance_maker.appearance_for("mage", 99))
	assert_ne(a.get_data(), b.get_data())


## The character-creation preview must actually reflect the illustrated rig
## (asked directly: "rehaul the character rendering in game AND IN
## CREATION"), not just CharacterView's in-game paperdoll -- this portrait is
## what main_menu.gd's creator screen shows, generated independently of
## CharacterView since it composites raw Images rather than Sprite2D nodes.
## Skin tone is the one signal that can only move through the ILLUSTRATED
## head (its own luminance recolor, see IllustratedCharacterSprite
## .generate_head_texture) -- the procedural head is also skin-tone
## sensitive, so this alone wouldn't distinguish the two paths, but it does
## confirm the wiring is live at all, and the two portraits below are
## additionally checked for a directional lightness shift consistent with a
## real recolor rather than two arbitrary-looking images.
func test_portrait_changes_with_skin_tone():
	var pale := appearance_maker.appearance_from_choices("warrior", {"skin": 0}, 4242)
	var deep := appearance_maker.appearance_from_choices(
		"warrior", {"skin": HeroAppearance.SKIN_TONES.size() - 1}, 4242
	)
	assert_ne(pale.skin, deep.skin, "precondition: the two skin choices should actually differ")
	var pale_image := sprite.generate_hero_portrait_image(pale)
	var deep_image := sprite.generate_hero_portrait_image(deep)
	assert_ne(pale_image.get_data(), deep_image.get_data())


func test_portrait_is_a_cohesive_figure_when_legs_are_a_fused_pair():
	# leg.png draws both legs as one connected pose (see CharacterView's own
	# doc comment on legs fusion) -- the portrait has no separate LegLeft/
	# LegRight nodes to hide one of, so it must blend the fused pair ONCE
	# rather than the procedural path's "same small leg image blended
	# twice", or the legs band would show two overlapping copies instead of
	# one figure.
	var image := sprite.generate_hero_portrait_image(appearance_maker.appearance_for("warrior", 1))
	var height := ProceduralCharacterSprite.PORTRAIT_SIZE.y
	var opaque := 0
	for y in range(int(height * 0.85), height):
		for x in ProceduralCharacterSprite.PORTRAIT_SIZE.x:
			if image.get_pixel(x, y).a > 0.0:
				opaque += 1
	assert_gt(opaque, 0, "the legs band should still show the figure's legs")


## The character creator's class-icon row renders exactly this portrait, one
## per archetype, at one fixed DNA seed -- so "the icon IS a tiny preview of
## picking this class" is only true if the portraits actually differ. They
## did not: hero_composite.png's outfit rows are PRE-COLOURED, so the
## illustrated portrait path deliberately never tints by appearance.tunic /
## appearance.legs (re-tinting already-coloured art would double the colour),
## which left the class palette -- the ONLY thing that varies between these
## seven appearances -- with no channel into the image at all. All seven
## thumbnails came out byte-identical (reported live).
func test_every_class_portrait_is_a_visibly_different_image():
	var seen := {}
	for archetype in ClassArchetype.new().archetype_names():
		var appearance: Dictionary = appearance_maker.appearance_for(archetype, 0)
		var key := sprite.generate_hero_portrait_image(appearance).get_data().hex_encode()
		assert_false(
			seen.has(key),
			"%s renders pixel-identically to %s" % [archetype, seen.get(key, "")]
		)
		seen[key] = archetype


## The outfit row a hero wears has to stay DNA-derived too (asked directly,
## and the reason IllustratedCharacterSprite.outfit_variant_for exists) --
## the class picks a row, the seed rotates it, so two warriors are still
## dressed differently. The guard against "fix the icons by making every
## warrior wear the same coat".
func test_the_outfit_row_still_varies_with_the_dna_seed_within_one_class():
	var seen := {}
	for seed_value in 24:
		seen[appearance_maker.outfit_variant_for("warrior", seed_value)] = true
	assert_gt(seen.size(), 1, "every warrior seed picked the same outfit row")


func test_outfit_rows_are_in_range_and_deterministic():
	for archetype in ClassArchetype.new().archetype_names():
		for seed_value in 12:
			var row: int = appearance_maker.outfit_variant_for(archetype, seed_value)
			assert_between(row, 0, IllustratedCharacterSprite.HERO_COMPOSITE_ROWS - 1)
			assert_eq(row, appearance_maker.outfit_variant_for(archetype, seed_value))


## Every player archetype has to land on a row of its own at a shared seed --
## that, not the palette, is what makes the seven icons tell classes apart.
func test_every_archetype_takes_its_own_outfit_row_at_a_shared_seed():
	var rows := {}
	for archetype in ClassArchetype.new().archetype_names():
		var row: int = appearance_maker.outfit_variant_for(archetype, 0)
		assert_false(rows.has(row), "%s reuses %s's outfit row %d" % [archetype, rows.get(row, ""), row])
		rows[row] = archetype


## The row travels on the appearance dict, so every renderer of that
## appearance (portrait here, CharacterView's paperdoll in-world) dresses the
## same hero in the same outfit instead of each re-rolling its own.
func test_the_portrait_wears_the_outfit_row_the_appearance_carries():
	var appearance: Dictionary = appearance_maker.appearance_for("warrior", 3)
	assert_true(appearance.has("outfit_variant"), "the appearance should name the outfit row")
	var as_built := sprite.generate_hero_portrait_image(appearance).get_data()
	var moved := appearance.duplicate()
	moved["outfit_variant"] = (int(appearance["outfit_variant"]) + 1) % IllustratedCharacterSprite.HERO_COMPOSITE_ROWS
	assert_ne(as_built, sprite.generate_hero_portrait_image(moved).get_data())


func _close(a: Color, b: Color) -> bool:
	return a.a > 0.0 and Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < 0.02


# -- torso silhouette -------------------------------------------------------
#
# Silhouette is the strongest readability cue in pixel art. The tunic used
# to be a plain rectangle, so the hero read as a colored box with a head on
# it regardless of how well the interior was shaded.

## Shoulders are the widest point, the waist is pinched in, and the hem
## flares back out -- a body shape, not a box.
func test_torso_is_widest_at_the_shoulders_and_pinched_at_the_waist():
	var size := Vector2i(52, 76)
	var shoulder := sprite.torso_half_width(size, int(size.y * 0.12))
	var waist := sprite.torso_half_width(size, int(size.y * 0.55))
	var hem := sprite.torso_half_width(size, size.y - 2)
	assert_gt(shoulder, waist, "shoulders should be wider than the waist")
	assert_gt(hem, waist, "the hem should flare back out below the waist")


func test_torso_half_width_never_exceeds_the_canvas():
	var size := Vector2i(52, 76)
	for y in size.y:
		var half := sprite.torso_half_width(size, y)
		assert_between(half, 1.0, size.x / 2.0)


## The shaped silhouette must actually reach the image: some rows must have
## transparent pixels at the edges where the body narrows.
func test_tunic_image_has_a_shaped_not_rectangular_silhouette():
	var size := Vector2i(52, 76)
	var image := sprite.generate_hero_tunic_image(size, appearance_maker.appearance_for("warrior", 2))
	var widths := []
	for y in size.y:
		var w := 0
		for x in size.x:
			if image.get_pixel(x, y).a > 0.0:
				w += 1
		widths.append(w)
	var narrowest: int = widths.min()
	var widest: int = widths.max()
	assert_lt(narrowest, widest, "the torso should vary in width, not be a rectangle")


# -- flat 16-bit colour, not volumetric shading -----------------------------
#
# 16-bit character sprites are FLAT colour regions plus hand-placed detail
# (eyes, mouth, belt, collar) -- not per-pixel lit volumes. An earlier pass
# shaded the hero as lit cylinders and spheroids, which read as a soft 3D
# render however correct the lighting maths was.

func _distinct_colors(image: Image) -> int:
	var seen := {}
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0:
				seen[pixel] = true
	return seen.size()


## The garment is flat: its own colour, one shadow side, an outline, and
## trim. A per-pixel ramp across the body would blow far past this.
func test_tunic_uses_a_small_flat_palette():
	var image := sprite.generate_hero_tunic_image(
		Vector2i(26, 38), appearance_maker.appearance_for("warrior", 2)
	)
	assert_lte(_distinct_colors(image), 6, "the tunic should be flat colour, not a shaded gradient")


func test_limbs_use_a_small_flat_palette():
	var image := sprite.generate_body_part_image(Vector2i(8, 18), Color(0.7, 0.55, 0.4))
	assert_lte(_distinct_colors(image), 4, "a limb should be flat colour with one shadow side")


## Flat does NOT mean featureless -- the resolution exists to carry detail,
## so the face must still have its own distinct marks (eyes, brows, mouth)
## beyond the skin and outline.
func test_the_head_still_carries_real_facial_detail():
	var image := sprite.generate_hero_head_image(
		Vector2i(24, 24), appearance_maker.appearance_for("ranger", 4)
	)
	assert_gte(_distinct_colors(image), 6, "the face should carry eyes, brows and mouth detail")
