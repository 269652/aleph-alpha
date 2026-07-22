extends GutTest

const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SPECIES := ["boar", "lynx", "herbivore", "predator"]


func _has_pixel(image: Image, target: Color) -> bool:
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				return true
	return false

var generator: ProceduralAnimalSprite


func before_each():
	generator = ProceduralAnimalSprite.new()


func _opaque_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _pixel_diff_count(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func _average_opaque_color(image: Image) -> Color:
	var total := Color(0, 0, 0, 0)
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0:
				total += pixel
				count += 1
	return total / count if count > 0 else Color()


func test_generated_image_has_the_expected_size():
	for species in SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_width(), ProceduralAnimalSprite.WIDTH, species)
		assert_eq(image.get_height(), ProceduralAnimalSprite.HEIGHT, species)


func test_generated_image_has_transparent_corners():
	for species in SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_pixel(0, 0).a, 0.0, species)
		assert_eq(image.get_pixel(ProceduralAnimalSprite.WIDTH - 1, ProceduralAnimalSprite.HEIGHT - 1).a, 0.0, species)


func test_generated_image_has_a_substantial_opaque_body():
	for species in SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_gt(_opaque_count(image), 60, "%s should have a substantial body" % species)


func test_generated_image_is_not_a_single_flat_color():
	for species in SPECIES:
		var image: Image = generator.generate_image(species, 1)
		var distinct := {}
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0:
					distinct[pixel] = true
		assert_gt(distinct.size(), 3, "%s should be shaded and outlined" % species)


func test_generated_image_is_deterministic_per_species_and_seed():
	for species in SPECIES:
		var first: Image = generator.generate_image(species, 42)
		var second: Image = generator.generate_image(species, 42)
		assert_eq(_pixel_diff_count(first, second), 0, species)


func test_different_seeds_produce_a_visible_variation():
	var first: Image = generator.generate_image("boar", 1)
	var second: Image = generator.generate_image("boar", 2)
	assert_gt(_pixel_diff_count(first, second), 0, "seed should jitter shading")


func test_species_silhouettes_are_visibly_different_from_each_other():
	for i in SPECIES.size():
		for j in range(i + 1, SPECIES.size()):
			var a: Image = generator.generate_image(SPECIES[i], 7)
			var b: Image = generator.generate_image(SPECIES[j], 7)
			assert_gt(
				_pixel_diff_count(a, b),
				30,
				"%s vs %s should differ substantially" % [SPECIES[i], SPECIES[j]]
			)


func test_boar_is_browner_and_darker_than_lynx():
	var boar_avg := _average_opaque_color(generator.generate_image("boar", 3))
	var lynx_avg := _average_opaque_color(generator.generate_image("lynx", 3))
	assert_gt(boar_avg.r, boar_avg.b, "boar should be brown (red over blue)")
	assert_gt(lynx_avg.v, boar_avg.v, "lynx tawny coat should be lighter than boar")


func test_lynx_has_ear_tufts_reaching_the_top_rows_unlike_boar():
	var lynx: Image = generator.generate_image("lynx", 5)
	var boar: Image = generator.generate_image("boar", 5)
	var lynx_top_opaque := 0
	var boar_top_opaque := 0
	for y in 3:
		for x in ProceduralAnimalSprite.WIDTH:
			if lynx.get_pixel(x, y).a > 0.0:
				lynx_top_opaque += 1
			if boar.get_pixel(x, y).a > 0.0:
				boar_top_opaque += 1
	assert_gt(lynx_top_opaque, 0, "lynx ears should reach the top rows")
	assert_eq(boar_top_opaque, 0, "stocky boar should stay low in the frame")


func test_unknown_species_falls_back_to_herbivore_shape():
	var unknown: Image = generator.generate_image("mystery", 9)
	var herbivore: Image = generator.generate_image("herbivore", 9)
	assert_eq(_pixel_diff_count(unknown, herbivore), 0)


## Art-direction pass: every species is outlined with the shared near-black
## cool outline so it pops against the ground (Hammerwatch readability).
func test_species_are_ringed_with_the_shared_dark_outline():
	for species in SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_true(_has_pixel(image, PixelPalette.OUTLINE), "%s should use the shared outline" % species)


func test_generate_texture_returns_an_image_texture_of_matching_size():
	var texture: ImageTexture = generator.generate_texture("lynx", 1)
	assert_eq(texture.get_width(), ProceduralAnimalSprite.WIDTH)
	assert_eq(texture.get_height(), ProceduralAnimalSprite.HEIGHT)
