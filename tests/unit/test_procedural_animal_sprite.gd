extends GutTest

const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SPECIES := ["boar", "lynx", "herbivore", "predator"]

## The 8 biome-specific species added on top of the original 4 -- each reuses
## one of the 4 hand-drawn shape families (see SHAPE_MATE below) with its own
## color, per CreatureRenderer's per-biome species pools.
const NEW_SPECIES := [
	"camel", "jackal", "reindeer", "arctic_fox", "tapir", "jaguar", "goat", "mountain_lion"
]

## Maps each new species to the one of the original 4 species it should share
## a silhouette (shape family) with.
const SHAPE_MATE := {
	"camel": "herbivore",
	"reindeer": "herbivore",
	"goat": "herbivore",
	"jackal": "predator",
	"mountain_lion": "predator",
	"arctic_fox": "lynx",
	"jaguar": "lynx",
	"tapir": "boar",
}


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


## Counts pixels where the two images disagree on whether that pixel is part
## of the silhouette (opaque) at all -- unlike _pixel_diff_count, this ignores
## color, so it isolates shape differences from color differences. Two
## species sharing a shape family (different color, same silhouette) should
## score 0 here.
func _opacity_diff_count(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if (a.get_pixel(x, y).a > 0.0) != (b.get_pixel(x, y).a > 0.0):
				count += 1
	return count


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


# -- new biome-specific species (shape-family reuse) --------------------------


func test_species_shape_family_maps_every_species_to_one_of_the_four_families():
	var valid_families := ["deer_shape", "boar_shape", "wolf_shape", "lynx_shape"]
	for species in SPECIES + NEW_SPECIES:
		var family: String = ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.get(species, "")
		assert_true(
			valid_families.has(family),
			"%s should map to one of the 4 shape families, got '%s'" % [species, family]
		)


func test_new_species_generated_image_has_the_expected_size():
	for species in NEW_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_width(), ProceduralAnimalSprite.WIDTH, species)
		assert_eq(image.get_height(), ProceduralAnimalSprite.HEIGHT, species)


func test_new_species_generated_image_has_transparent_corners():
	for species in NEW_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_pixel(0, 0).a, 0.0, species)
		assert_eq(image.get_pixel(ProceduralAnimalSprite.WIDTH - 1, ProceduralAnimalSprite.HEIGHT - 1).a, 0.0, species)


func test_new_species_generated_image_has_a_substantial_opaque_body():
	for species in NEW_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_gt(_opaque_count(image), 60, "%s should have a substantial body" % species)


func test_new_species_generated_image_is_not_a_single_flat_color():
	for species in NEW_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		var distinct := {}
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.0:
					distinct[pixel] = true
		assert_gt(distinct.size(), 3, "%s should be shaded and outlined" % species)


func test_new_species_generated_image_is_deterministic_per_species_and_seed():
	for species in NEW_SPECIES:
		var first: Image = generator.generate_image(species, 42)
		var second: Image = generator.generate_image(species, 42)
		assert_eq(_pixel_diff_count(first, second), 0, species)


func test_new_species_are_ringed_with_the_shared_dark_outline():
	for species in NEW_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_true(_has_pixel(image, PixelPalette.OUTLINE), "%s should use the shared outline" % species)


func test_new_species_reuse_their_shape_mates_silhouette():
	for species in NEW_SPECIES:
		var mate: String = SHAPE_MATE[species]
		var species_image: Image = generator.generate_image(species, 3)
		var mate_image: Image = generator.generate_image(mate, 3)
		assert_eq(
			_opacity_diff_count(species_image, mate_image),
			0,
			"%s should reuse %s's silhouette" % [species, mate]
		)


func test_new_species_have_a_base_color_distinct_from_their_shape_mate():
	for species in NEW_SPECIES:
		var mate: String = SHAPE_MATE[species]
		var species_color: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS[species]
		var mate_color: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS[mate]
		assert_gt(
			Vector3(species_color.r, species_color.g, species_color.b).distance_to(
				Vector3(mate_color.r, mate_color.g, mate_color.b)
			),
			0.05,
			"%s should be visually distinguishable from %s" % [species, mate]
		)


func test_every_species_has_a_visually_distinct_base_color_from_every_other():
	var all_species: Array = SPECIES + NEW_SPECIES
	for i in all_species.size():
		for j in range(i + 1, all_species.size()):
			var a: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS[all_species[i]]
			var b: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS[all_species[j]]
			assert_gt(
				Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)),
				0.02,
				"%s vs %s should be visually distinguishable" % [all_species[i], all_species[j]]
			)


func test_tapir_is_darker_than_boar_despite_sharing_its_shape():
	var tapir_avg := _average_opaque_color(generator.generate_image("tapir", 3))
	var boar_avg := _average_opaque_color(generator.generate_image("boar", 3))
	assert_lt(tapir_avg.v, boar_avg.v, "tapir should read as a darker grey-brown than boar")


## Optional art-direction detail: jaguar (lynx-shaped) gets a scatter of dark
## rosette-like speckle dots so it doesn't read as a plain recolor of the
## other lynx-shaped species -- same speckle technique as
## ProceduralTreeSprite._paint_speckles. arctic_fox (also lynx-shaped) should
## NOT have them.
func _spot_pixel_count(image: Image) -> int:
	# Image.FORMAT_RGBA8 quantizes float colors to 8 bits per channel, so an
	## exact `==` against the raw JAGUAR_SPOT_COLOR constant would spuriously
	# fail -- use the same distance-based approach as _has_pixel() above.
	var count := 0
	var target := ProceduralAnimalSprite.JAGUAR_SPOT_COLOR
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and Vector3(p.r, p.g, p.b).distance_to(Vector3(target.r, target.g, target.b)) < 0.01:
				count += 1
	return count


func test_jaguar_has_speckle_spots_that_other_lynx_shaped_species_lack():
	var jaguar: Image = generator.generate_image("jaguar", 3)
	var arctic_fox: Image = generator.generate_image("arctic_fox", 3)
	assert_gt(_spot_pixel_count(jaguar), 0, "jaguar should have speckle spots")
	assert_eq(_spot_pixel_count(arctic_fox), 0, "arctic_fox should not have jaguar's speckle spots")
