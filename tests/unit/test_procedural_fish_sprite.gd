extends GutTest

const ProceduralFishSprite = preload("res://src/rendering/procedural_fish_sprite.gd")

var generator := ProceduralFishSprite.new()


func test_image_has_the_expected_size():
	var image := generator.generate_image("goldfish", 0)
	assert_eq(image.get_width(), ProceduralFishSprite.SIZE.x)
	assert_eq(image.get_height(), ProceduralFishSprite.SIZE.y)


func test_has_transparent_corners_and_an_opaque_body():
	var image := generator.generate_image("goldfish", 0)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	var mid := Vector2i(ProceduralFishSprite.SIZE.x / 2, ProceduralFishSprite.SIZE.y / 2)
	assert_gt(image.get_pixel(mid.x, mid.y).a, 0.0)


func test_is_deterministic_for_the_same_species_and_seed():
	var a := generator.generate_image("trout", 5)
	var b := generator.generate_image("trout", 5)
	assert_eq(a.get_data(), b.get_data())


## Colorful and multiple varieties: every known species has its OWN look,
## not a shared generic silhouette recolored the same way each time.
func test_every_known_species_has_a_distinct_base_color():
	var seen_colors := {}
	for species in ProceduralFishSprite.SPECIES_IDS:
		seen_colors[ProceduralFishSprite.SPECIES_BASE_COLORS[species]] = true
	assert_eq(seen_colors.size(), ProceduralFishSprite.SPECIES_IDS.size(), "every species should have a unique base color")


func test_species_colors_are_vividly_saturated_not_muddy():
	for species in ProceduralFishSprite.SPECIES_IDS:
		var color: Color = ProceduralFishSprite.SPECIES_BASE_COLORS[species]
		assert_gt(color.s, 0.4, "%s should read as a colorful, vivid fish" % species)


func test_different_species_render_different_images():
	var a := generator.generate_image("goldfish", 0)
	var b := generator.generate_image("bluegill", 0)
	assert_ne(a.get_data(), b.get_data())


func test_unknown_species_falls_back_to_a_valid_image_rather_than_crashing():
	var image := generator.generate_image("not_a_real_fish", 0)
	assert_eq(image.get_width(), ProceduralFishSprite.SIZE.x)


func test_generate_texture_returns_an_image_texture():
	var texture := generator.generate_texture("koi", 3)
	assert_eq(texture.get_width(), ProceduralFishSprite.SIZE.x)


## Different seeds of the same species still look like individuals (mirrors
## the shade-jitter technique used elsewhere -- see procedural_animal_sprite).
func test_different_seeds_of_the_same_species_vary_slightly():
	var a := generator.generate_image("trout", 1)
	var b := generator.generate_image("trout", 2)
	assert_ne(a.get_data(), b.get_data())
