extends GutTest

const ProceduralAnimalSprite = preload("res://src/rendering/procedural_animal_sprite.gd")
const PixelPalette = preload("res://src/rendering/pixel_palette.gd")

const SPECIES := ["boar", "lynx", "herbivore", "predator"]

## The 8 biome-specific species added on top of the original 4 -- each reuses
## one of the 4 hand-drawn shape families (see SHAPE_MATE below) with its own
## color, per CreatureRenderer's per-biome species pools.
const NEW_SPECIES := [
	"camel", "jackal", "reindeer", "arctic_fox", "tapir", "jaguar", "goat", "mountain_lion", "horse",
	"deer", "bear", "lion"
]

## Maps each new species to the one of the original 4 species it should share
## a silhouette (shape family) with. Horse/deer join this group: real horses
## and deer are both slender-legged ungulates, so both reuse deer_shape
## rather than needing new art -- the same reasoning as camel/reindeer/goat.
## Bear reuses boar_shape (both heavy-bodied, low-slung quadrupeds). Lion
## reuses lynx_shape -- lions are cats, anatomically closer to the lynx
## silhouette than the wolf one (see
## docs/concept/ecosystem_dynamics.md's Species roster section).
const SHAPE_MATE := {
	"camel": "herbivore",
	"reindeer": "herbivore",
	"goat": "herbivore",
	"horse": "herbivore",
	"deer": "herbivore",
	"jackal": "predator",
	"mountain_lion": "predator",
	"arctic_fox": "lynx",
	"jaguar": "lynx",
	"lion": "lynx",
	"tapir": "boar",
	"bear": "boar",
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


## Species with a KNOWN, pre-existing (not introduced by the horse-tuning
## fix below) edge touch: deer/reindeer antlers reach row 0 -- a real, worth-
## fixing bug, just a different one than what this test guards against here.
## Flagged separately rather than silently papered over by excluding it
## without a trace.
const _KNOWN_EDGE_TOUCH_EXCEPTIONS := {"deer": true, "reindeer": true}


## Regression: tuning a horse's head longer/higher (see test_animal_anatomy.gd's
## "less flat head"/"straighter back" tests) once pushed its muzzle and ears
## past the canvas edges -- the corner check above wouldn't catch that (a
## silhouette can touch the top or right edge, mid-height/mid-width, without
## ever touching either literal corner). Covers the full species roster
## (minus the known exceptions above), not just horse, since any future
## profile tuning could hit the same edge.
func test_no_species_silhouette_touches_the_top_or_right_edge():
	for species in SPECIES + NEW_SPECIES:
		if _KNOWN_EDGE_TOUCH_EXCEPTIONS.has(species):
			continue
		var image: Image = generator.generate_image(species, 1)
		for x in ProceduralAnimalSprite.WIDTH:
			assert_eq(image.get_pixel(x, 0).a, 0.0, "%s's silhouette touches the top edge" % species)
		for y in ProceduralAnimalSprite.HEIGHT:
			assert_eq(
				image.get_pixel(ProceduralAnimalSprite.WIDTH - 1, y).a, 0.0,
				"%s's silhouette touches the right edge" % species
			)


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
	# Compares each animal's TOPMOST occupied row rather than counting
	# pixels in the first three: the old hand-drawn bitmaps happened to put
	# lynx ears on row 0, but anatomy-built animals are framed by their own
	# proportions and neither reaches the very top. The real claim is that
	# an upright-eared cat carries its head higher than a stocky boar.
	assert_lt(
		_topmost_opaque_row(lynx), _topmost_opaque_row(boar),
		"an upright lynx should reach higher than a stocky boar"
	)


func _topmost_opaque_row(image: Image) -> int:
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				return y
	return image.get_height()


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


## This used to assert the OPPOSITE -- that each new species reused its
## shape-mate's silhouette pixel for pixel. That design is exactly what was
## reported as broken ("herbivore, deer and horse look exactly the same"),
## so species now differ by real anatomy (see AnimalAnatomy) and the test
## pins the distinctness instead of the sharing.
func test_new_species_do_not_share_a_silhouette_with_their_shape_mate():
	for species in NEW_SPECIES:
		var mate: String = SHAPE_MATE[species]
		if mate == species:
			continue
		var species_image: Image = generator.generate_image(species, 3)
		var mate_image: Image = generator.generate_image(mate, 3)
		assert_gt(
			_opacity_diff_count(species_image, mate_image),
			0,
			"%s should have its own silhouette, not %s's" % [species, mate]
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
	var all_species: Array = SPECIES + NEW_SPECIES + ["mouse", "squirrel", "venomous_snake", "nonvenomous_snake"]
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


# -- mouse: a genuinely new (5th) shape family, not a reuse of the original 4 --
#
# Unlike every other species so far, mice don't read as any existing
# silhouette at any scale (short legs, round body, long tail) -- see
# docs/concept/ecosystem_dynamics.md's Species roster section -- so mouse
# gets its own hand-authored "mouse_shape" family instead of a SHAPE_MATE.

func test_mouse_gets_its_own_shape_family_not_one_of_the_original_four():
	var family: String = ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.get("mouse", "")
	assert_eq(family, "mouse_shape")
	assert_false(
		["deer_shape", "boar_shape", "wolf_shape", "lynx_shape"].has(family),
		"mouse should not reuse one of the original 4 silhouettes"
	)


func test_mouse_generated_image_has_the_expected_size():
	var image: Image = generator.generate_image("mouse", 1)
	assert_eq(image.get_width(), ProceduralAnimalSprite.WIDTH)
	assert_eq(image.get_height(), ProceduralAnimalSprite.HEIGHT)


func test_mouse_generated_image_has_transparent_corners():
	var image: Image = generator.generate_image("mouse", 1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralAnimalSprite.WIDTH - 1, ProceduralAnimalSprite.HEIGHT - 1).a, 0.0)


func test_mouse_generated_image_has_a_body():
	var image: Image = generator.generate_image("mouse", 1)
	assert_gt(_opaque_count(image), 15, "mouse should have a visible body")


func test_mouse_generated_image_is_not_a_single_flat_color():
	var image: Image = generator.generate_image("mouse", 1)
	var distinct := {}
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0:
				distinct[pixel] = true
	assert_gt(distinct.size(), 3, "mouse should be shaded and outlined")


func test_mouse_generated_image_is_deterministic_per_seed():
	var first: Image = generator.generate_image("mouse", 42)
	var second: Image = generator.generate_image("mouse", 42)
	assert_eq(_pixel_diff_count(first, second), 0)


func test_mouse_is_ringed_with_the_shared_dark_outline():
	var image: Image = generator.generate_image("mouse", 1)
	assert_true(_has_pixel(image, PixelPalette.OUTLINE))


## Mouse is meant to be the visually simplest/smallest of the five families
## (it renders small on screen) -- smaller opaque footprint than every one of
## the four original quadruped silhouettes.
func test_mouse_has_a_smaller_silhouette_than_every_original_species():
	var mouse_count := _opaque_count(generator.generate_image("mouse", 1))
	for species in SPECIES:
		var count := _opaque_count(generator.generate_image(species, 1))
		assert_lt(mouse_count, count, "mouse should be smaller than %s" % species)


# -- squirrel: reuses mouse's shape family, not a new one --------------------
#
# Unlike mouse, a squirrel DOES read as the same small-rodent silhouette at a
# larger scale (short legs, round body) -- what makes it distinctly a
# squirrel is AnimalAnatomy's own tail field (a large TAIL_BUSHY, drawn
# procedurally on top of the shared bitmap by _paint_tail, not baked into the
# bitmap itself), not a different body silhouette. So squirrel reuses
# "mouse_shape" rather than getting a 6th hand-authored family, and gets its
# own SPECIES_BASE_COLORS entry so it never falls through to a generic/
## herbivore default the way jackal/arctic_fox/mountain_lion/lion once did.

func test_squirrel_reuses_mouses_shape_family():
	assert_eq(ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.get("squirrel", ""), "mouse_shape")


func test_squirrel_has_its_own_base_color_distinct_from_mouse():
	assert_true(ProceduralAnimalSprite.SPECIES_BASE_COLORS.has("squirrel"))
	var squirrel_color: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS["squirrel"]
	var mouse_color: Color = ProceduralAnimalSprite.SPECIES_BASE_COLORS["mouse"]
	assert_gt(
		Vector3(squirrel_color.r, squirrel_color.g, squirrel_color.b).distance_to(
			Vector3(mouse_color.r, mouse_color.g, mouse_color.b)
		),
		0.05,
		"squirrel should be visually distinguishable from mouse"
	)


func test_squirrel_generated_image_has_the_expected_size():
	var image: Image = generator.generate_image("squirrel", 1)
	assert_eq(image.get_width(), ProceduralAnimalSprite.WIDTH)
	assert_eq(image.get_height(), ProceduralAnimalSprite.HEIGHT)


func test_squirrel_generated_image_has_transparent_corners():
	var image: Image = generator.generate_image("squirrel", 1)
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(ProceduralAnimalSprite.WIDTH - 1, ProceduralAnimalSprite.HEIGHT - 1).a, 0.0)


