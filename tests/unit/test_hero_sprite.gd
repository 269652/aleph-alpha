extends GutTest

## The hero-appearance engine: (class archetype, dna seed) -> a deterministic
## visual identity (skin tone, hair color/style, class-colored tunic + trim),
## rendered by ProceduralCharacterSprite's hero generators -- so the player
## reads as a distinct Hammerwatch-style hero, not a generic blue rectangle
## person, and two heroes of the same class still differ by their DNA seed.

const HeroAppearance = preload("res://src/rendering/hero_appearance.gd")
const ProceduralCharacterSprite = preload("res://src/rendering/procedural_character_sprite.gd")

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


func test_portrait_shows_the_class_tunic_color():
	var appearance := appearance_maker.appearance_for("mage", 1)
	var image := sprite.generate_hero_portrait_image(appearance)
	var found := false
	for y in ProceduralCharacterSprite.PORTRAIT_SIZE.y:
		for x in ProceduralCharacterSprite.PORTRAIT_SIZE.x:
			if _close(image.get_pixel(x, y), appearance.tunic):
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


func _close(a: Color, b: Color) -> bool:
	return a.a > 0.0 and Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < 0.02
