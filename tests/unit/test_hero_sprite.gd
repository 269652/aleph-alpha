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


func _close(a: Color, b: Color) -> bool:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < 0.02