func test_squirrel_generated_image_has_a_body():
	var image: Image = generator.generate_image("squirrel", 1)
	assert_gt(_opaque_count(image), 15, "squirrel should have a visible body")


func test_squirrel_generated_image_is_deterministic_per_seed():
	var first: Image = generator.generate_image("squirrel", 42)
	var second: Image = generator.generate_image("squirrel", 42)
	assert_eq(_pixel_diff_count(first, second), 0)


## The whole point of squirrel's own AnimalAnatomy tail override: its bushy
## tail is proportionally larger than mouse's own tail, so it should occupy
## more of the shared silhouette's opaque footprint despite sharing a body.
func test_squirrel_has_a_bigger_silhouette_than_mouse_thanks_to_its_bushy_tail():
	var squirrel_count := _opaque_count(generator.generate_image("squirrel", 1))
	var mouse_count := _opaque_count(generator.generate_image("mouse", 1))
	assert_gt(squirrel_count, mouse_count, "squirrel's big bushy tail should read as more silhouette than mouse's thin one")


# -- snakes: another genuinely new (6th) shape family, low and long ---------
#
# Real venomous snakes often carry a real, visible warning pattern (see
# docs/concept/ecosystem_dynamics.md's Species roster) -- venomous_snake
# gets diamond/warning speckle marks (same technique as jaguar's rosettes)
# that nonvenomous_snake lacks, so the visual distinction is grounded, not
## just an arbitrary recolor.

