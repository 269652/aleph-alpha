extends GutTest

## Pixel art for the sward's four rosette species (see
## docs/concept/ground_cover.md).
##
## Unlike ProceduralGrassSprite/ScrubSprite/LichenSprite -- blades rising from
## the BOTTOM edge of their canvas -- a rosette radiates from its own CENTRE
## and lies flat on the ground. That difference is the whole reason this is its
## own generator rather than another colour on the shared blade technique.

const ProceduralSwardSprite = preload("res://src/rendering/procedural_sward_sprite.gd")
const GroundCover = preload("res://src/world/ground_cover.gd")


func _opaque_pixels(image: Image) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				found.append(Vector2i(x, y))
	return found


# -- every species is real ---------------------------------------------------


func test_every_species_paints_something():
	for index in GroundCover.SPECIES.size():
		var image := ProceduralSwardSprite.new().generate_image(index, 1234)
		assert_gt(_opaque_pixels(image).size(), 8, "%s painted nothing" % GroundCover.SPECIES[index])


## Four species that painted the same shape would be one species wearing four
## names -- the meadow has to read as a mixed sward.
func test_the_species_do_not_all_look_the_same():
	var silhouettes := {}
	for index in GroundCover.SPECIES.size():
		var pixels := _opaque_pixels(ProceduralSwardSprite.new().generate_image(index, 7))
		silhouettes[str(pixels)] = true
	assert_eq(silhouettes.size(), GroundCover.SPECIES.size(), "two species paint the same silhouette")


## ...and neither do two plants of the SAME species, or a lawn reads as stamped
## clones. This is the bug PixelNoise exists to prevent, in a new place.
func test_two_plants_of_one_species_are_not_identical():
	var first := _opaque_pixels(ProceduralSwardSprite.new().generate_image(0, 11))
	var second := _opaque_pixels(ProceduralSwardSprite.new().generate_image(0, 12))
	assert_ne(str(first), str(second))


func test_the_same_seed_paints_the_same_plant():
	var first := ProceduralSwardSprite.new().generate_image(2, 99)
	var second := ProceduralSwardSprite.new().generate_image(2, 99)
	assert_eq(str(_opaque_pixels(first)), str(_opaque_pixels(second)))


# -- it is a rosette, not a tuft ---------------------------------------------


## A rosette radiates from its own centre. If the art hugged the bottom edge
## the way a grass tuft does, every plant would sit visibly below the point the
## simulation placed it once the MultiMesh centres a quad on that point.
func test_a_rosette_is_centred_on_its_canvas():
	for index in GroundCover.SPECIES.size():
		var pixels := _opaque_pixels(ProceduralSwardSprite.new().generate_image(index, 5))
		var sum := Vector2.ZERO
		for pixel in pixels:
			sum += Vector2(pixel)
		var centroid := sum / float(pixels.size())
		var canvas_centre := Vector2(ProceduralSwardSprite.SIZE) * 0.5
		assert_lt(
			centroid.distance_to(canvas_centre),
			float(ProceduralSwardSprite.SIZE.x) * 0.15,
			"%s is not centred on its canvas" % GroundCover.SPECIES[index]
		)


## Leaves radiate outward, so a rosette must not be a solid blob -- there has
## to be ground visible between the leaves or the sward reads as paint.
func test_a_rosette_is_leaves_and_not_a_disc():
	for index in GroundCover.SPECIES.size():
		var image := ProceduralSwardSprite.new().generate_image(index, 3)
		var painted := _opaque_pixels(image).size()
		var canvas := ProceduralSwardSprite.SIZE.x * ProceduralSwardSprite.SIZE.y
		assert_lt(
			float(painted) / float(canvas),
			0.5,
			"%s covers more than half its canvas" % GroundCover.SPECIES[index]
		)


func test_nothing_is_painted_outside_the_canvas():
	for index in GroundCover.SPECIES.size():
		for seed_value in 12:
			var image := ProceduralSwardSprite.new().generate_image(index, seed_value)
			assert_eq(image.get_width(), ProceduralSwardSprite.SIZE.x)
			assert_eq(image.get_height(), ProceduralSwardSprite.SIZE.y)


## An unknown index is a real case in this codebase, not defensiveness: it must
## paint an ordinary plant rather than an empty square that would read as a
## hole in the meadow.
func test_an_unknown_species_still_paints_a_plant():
	assert_gt(_opaque_pixels(ProceduralSwardSprite.new().generate_image(99, 1)).size(), 8)


# -- it has to read as a plant -----------------------------------------------


## Green, and not by accident: every painted pixel's green channel leads. A
## sward that came out grey or magenta would be a silent art bug that only a
## screenshot would ever catch.
func test_the_sward_is_green():
	for index in GroundCover.SPECIES.size():
		var image := ProceduralSwardSprite.new().generate_image(index, 21)
		for pixel in _opaque_pixels(image):
			var colour := image.get_pixel(pixel.x, pixel.y)
			assert_gt(colour.g, colour.r, "%s is not green" % GroundCover.SPECIES[index])
			assert_gt(colour.g, colour.b, "%s is not green" % GroundCover.SPECIES[index])