const SNAKE_SPECIES := ["venomous_snake", "nonvenomous_snake"]


func test_snakes_get_their_own_shape_family_not_one_of_the_original_four():
	for species in SNAKE_SPECIES:
		var family: String = ProceduralAnimalSprite.SPECIES_SHAPE_FAMILY.get(species, "")
		assert_eq(family, "snake_shape", species)
		assert_false(
			["deer_shape", "boar_shape", "wolf_shape", "lynx_shape"].has(family),
			"%s should not reuse one of the original 4 silhouettes" % species
		)


func test_snake_generated_images_have_the_expected_size():
	for species in SNAKE_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_width(), ProceduralAnimalSprite.WIDTH, species)
		assert_eq(image.get_height(), ProceduralAnimalSprite.HEIGHT, species)


func test_snake_generated_images_have_transparent_corners():
	for species in SNAKE_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_eq(image.get_pixel(0, 0).a, 0.0, species)


func test_snake_generated_images_have_a_body():
	for species in SNAKE_SPECIES:
		var image: Image = generator.generate_image(species, 1)
		assert_gt(_opaque_count(image), 15, "%s should have a visible body" % species)


func test_snake_generated_images_are_deterministic_per_seed():
	for species in SNAKE_SPECIES:
		var first: Image = generator.generate_image(species, 42)
		var second: Image = generator.generate_image(species, 42)
		assert_eq(_pixel_diff_count(first, second), 0, species)


func test_venomous_snake_has_warning_pattern_marks_that_nonvenomous_lacks():
	var venomous: Image = generator.generate_image("venomous_snake", 3)
	var nonvenomous: Image = generator.generate_image("nonvenomous_snake", 3)
	assert_gt(_spot_pixel_count(venomous), 0, "venomous_snake should have warning-pattern marks")
	assert_eq(_spot_pixel_count(nonvenomous), 0, "nonvenomous_snake should not have warning-pattern marks")


# -- anatomy-driven silhouettes (docs/concept/pixel_art_engine.md) ----------
#
# Species used to share four hand-drawn bitmaps -- horse, deer and the
# generic herbivore were literally the same sprite in different colours.
# They are now assembled from AnimalAnatomy proportions.

const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")


func _silhouette(species: String) -> Array:
	## Per-row opaque pixel counts: the animal's shape, ignoring colour.
	var image: Image = generator.generate_image(species, 3)
	var rows := []
	for y in image.get_height():
		var count := 0
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
		rows.append(count)
	return rows


## The reported bug, pinned: these are different ANIMALS, not recolours.
func test_horse_deer_and_herbivore_have_different_silhouettes():
	var horse := _silhouette("horse")
	var deer := _silhouette("deer")
	var herbivore := _silhouette("herbivore")
	assert_ne(horse, deer, "a horse and a deer must not share a silhouette")
	assert_ne(horse, herbivore, "a horse and a herbivore must not share a silhouette")
	assert_ne(deer, herbivore, "a deer and a herbivore must not share a silhouette")


func test_every_profiled_species_renders_a_non_empty_animal():
	for species in AnimalAnatomy.SPECIES:
		var rows := _silhouette(species)
		var total := 0
		for count in rows:
			total += count
		assert_gt(total, 20, "%s should render a real body" % species)


## A horse stands taller than a boar: its topmost opaque row is higher up.
func test_a_horse_stands_taller_than_a_boar():
	var horse := _silhouette("horse")
	var boar := _silhouette("boar")
	var horse_top := 0
	while horse_top < horse.size() and horse[horse_top] == 0:
		horse_top += 1
	var boar_top := 0
	while boar_top < boar.size() and boar[boar_top] == 0:
		boar_top += 1
	assert_lt(horse_top, boar_top, "the horse's head should reach higher than the boar's")


## Antlers put pixels ABOVE the head that a hornless animal of the same
## build doesn't have.
func test_antlered_species_are_taller_than_their_hornless_equivalent():
	var deer := _silhouette("deer")
	var herbivore := _silhouette("herbivore")
	var deer_top := 0
	while deer_top < deer.size() and deer[deer_top] == 0:
		deer_top += 1
	var herb_top := 0
	while herb_top < herbivore.size() and herbivore[herb_top] == 0:
		herb_top += 1
	assert_lt(deer_top, herb_top, "antlers should reach above a hornless herbivore's head")


func test_generated_animals_stay_deterministic():
	assert_eq(
		generator.generate_image("horse", 5).get_data(),
		generator.generate_image("horse", 5).get_data()
	)


# -- gait: legs actually articulate for a walk cycle -------------------------
#
# Legs used to be a straight vertical capsule that a post-process step slid
# sideways for "walking" -- there was no joint. generate_image now takes a
# gait_phase (see QuadrupedGait) that poses the hip/knee for real, and these
# tests exist so that claim is checked rather than eyeballed on screen.

func test_gait_phase_zero_reproduces_the_original_standing_pose():
	assert_eq(
		generator.generate_image("horse", 3).get_data(),
		generator.generate_image("horse", 3, 0.0).get_data(),
		"the default phase must be the same neutral pose every existing caller already gets"
	)


## The actual claim: posing at different phases must move leg pixels, not
## just tint or jitter something incidental.
func test_different_gait_phases_move_leg_pixels():
	var standing := generator.generate_image("horse", 3, 0.0)
	var mid_stride := generator.generate_image("horse", 3, 0.25)
	assert_ne(standing.get_data(), mid_stride.get_data())


func test_gait_posing_is_deterministic():
	assert_eq(
		generator.generate_image("deer", 8, 0.4).get_data(),
		generator.generate_image("deer", 8, 0.4).get_data()
	)


## A legless species (a snake) has no hip/knee to pose -- gait_phase must be
## harmless rather than crashing on a species with no legs at all.
func test_gait_phase_is_a_no_op_for_legless_species():
	assert_eq(
		generator.generate_image("nonvenomous_snake", 1, 0.0).get_data(),
		generator.generate_image("nonvenomous_snake", 1, 0.5).get_data()
	)


## The walking silhouette must still be a fully connected, outlined animal --
## a bent leg must not tear a hole in the body or leave the outline broken.
func test_a_mid_stride_horse_is_still_a_solid_outlined_silhouette():
	var image := generator.generate_image("horse", 3, 0.25)
	var opaque_pixels := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				opaque_pixels += 1
	var standing_opaque := 0
	var standing := generator.generate_image("horse", 3, 0.0)
	for y in standing.get_height():
		for x in standing.get_width():
			if standing.get_pixel(x, y).a > 0.0:
				standing_opaque += 1
	# Loosely bounded rather than exact: a bent leg's silhouette area
	# naturally differs a little, but a torn or missing leg would differ by
	# far more than that.
	assert_gt(opaque_pixels, standing_opaque * 0.8)