## ...but not all the SAME green, or four species would read as one plant in
## four sizes.
func test_the_species_are_not_all_the_same_green():
	var greens := {}
	for index in GroundCover.SPECIES.size():
		greens[ProceduralSwardSprite.LEAF_COLORS[index].to_html()] = true
	assert_eq(greens.size(), GroundCover.SPECIES.size())


## One colour per species, always -- an index with no colour would fall off the
## end of the table the moment a species is added.
func test_every_species_has_a_colour():
	assert_eq(ProceduralSwardSprite.LEAF_COLORS.size(), GroundCover.SPECIES.size())


# -- the atlas the renderer actually binds -----------------------------------


## The renderer holds one texture per species, cached: a chunk that unloads and
## reloads asks for the same texture back instead of a fresh repaint (the same
## reasoning ProceduralScrubSprite's own cache gives).
func test_a_texture_is_cached_per_species_and_seed():
	var generator := ProceduralSwardSprite.new()
	assert_same(generator.generate_texture(1, 42), generator.generate_texture(1, 42))


func test_different_seeds_are_different_textures():
	var generator := ProceduralSwardSprite.new()
	assert_not_same(generator.generate_texture(1, 42), generator.generate_texture(1, 43))


# -- it has to sit ON the grass, not on top of it ----------------------------
#
# Reported live from a real screenshot after the first pass landed: the
# plantain and yarrow rosettes read as pale white STARS scattered over the
# meadow rather than as plants growing in it. The cause was straightforward and
# is worth pinning so it cannot come back -- their leaf colours, and especially
# their midrib highlights, were LIGHTER than the grassland tile they were drawn
# against, so the eye read them as objects lying on the ground instead of as
# vegetation.


const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")


## Every sward pixel must be no brighter than the grass it grows in. Ground
## cover seen from above is a DENSER patch of green, not a paler one.
func test_no_sward_pixel_is_brighter_than_the_grass_it_grows_in():
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	for index in GroundCover.SPECIES.size():
		for seed_value in 8:
			var image := ProceduralSwardSprite.new().generate_image(index, seed_value)
			for pixel in _opaque_pixels(image):
				var colour := image.get_pixel(pixel.x, pixel.y)
				assert_lte(
					colour.get_luminance(),
					grassland.get_luminance(),
					(
						"%s paints a pixel brighter than grassland -- it will read as a pale star"
						% GroundCover.SPECIES[index]
					)
				)


## ...and the highlight, which is the pixel that actually went wrong, is a
## SHADING of the leaf rather than a near-white one.
func test_the_leaf_highlight_is_a_shading_not_a_flash():
	assert_lt(ProceduralSwardSprite.HIGHLIGHT_LIGHTEN, 0.15)


## Luminance alone did not catch it. The plantain and yarrow that read as pale
## stars were no BRIGHTER than the grass -- they were less SATURATED than it,
## and a washed-out green against a vivid one reads as grey however dark it is.
## That is the property worth pinning, and it is the one the first pass missed.
func test_no_sward_species_is_washed_out_against_the_grass():
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	for index in GroundCover.SPECIES.size():
		var leaf: Color = ProceduralSwardSprite.LEAF_COLORS[index]
		assert_gte(
			leaf.s,
			grassland.s * ProceduralSwardSprite.MIN_SATURATION_OF_GRASS,
			(
				"%s is washed out next to grassland -- it will read as grey, not as a plant"
				% GroundCover.SPECIES[index]
			)
		)


## ...and darker than it, so a rosette reads as a denser patch of green rather
## than something lying on top of the meadow.
func test_every_sward_species_is_darker_than_the_grass():
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	for index in GroundCover.SPECIES.size():
		assert_lt(
			ProceduralSwardSprite.LEAF_COLORS[index].v,
			grassland.v,
			"%s is not darker than the grass" % GroundCover.SPECIES[index]
		)


## A rosette whose leaves all radiate at exactly equal angles and equal lengths
## reads as a snowflake, which is the other half of what the screenshot showed.
## Leaf tips must land at genuinely different distances from the centre.
func test_a_rosette_is_not_radially_symmetric():
	for index in GroundCover.SPECIES.size():
		var image := ProceduralSwardSprite.new().generate_image(index, 13)
		var centre := Vector2(ProceduralSwardSprite.SIZE) * 0.5
		var radii := {}
		for pixel in _opaque_pixels(image):
			radii[int(roundf(Vector2(pixel).distance_to(centre)))] = true
		assert_gt(
			radii.size(), 3, "%s reads as one perfect ring" % GroundCover.SPECIES[index]
		)
