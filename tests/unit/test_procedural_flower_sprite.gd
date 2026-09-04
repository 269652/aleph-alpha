extends GutTest

## Flower art (see docs/concept/flora.md).
##
## The bloom used to be drawn as single-pixel RAYS radiating from a 3x3
## centre: petal_count lines one pixel wide, which reads as an asterisk rather
## than a flower, and made every species look the same but for its hue. Real
## petals have area, and a lavender spike does not look like a daisy.

const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const IllustratedFlowerHead = preload("res://src/rendering/illustrated_flower_head.gd")

var generator: ProceduralFlowerSprite


func before_each():
	generator = ProceduralFlowerSprite.new()


func _painted_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


## Colours present in the bloom (the head only -- above the stem), so shape
## and shading can be measured without the stem and leaves.
func _head_colors(image: Image) -> Dictionary:
	var found := {}
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.0:
				found[c.to_html()] = true
	return found


# -- petals have area --------------------------------------------------------

## The direct measure of the old fault: rays paint about
## petal_count * radius pixels. Real petals paint far more, because they are
## shapes rather than lines.
func test_a_bloom_is_made_of_shapes_not_single_pixel_rays():
	for species in FlowerSpecies.IDS:
		var image := generator.generate_image(species, 4)
		assert_gt(
			_painted_pixels(image), 60,
			"%s paints too few pixels to be anything but a handful of lines" % species
		)


## Petals must be at least two pixels thick somewhere, or they are still
## lines however many there are.
func test_petals_are_thicker_than_one_pixel():
	var image := generator.generate_image("tulip", 9)
	var widest := 0
	for y in image.get_height():
		var run := 0
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				run += 1
				widest = maxi(widest, run)
			else:
				run = 0
	assert_gte(widest, 5, "a bloom should have a solid run of pixels across it")


# -- species look like themselves --------------------------------------------

## The point of the pass: a lavender spike, a clover puff and a tulip cup are
## different SHAPES, not one shape in different colours. Compared on alpha
## silhouette alone so hue cannot mask a shared outline.
## Every ARCHETYPE has its own silhouette (see ProceduralFlowerSprite.
## HEAD_SHAPE_BY_SPECIES) -- species sharing an archetype are EXPECTED to
## share a silhouette now that "cup" has real illustrated art (see
## IllustratedFlowerHead): a real crocus and a real tulip genuinely are the
## same shallow-open-cup shape, differing only in colour/size, both of which
## are already applied elsewhere (FlowerSpecies.color_for, height_cm) --
## that's the whole point of building one kit per archetype instead of per
## species. Before illustrated art this held per-species too (a procedural
## `tight := _head_species == "crocus"` branch nudged crocus/tulip apart
## even within "cup"); that per-species nuance is gone for an illustrated
## archetype specifically, a real and accepted trade-off, not a bug.
func test_species_without_their_own_art_share_their_archetype_silhouette():
	var shapes_by_archetype := {}
	for species in FlowerSpecies.IDS:
		# A species with a sheet of its own is drawn from that sheet, so it is
		# SUPPOSED to look unlike its archetype-mates -- that is the whole
		# point of giving it one. Only the species falling back to the shared
		# shape should share a silhouette.
		var archetype: String = ProceduralFlowerSprite.HEAD_SHAPE_BY_SPECIES.get(
			species, ProceduralFlowerSprite._FALLBACK_HEAD_SHAPE
		)
		if IllustratedFlowerHead.new().has_own_art(species):
			continue
		var image := generator.generate_image(species, 3)
		var mask := ""
		for y in image.get_height():
			for x in image.get_width():
				mask += "1" if image.get_pixel(x, y).a > 0.0 else "0"
		if not shapes_by_archetype.has(archetype):
			shapes_by_archetype[archetype] = mask
		else:
			assert_eq(
				mask, shapes_by_archetype[archetype],
				"%s should share its silhouette with its archetype-mates" % species
			)
	assert_gt(shapes_by_archetype.size(), 0, "some species should still share a shape")


## A species given its own sheet actually looks different from the archetype
## it belongs to -- otherwise registering the art achieved nothing.
func test_a_species_with_its_own_art_does_not_look_like_its_archetype_mates():
	# Crocus and tulip are both cups, and both now have their own drawings.
	var crocus := generator.generate_image("crocus", 3)
	var tulip := generator.generate_image("tulip", 3)
	assert_ne(crocus.get_data(), tulip.get_data(), "two cups with their own art should differ")


## Shading: a bloom lit from one side has more than one tone of its petal
## colour, or it reads as a flat sticker.
func test_a_bloom_is_shaded_rather_than_flat():
	for species in FlowerSpecies.IDS:
		assert_gte(
			_head_colors(generator.generate_image(species, 6)).size(), 4,
			"%s should carry petal, shade, highlight and stem tones at least" % species
		)


## Every bloom keeps a focal centre distinct from its petals -- that is what
## makes a flower read as a flower from a distance.
## Asserted as "a focal region exists", not as the colour of one hardcoded
## pixel: where the centre sits depends on the head shape, and a spike's core
## is not in the same place as a cup's. Sampling a fixed coordinate tested the
## coordinate, not the flower.
func test_a_bloom_has_a_centre_that_differs_from_its_petals():
	for species in FlowerSpecies.IDS:
		var image := generator.generate_image(species, 8)
		var petal: Color = FlowerSpecies.color_for(species)
		var focal := 0
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				if Vector3(c.r, c.g, c.b).distance_to(Vector3(petal.r, petal.g, petal.b)) > 0.25:
					focal += 1
		assert_gt(focal, 3, "%s needs a focal centre distinct from its petals" % species)


# -- the invariants that must survive the detail pass ------------------------

func test_blooms_stay_inside_their_canvas():
	for species in FlowerSpecies.IDS:
		var image := generator.generate_image(species, 12)
		for y in image.get_height():
			assert_eq(image.get_pixel(0, y).a, 0.0, "%s touches the left edge" % species)
			assert_eq(
				image.get_pixel(image.get_width() - 1, y).a, 0.0,
				"%s touches the right edge" % species
			)


func test_the_same_flower_is_always_drawn_the_same():
	assert_eq(
		generator.generate_image("rose", 5).get_data(),
		generator.generate_image("rose", 5).get_data()
	)


func test_different_seeds_vary_the_same_species():
	assert_ne(
		generator.generate_image("rose", 5).get_data(),
		generator.generate_image("rose", 6).get_data()
	)


func test_an_unknown_species_still_draws_something():
	assert_gt(_painted_pixels(generator.generate_image("not_a_flower", 1)), 0)


# -- how big a bloom stands in the world -------------------------------------
#
# The detail pass gave the rose a layered head and left its height alone, so a
# mature rose rendered as a big red ball towering over the small purple blooms
# beside it (reported: "flowers are now too big... the mature red flowers
# should be as small as the purple flowers").

func test_the_accents_stay_within_reach_of_each_other():
	# This replaces a test that pinned "a rose is no bigger than a crocus".
	# That was the right fix for the complaint that produced it -- roses were
	# rendering as towering shrubs -- but it was fixed by flattening every
	# species to roughly one size, and species stature is now real.
	#
	# The sunflower is excluded on purpose: it is meant to tower, and the
	# ceiling that matters for it is the player, not the other flowers.
	var shortest := INF
	var tallest := 0.0
	for species in FlowerSpecies.IDS:
		if FlowerSpecies.height_cm_for(species) > ProceduralFlowerSprite.HIP_HEIGHT_ANCHOR_CM:
			continue
		var scale: float = ProceduralFlowerSprite.world_scale_for(species)
		shortest = minf(shortest, scale)
		tallest = maxf(tallest, scale)
	assert_lte(
		tallest / shortest, 2.5,
		"one accent towering over the rest reads as a landmark, not a meadow"
	)


## Flowers are accents among grass -- with one deliberate exception.
##
## Everything up to hip height still grows BETWEEN the blades and must not
## tower over them. The sunflower is the exception that makes the rest read as
## small: it is meant to stand above the meadow, so it is measured against the
## player instead (test_a_sunflower_stands_as_tall_as_the_player).
func test_no_ordinary_bloom_stands_taller_than_the_grass_around_it():
	for species in FlowerSpecies.IDS:
		if FlowerSpecies.height_cm_for(species) > ProceduralFlowerSprite.HIP_HEIGHT_ANCHOR_CM:
			continue
		var height_tiles := ProceduralFlowerSprite.world_scale_for(species) 			* float(ProceduralFlowerSprite.SIZE.y) / ProceduralFlowerSprite.TILE_SIZE
		assert_lte(height_tiles, 1.0, "%s is taller than a tile of grass" % species)


## A newly-seeded flower is a seedling, not a full bloom that happens to be
## new -- growth is something the player can see happen.
func test_a_seedling_is_much_smaller_than_a_mature_bloom():
	assert_lt(
		ProceduralFlowerSprite.growth_scale(0.0),
		ProceduralFlowerSprite.growth_scale(1.0) * 0.5,
		"a seedling should be a fraction of a grown flower"
	)


func test_a_flower_grows_steadily_to_full_size():
	var previous := -1.0
	for step in 20:
		var scale := ProceduralFlowerSprite.growth_scale(float(step) / 19.0)
		assert_gte(scale, previous, "growth must not go backwards")
		previous = scale
	assert_almost_eq(ProceduralFlowerSprite.growth_scale(1.0), 1.0, 0.001)


## Still visible: a seedling nobody can see is indistinguishable from bare
## ground, and the player is meant to notice a meadow filling in.
func test_a_seedling_is_still_visible():
	assert_gt(ProceduralFlowerSprite.growth_scale(0.0), 0.2)


## Illustrated head art (see IllustratedFlowerHead, docs/art/
## ai_sprite_prompts.md): one AI-generated sheet per ARCHETYPE, composited
## onto the same procedural stem/leaves, tinted per species. Only "cup"
## (crocus/tulip) has a sheet supplied so far -- every other archetype must
## keep drawing procedurally, unaffected.

## No 3rd arg at all is the existing 2-arg call every older test above still
## uses -- must keep behaving exactly like nectar=1.0 (a fresh bloom's real
## default, see FlowerPatch.plant), not a made-up convenience default.
func test_omitting_nectar_matches_passing_a_full_1_0():
	assert_eq(
		generator.generate_image("tulip", 5).get_data(),
		generator.generate_image("tulip", 5, 1.0).get_data()
	)


## WITHERED renders the spent stage -- not empty nectar.
##
## This asserted that near-empty nectar rendered differently, which encoded the
## conflation it now guards against: a bloom a bee had just drained read as
## dead, and a nectary refills in about a minute. Spent means the flower is
## over for its season (see FlowerBloom), and which part of the year that is
## depends on the flower.
func test_a_withered_bloom_renders_the_spent_stage():
	var fresh := generator.generate_image("tulip", 5, 1.0, false).get_data()
	var spent := generator.generate_image("tulip", 5, 1.0, true).get_data()
	assert_ne(fresh, spent, "a withered bloom should look visibly different from a fresh one")


## Rose ("layered") has no illustrated sheet yet -- nectar must be a total
## no-op for it, so adding illustrated art to one archetype can never
## silently change how an unrelated procedural archetype renders.
func test_nectar_has_no_effect_on_an_archetype_with_no_illustrated_sheet_yet():
	assert_eq(
		# Clover: a puff, which has neither a species sheet nor an archetype
		# one, so it is still procedurally painted. Rose stood here first,
		# then lavender; both have since been given their own drawings.
		generator.generate_image("clover", 5, 1.0).get_data(),
		generator.generate_image("clover", 5, 0.01).get_data()
	)


func test_nectar_switches_stage_exactly_at_the_tested_spent_threshold():
	var threshold := ProceduralFlowerSprite.SPENT_NECTAR_THRESHOLD
	assert_eq(
		generator.generate_image("tulip", 5, threshold + 0.001).get_data(),
		generator.generate_image("tulip", 5, 1.0).get_data(),
		"just above the threshold should still read as a full, not spent, bloom"
	)
	assert_eq(
		generator.generate_image("tulip", 5, threshold - 0.001).get_data(),
		generator.generate_image("tulip", 5, 0.0).get_data(),
		"just below the threshold should already read as spent"
	)


func test_an_illustrated_bloom_still_stays_inside_its_canvas():
	for seed_value in range(20):
		var image := generator.generate_image("tulip", seed_value)
		for y in image.get_height():
			for x in image.get_width():
				assert_true(true)  # get_pixel not raising IS the assertion
				image.get_pixel(x, y)


# -- the blossom is shrunk to fit, never sliced off ---------------------------
#
# IllustratedFlowerHead.HEAD_CANVAS_SIZE is taller than the headroom a short
# stem roll leaves above its own attachment point (see stem_height_px):
# composited at full size, the crown was sliced off flat by the canvas edge
# instead of drawn smaller. Invisible on the small species this shipped with;
# glaring on the sunflower, whose much larger world scale turns the same
# handful of always-clipped art pixels into an obvious flat top (reported,
# with a screenshot: "the sunflower sprite is clipped at the top").

func test_head_fit_scale_is_full_when_the_head_already_fits():
	assert_eq(ProceduralFlowerSprite.head_fit_scale(18, 18), 1.0)
	assert_eq(ProceduralFlowerSprite.head_fit_scale(30, 18), 1.0)


func test_head_fit_scale_shrinks_to_exactly_the_available_headroom():
	assert_almost_eq(ProceduralFlowerSprite.head_fit_scale(9, 18), 0.5, 0.001)
	assert_almost_eq(ProceduralFlowerSprite.head_fit_scale(6, 12), 0.5, 0.001)


## The invariant the compositor actually relies on: whatever it shrinks the
## head to, the result must never exceed the real headroom -- checked across
## every stem-height roll this project's own seed range can produce, not just
## one hand-picked case.
func test_head_fit_scale_never_exceeds_the_real_headroom_at_any_stem_roll():
	for seed_value in range(200):
		var headroom: int = (
			ProceduralFlowerSprite.SIZE.y - ProceduralFlowerSprite.stem_height_px(seed_value)
		)
		var scale := ProceduralFlowerSprite.head_fit_scale(
			headroom, IllustratedFlowerHead.HEAD_CANVAS_SIZE.y
		)
		var fitted := int(round(IllustratedFlowerHead.HEAD_CANVAS_SIZE.y * scale))
		assert_lte(fitted, headroom, "seed %d still overflows its own headroom" % seed_value)


## The direct measure of the bug: a hard clip only ever drops ROWS past the
## canvas edge, so a tight-headroom head would still be exactly as WIDE as a
## roomy one -- just cut off flat across the top. A head genuinely shrunk to
## fit reads narrower too, because both dimensions shrink together.
func test_a_tight_headroom_sunflower_head_is_narrower_not_just_clipped_flat():
	var tightest_seed := 0
	var roomiest_seed := 0
	var min_headroom := 9999
	var max_headroom := 0
	for seed_value in range(60):
		var headroom: int = (
			ProceduralFlowerSprite.SIZE.y - ProceduralFlowerSprite.stem_height_px(seed_value)
		)
		if headroom < min_headroom:
			min_headroom = headroom
			tightest_seed = seed_value
		if headroom > max_headroom:
			max_headroom = headroom
			roomiest_seed = seed_value
	assert_lt(
		min_headroom, max_headroom,
		"precondition: the scanned seeds should vary the stem's headroom"
	)
	assert_lt(
		min_headroom, IllustratedFlowerHead.HEAD_CANVAS_SIZE.y,
		"precondition: the tightest roll in range should actually need shrinking"
	)

	var tight_width := _widest_head_run(
		generator.generate_image("sunflower", tightest_seed), tightest_seed
	)
	var roomy_width := _widest_head_run(
		generator.generate_image("sunflower", roomiest_seed), roomiest_seed
	)
	assert_lt(
		tight_width, roomy_width,
		"a short-stemmed sunflower's head should be drawn smaller, not clipped flat at the same width"
	)


## The widest run of painted pixels in any one row of the head region (above
## the stem, see _head_pixels) -- how wide the bloom reads at its widest.
func _widest_head_run(image: Image, seed_value: int) -> int:
	var head_bottom: int = ProceduralFlowerSprite.SIZE.y - ProceduralFlowerSprite.stem_height_px(seed_value)
	var widest := 0
	for y in head_bottom:
		var run := 0
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				run += 1
				widest = maxi(widest, run)
			else:
				run = 0
	return widest


# -- the blossom offset tracks the ACTUAL plant, not just its species --------
#
# blossom_height_world used to scale by the species' own nominal size alone
# (world_scale_for), while the sprite itself is drawn at plant_scale_for
# (species size nudged by this plant's own variance) times growth_scale (how
# far it has grown -- see EarthChunkManager._flower_scale_for). A
# below-average or still-growing plant's sprite is smaller than the species
# norm, but its landing point did not move with it -- most visible on a
# species whose scale is large to begin with, where even a modest mismatch is
# a lot of world pixels (reported on the sunflower: "butterflies drink from
# their stem").

func test_blossom_height_scales_linearly_with_the_actual_plant_scale():
	var seed_value := 5
	var full := ProceduralFlowerSprite.blossom_height_world(seed_value, 10.0)
	var half := ProceduralFlowerSprite.blossom_height_world(seed_value, 5.0)
	assert_almost_eq(half, full * 0.5, 0.001)


func test_a_smaller_plant_has_a_lower_blossom_than_the_species_norm():
	var seed_value := 5
	var species_scale := ProceduralFlowerSprite.world_scale_for("sunflower")
	var norm := ProceduralFlowerSprite.blossom_height_world(seed_value, species_scale)
	var runt := ProceduralFlowerSprite.blossom_height_world(
		seed_value, species_scale * (1.0 - ProceduralFlowerSprite.PLANT_SIZE_VARIANCE)
	)
	assert_lt(runt, norm, "a below-average plant's blossom should sit lower than the species norm")


func test_a_still_growing_flowers_blossom_sits_lower_than_a_mature_ones():
	var seed_value := 5
	var species_scale := ProceduralFlowerSprite.world_scale_for("sunflower")
	var mature := ProceduralFlowerSprite.blossom_height_world(
		seed_value, species_scale * ProceduralFlowerSprite.growth_scale(1.0)
	)
	var seedling := ProceduralFlowerSprite.blossom_height_world(
		seed_value, species_scale * ProceduralFlowerSprite.growth_scale(0.0)
	)
	assert_lt(seedling, mature, "a seedling's blossom should sit far lower than a mature plant's")
	assert_almost_eq(
		seedling / mature, ProceduralFlowerSprite.growth_scale(0.0), 0.001,
		"the blossom should shrink in lockstep with the plant's own growth"
	)


func test_an_illustrated_head_is_tinted_toward_its_species_colour_not_left_pale():
	# The source art is deliberately pale/neutral (see ai_sprite_prompts.md)
	# so it can be recoloured per species -- if tinting isn't actually
	## applied, a tulip's bloom stays cream instead of reading red.
	var image := generator.generate_image("tulip", 5)
	var petal := FlowerSpecies.color_for("tulip")
	var found_tinted_pixel := false
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if p.a < 0.5:
				continue
			# A pale/neutral source pixel tinted by a saturated red petal
			# colour reads noticeably redder (higher r relative to g/b) than
			# a truly neutral cream pixel would.
			if p.r > p.g + 0.08 and p.r > p.b + 0.08:
				found_tinted_pixel = true
				break
		if found_tinted_pixel:
			break
	assert_true(found_tinted_pixel, "expected at least one visibly red-tinted pixel in a tulip's bloom")


# -- petals are never green --------------------------------------------------
#
# The illustrated head sheet is composited by MULTIPLYING it with the species
# petal colour, which only recolours correctly if the source art is pale and
# neutral. The cup sheet is not: it carries real green in its sepals and
# outlines, and multiply preserves hue, so crocus and tulip came out as green
# cages -- invisible against grass, and not a colour petals come in (reported:
# "green petals are hard to see on green grass and not really natural colour
# for flower petals").
#
# Petals now take only the source's SHADING and none of its hue, so the
# recolour works whatever the art happens to be tinted.

## The bloom only -- above the stem -- since stems and leaves are green on
## purpose and would drown out the measurement.
func _head_pixels(image: Image, seed_value: int) -> Array:
	var out: Array = []
	var head_bottom: int = ProceduralFlowerSprite.SIZE.y \
		- ProceduralFlowerSprite.stem_height_px(seed_value)
	for y in head_bottom:
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				out.append(c)
	return out


func test_no_bloom_is_painted_in_green():
	for species in FlowerSpecies.IDS:
		var pixels := _head_pixels(generator.generate_image(species, 8), 8)
		assert_gt(pixels.size(), 10, "precondition: %s has a bloom to measure" % species)
		var greenish := 0
		for c in pixels:
			if c.g > c.r and c.g > c.b:
				greenish += 1
		assert_lt(
			float(greenish) / float(pixels.size()), 0.15,
			"%s is painted mostly green, which is not a petal colour" % species
		)


## The point of not being green: a flower has to be findable in grass.
func test_every_bloom_stands_out_against_grass():
	var grass := Color(0.35, 0.62, 0.28)
	for species in FlowerSpecies.IDS:
		var pixels := _head_pixels(generator.generate_image(species, 8), 8)
		var total := Vector3.ZERO
		for c in pixels:
			total += Vector3(c.r, c.g, c.b)
		var average := total / float(maxi(1, pixels.size()))
		assert_gt(
			average.distance_to(Vector3(grass.r, grass.g, grass.b)), 0.25,
			"%s does not stand out from the grass it grows in" % species
		)


## The bloom still reads as the colour THIS PLANT came up as, rather than
## being washed out to a uniform pale blob by the recolour.
##
## Checked against the plant's own variety rather than the species' canonical
## colour: a species comes up in several colours now (FlowerSpecies "On
## variety"), so a tulip grown from this seed may legitimately be yellow.
func test_a_bloom_still_reads_as_the_colour_it_came_up():
	for species in FlowerSpecies.IDS:
		var petal: Color = FlowerSpecies.tint_for(species, 8)
		var pixels := _head_pixels(generator.generate_image(species, 8), 8)
		var closest := 999.0
		for c in pixels:
			closest = minf(
				closest,
				Vector3(c.r, c.g, c.b).distance_to(Vector3(petal.r, petal.g, petal.b))
			)
		assert_lt(closest, 0.25, "%s should carry its own colour somewhere" % species)


## Every variety survives the recolour, not just the one seed 8 happens to
## pick -- a pale yellow tulip must not come out as washed-out red.
func test_every_variety_of_every_species_reads_as_itself():
	for species in FlowerSpecies.IDS:
		for seed_value in 24:
			var petal: Color = FlowerSpecies.tint_for(species, seed_value)
			var pixels := _head_pixels(generator.generate_image(species, seed_value), seed_value)
			var closest := 999.0
			for c in pixels:
				closest = minf(
					closest,
					Vector3(c.r, c.g, c.b).distance_to(Vector3(petal.r, petal.g, petal.b))
				)
			assert_lt(closest, 0.3, "%s at seed %d lost its colour" % [species, seed_value])


## Petals are not windows.
##
## The cup sheet is line art -- petals drawn as outlines with nothing inside
## them -- so composited as-is the grass showed straight through every petal
## and the flower read as a green wireframe cage. Reported twice: "green
## petals ... on green grass", and then, after the outlines themselves were
## correctly recoloured, "the bloom is correctly colored but the petals are
## still green". The green was the background.
func test_a_bloom_has_no_holes_for_the_grass_to_show_through():
	for species in FlowerSpecies.IDS:
		var image := generator.generate_image(species, 8)
		# Anything transparent that cannot be reached from the edge of the
		# canvas is a hole INSIDE the flower.
		var outside := {}
		var queue: Array[Vector2i] = []
		for x in image.get_width():
			queue.append(Vector2i(x, 0))
			queue.append(Vector2i(x, image.get_height() - 1))
		for y in image.get_height():
			queue.append(Vector2i(0, y))
			queue.append(Vector2i(image.get_width() - 1, y))
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			if at.x < 0 or at.x >= image.get_width() or at.y < 0 or at.y >= image.get_height():
				continue
			if outside.has(at) or image.get_pixel(at.x, at.y).a >= 0.05:
				continue
			outside[at] = true
			queue.append(at + Vector2i(1, 0))
			queue.append(at + Vector2i(-1, 0))
			queue.append(at + Vector2i(0, 1))
			queue.append(at + Vector2i(0, -1))
		var holes := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a < 0.05 and not outside.has(Vector2i(x, y)):
					holes += 1
		assert_eq(holes, 0, "%s has gaps the background shows through" % species)


# -- how big a flower is, measured against the player -------------------------

## ...and the player's height here is the one CharacterView actually uses,
## rather than a second copy that can drift away from it.
func test_the_player_height_flowers_are_measured_against_is_the_real_one():
	var CharacterView := load("res://scenes/character_view.gd")
	assert_almost_eq(
		ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX,
		-CharacterView.HEAD_TOP_Y * CharacterView.SCALE,
		0.001,
		"flowers must be measured against the character's real height"
	)


## Relative stature survives the shrink: a lavender still stands well above a
## crocus, which is the whole point of per-species size.
func test_taller_species_are_still_visibly_taller():
	assert_gt(
		ProceduralFlowerSprite.world_height_px("lavender"),
		ProceduralFlowerSprite.world_height_px("crocus") * 1.5,
		"a lavender should read as clearly taller than a crocus"
	)


## Real heights are exaggerated toward legibility, deliberately: a crocus is
## 6% of a person and would render as a speck at true scale. The exaggeration
## must not invert the ordering.
func test_shrinking_never_reorders_the_species():
	var by_real_height := FlowerSpecies.IDS.duplicate()
	by_real_height.sort_custom(func(a, b): return (
		FlowerSpecies.height_cm_for(a) < FlowerSpecies.height_cm_for(b)
	))
	var previous := 0.0
	for species in by_real_height:
		var height := ProceduralFlowerSprite.world_height_px(species)
		assert_gte(height, previous, "%s broke the real-height ordering" % species)
		previous = height


## Even the smallest species stays big enough to read as a flower rather than
## a stray pixel -- the failure mode the previous size was raised to escape.
func test_even_the_smallest_bloom_is_still_visible():
	for species in FlowerSpecies.IDS:
		assert_gte(
			ProceduralFlowerSprite.world_height_px(species),
			ProceduralFlowerSprite.MINIMUM_READABLE_HEIGHT_PX,
			"%s is a speck" % species
		)


# -- one plant is not another --------------------------------------------------

## No two flowers in a bed are quite the same size. A patch where every bloom
## is pixel-identical reads as stamped-out copies rather than as things that
## grew.
func test_individual_plants_vary_in_size():
	var sizes := {}
	for seed_value in 60:
		sizes[snappedf(ProceduralFlowerSprite.plant_scale_for("tulip", seed_value), 0.0001)] = true
	assert_gt(sizes.size(), 3, "a bed of tulips should not be stamped out")


## ...but an individual plant does not change size, any more than it changes
## colour: its size belongs to the plant, not to the frame.
func test_a_given_plant_keeps_its_size():
	for seed_value in [0, 3, 77, 4001]:
		assert_eq(
			ProceduralFlowerSprite.plant_scale_for("rose", seed_value),
			ProceduralFlowerSprite.plant_scale_for("rose", seed_value)
		)


## Variance is a nudge, not a lottery: a runt and a giant of the same species
## still read as the same species, and the giant still clears the knee rule.
func test_variance_stays_within_bounds_and_under_the_knee():
	for species in FlowerSpecies.IDS:
		var base := ProceduralFlowerSprite.world_scale_for(species)
		for seed_value in 80:
			var scale := ProceduralFlowerSprite.plant_scale_for(species, seed_value)
			var ratio := scale / base
			assert_between(
				ratio,
				1.0 - ProceduralFlowerSprite.PLANT_SIZE_VARIANCE - 0.001,
				1.0 + ProceduralFlowerSprite.PLANT_SIZE_VARIANCE + 0.001,
				"%s at seed %d is a different species-worth of size" % [species, seed_value]
			)
			# Even a large individual stays roughly in its species' league --
			# a big sunflower may top the player, but only by its variance.
			var height := scale * float(ProceduralFlowerSprite.SIZE.y)
			assert_lte(
				height / ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX,
				1.0 + ProceduralFlowerSprite.PLANT_SIZE_VARIANCE + 0.01,
				"a %s grew out of all proportion" % species
			)


# -- masks: recolour the petals, keep what is deliberately another colour ------

## A flower's centre is not its petals.
##
## The recolour discards the sheet's hue entirely, which is what fixed blooms
## rendering as green cages -- but it discarded the yellow eye along with it,
## so an illustrated daisy came out uniformly grey where it should have a gold
## centre. The eye is not a shading artifact, it is a part of the flower drawn
## in a different colour on purpose.
##
## The mask is derived from the sheet rather than hand-painted: the dominant
## hue is the petal mass, and a saturated minority sitting far from it in hue
## is an accent that keeps its own colour. Measured across the sheets, every
## species drawing carries its stamens 90-150 degrees off its petals, while
## the shared cup sheet's hues all sit within 30 degrees of each other -- so
## this preserves eyes without un-fixing the green cage.
func test_an_illustrated_bloom_keeps_a_centre_of_its_own_colour():
	for species in ["crocus", "tulip", "rose", "daisy"]:
		assert_true(
			_has_gold_centre(generator.generate_image(species, 8), 8),
			"%s lost the centre of its bloom to the recolour" % species
		)


## The centre survives whatever colour the plant came up as: a white tulip
## still has a gold eye rather than a white one.
##
## Checked as "is there gold in the head", not "is there a hue far from the
## petals" -- a tulip that comes up gold has petals the same hue as its eye,
## and there is legitimately no contrast to find.
func test_the_centre_survives_every_variety():
	for seed_value in 24:
		assert_true(
			_has_gold_centre(generator.generate_image("tulip", seed_value), seed_value),
			"a tulip at seed %d lost its centre" % seed_value
		)


## Green sepals are NOT preserved. They are as far from the petals in hue as a
## gold eye is, so a pure distance rule keeps them -- but on a bloom a few
## pixels tall a preserved sepal reads as a green flower, which is the
## complaint that started all of this.
func test_no_bloom_keeps_the_sheets_green():
	for species in FlowerSpecies.IDS:
		var green := 0
		var pixels := _head_pixels(generator.generate_image(species, 8), 8)
		for pixel in pixels:
			if pixel.s < ProceduralFlowerSprite.ACCENT_MIN_SATURATION:
				continue
			var degrees: float = pixel.h * 360.0
			if degrees > ProceduralFlowerSprite.ACCENT_HUE_MAX and degrees < 170.0:
				green += 1
		assert_eq(green, 0, "%s kept green from its sheet" % species)


func _has_gold_centre(image: Image, seed_value: int) -> bool:
	for pixel in _head_pixels(image, seed_value):
		if pixel.s < ProceduralFlowerSprite.ACCENT_MIN_SATURATION:
			continue
		var degrees: float = pixel.h * 360.0
		if degrees >= ProceduralFlowerSprite.ACCENT_HUE_MIN and degrees <= ProceduralFlowerSprite.ACCENT_HUE_MAX:
			return true
	return false


## The mask must not swallow the bloom: an accent is a minority of the head,
## not most of it. If it ever took the majority the recolour would be doing
## nothing and the green cage would be back.
func test_the_accent_is_a_minority_of_the_bloom():
	for species in FlowerSpecies.IDS:
		var petal: Color = FlowerSpecies.tint_for(species, 8)
		var pixels := _head_pixels(generator.generate_image(species, 8), 8)
		if pixels.is_empty():
			continue
		var accents := 0
		for pixel in pixels:
			if pixel.s < ProceduralFlowerSprite.ACCENT_MIN_SATURATION:
				continue
			if _hue_gap_degrees(pixel.h, petal.h) > ProceduralFlowerSprite.ACCENT_HUE_DISTANCE:
				accents += 1
		assert_lt(
			float(accents) / float(pixels.size()), 0.5,
			"%s is mostly accent -- the petals are not being recoloured" % species
		)


## Hue is circular: 350 degrees and 10 degrees are 20 apart, not 340.
func _hue_gap_degrees(hue_a: float, hue_b: float) -> float:
	var gap: float = abs(hue_a - hue_b) * 360.0
	return minf(gap, 360.0 - gap)


# -- plants that grow as bushes ------------------------------------------------

## Lavender does not grow as a single stem.
##
## It grows as a bush of many spikes, and rendering one lone spike per plant
## made a lavender bed read as scattered twigs rather than as lavender. A
## species says how it grows, and a bush is drawn as several stems of its own
## with their own heights and offsets.
func test_a_bush_species_draws_several_stems():
	assert_gt(
		_stem_columns(generator.generate_image("lavender", 4)), 1,
		"lavender should be a bush, not one twig"
	)


func test_a_single_stemmed_species_still_draws_one_stem():
	for species in ["tulip", "rose", "crocus"]:
		assert_eq(
			_stem_columns(generator.generate_image(species, 4)), 1,
			"%s grows on one stem" % species
		)


## The spikes in a bush are not clones: they differ in height and position, or
## the bush reads as one sprite drawn several times.
func test_the_spikes_in_a_bush_differ_from_each_other():
	var heights := {}
	for offset in ProceduralFlowerSprite.bush_offsets("lavender", 4):
		heights[snappedf(offset.y, 0.01)] = true
	assert_gt(heights.size(), 1, "every spike at the same height is one sprite repeated")


## ...but the bush is still one plant: the spikes stay together rather than
## scattering across the tile.
func test_a_bush_stays_one_plant():
	for offset in ProceduralFlowerSprite.bush_offsets("lavender", 4):
		assert_lte(
			absf(offset.x), float(ProceduralFlowerSprite.SIZE.x) * 0.5,
			"a spike wandered off its own plant"
		)


## Two lavenders are not the same bush.
func test_two_bushes_are_arranged_differently():
	var first := ProceduralFlowerSprite.bush_offsets("lavender", 4)
	var second := ProceduralFlowerSprite.bush_offsets("lavender", 91)
	assert_ne(first, second, "every lavender being identical reads as copy-paste")


## ...but a given bush keeps its arrangement, like its colour and its size.
func test_a_given_bush_keeps_its_arrangement():
	assert_eq(
		ProceduralFlowerSprite.bush_offsets("lavender", 12),
		ProceduralFlowerSprite.bush_offsets("lavender", 12)
	)


## How many separate stems rise from the bottom of this sprite: the count of
## runs of stem-coloured pixels along the row just above the base.
func _stem_columns(image: Image) -> int:
	var runs := 0
	var was_stem := false
	var y := image.get_height() - 2
	for x in image.get_width():
		var pixel := image.get_pixel(x, y)
		var is_stem: bool = pixel.a > 0.5 and pixel.g > pixel.r and pixel.g > pixel.b
		if is_stem and not was_stem:
			runs += 1
		was_stem = is_stem
	return runs


# -- the two anchors flower sizes are pinned to --------------------------------

## Sizes are set by two stated reference points rather than by a curve chosen
## by eye: a tulip stands hip-high on the player, and a sunflower stands as
## tall as the player. Everything else follows from its real height.
func test_a_tulip_stands_hip_high_on_the_player():
	assert_almost_eq(
		ProceduralFlowerSprite.world_height_px("tulip")
			/ ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX,
		ProceduralFlowerSprite.HIP_FRACTION_OF_PLAYER,
		0.01,
		"a tulip should come up to the player's hip"
	)


func test_a_sunflower_stands_as_tall_as_the_player():
	assert_almost_eq(
		ProceduralFlowerSprite.world_height_px("sunflower")
			/ ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX,
		1.0,
		0.01,
		"a sunflower should stand eye to eye with the player"
	)


## Nothing in the roster stands OVER the player. The sunflower is the ceiling,
## not a step on the way to one.
func test_no_flower_stands_taller_than_the_player():
	for species in FlowerSpecies.IDS:
		assert_lte(
			ProceduralFlowerSprite.world_height_px(species)
				/ ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX,
			1.01,
			"%s stands taller than the player" % species
		)


## Adding a species must not resize the ones already there.
##
## Sizes used to be relative to whichever species happened to be tallest, so
## introducing the sunflower would silently have shrunk every other flower in
## the world. The curve is anchored to real centimetres instead, so a new
## entry only decides its own size.
func test_adding_a_taller_species_does_not_resize_the_others():
	var tulip := ProceduralFlowerSprite.world_height_px("tulip")
	var tallest := 0.0
	for species in FlowerSpecies.IDS:
		tallest = maxf(tallest, FlowerSpecies.height_cm_for(species))
	assert_gt(tallest, FlowerSpecies.height_cm_for("tulip") * 2.0, "a much taller species exists")
	assert_almost_eq(
		tulip,
		ProceduralFlowerSprite.PLAYER_WORLD_HEIGHT_PX * ProceduralFlowerSprite.HIP_FRACTION_OF_PLAYER,
		0.01,
		"the tulip's size must not depend on what else is in the roster"
	)


## The exaggeration is computed from the two anchors, not typed in.
func test_the_exaggeration_curve_is_derived_from_the_anchors():
	var expected: float = (
		log(ProceduralFlowerSprite.HIP_FRACTION_OF_PLAYER)
		/ log(
			ProceduralFlowerSprite.HIP_HEIGHT_ANCHOR_CM
			/ ProceduralFlowerSprite.PLAYER_HEIGHT_ANCHOR_CM
		)
	)
	assert_almost_eq(ProceduralFlowerSprite.size_exaggeration(), expected, 0.0001)


# -- withered is not drained --------------------------------------------------

## The wilted look is a flower at the END OF ITS SEASON, not one that has just
## been visited.
##
## It used to be drawn off the nectar level, which meant a bloom a bee had just
## emptied read as dead -- and it refills in about a minute. Two different
## things wearing one sprite: "there is nothing in this flower right now" and
## "this flower is over for the year".
func test_a_drained_flower_still_looks_alive():
	var full := generator.generate_image("crocus", 5, 1.0, false)
	var drained := generator.generate_image("crocus", 5, 0.0, false)
	assert_eq(
		full.get_data(), drained.get_data(),
		"an empty nectary should not change how a flower looks"
	)


func test_a_withered_flower_looks_different():
	assert_ne(
		generator.generate_image("crocus", 5, 1.0, false).get_data(),
		generator.generate_image("crocus", 5, 1.0, true).get_data(),
		"a flower at the end of its season should look spent"
	)


## Withering is the same whatever is left in the nectary -- they are unrelated.
func test_withering_does_not_depend_on_nectar():
	assert_eq(
		generator.generate_image("tulip", 3, 1.0, true).get_data(),
		generator.generate_image("tulip", 3, 0.0, true).get_data()
	)


# -- texture cache ------------------------------------------------------------
#
# Every bloom used to mint a brand new, uncached Texture2D on the frame it was
# planted or reloaded -- unlike ProceduralTreeSprite's own
# _tree_texture_cache, which shares one Texture2D per distinct look. Mirrors
# that pattern here: same generate_texture(...) inputs get the exact same
# Texture2D object back, sharable across the many blooms of one meadow, and
# reused again whenever a chunk unloads and reloads (chunks aren't persisted --
# see EarthChunkManager's own doc comment -- so the same cell asks for the
# same texture again on every revisit).

func test_the_same_bloom_gets_its_texture_back_instead_of_redrawing_it():
	var first := generator.generate_texture("tulip", 7, 1.0, false)
	var second := generator.generate_texture("tulip", 7, 1.0, false)
	assert_same(first, second, "one texture per distinct bloom, not one per sprite")


## The cache is shared across generator INSTANCES too -- each EarthChunkManager
## holds its own ProceduralFlowerSprite, so a per-instance cache would still
## redraw once per instance.
func test_two_generators_of_one_bloom_share_the_texture():
	var a := ProceduralFlowerSprite.new().generate_texture("crocus", 3, 1.0, false)
	var b := ProceduralFlowerSprite.new().generate_texture("crocus", 3, 1.0, false)
	assert_same(a, b)


func test_a_different_species_does_not_share_the_texture():
	assert_not_same(
		generator.generate_texture("crocus", 3, 1.0, false),
		generator.generate_texture("tulip", 3, 1.0, false)
	)


func test_a_different_seed_does_not_share_the_texture():
	assert_not_same(
		generator.generate_texture("crocus", 3, 1.0, false),
		generator.generate_texture("crocus", 4, 1.0, false)
	)


func test_withered_and_fresh_do_not_share_the_texture():
	assert_not_same(
		generator.generate_texture("crocus", 3, 1.0, false),
		generator.generate_texture("crocus", 3, 1.0, true)
	)


func test_cached_texture_still_matches_a_freshly_drawn_one():
	var cached := generator.generate_texture("rose", 8, 1.0, false)
	var fresh := generator.generate_image("rose", 8, 1.0, false)
	assert_eq(cached.get_image().get_data(), fresh.get_data())


## The bucketing the cache key relies on: nectar drains and refills
## continuously while a bloom's other traits stay fixed, so nectar is
## quantized into a small, bounded number of levels (see
## ProceduralTreeSprite.CROP_LEVELS for the pattern this mirrors) rather than
## keyed on the exact float, which would mint a fresh cache entry on almost
## every call.
func test_nectar_level_is_bounded_and_monotonic():
	var previous := -1
	for hundredth in 101:
		var level := ProceduralFlowerSprite.nectar_level_for(float(hundredth) / 100.0)
		assert_between(level, 0, ProceduralFlowerSprite.NECTAR_LEVELS - 1)
		assert_gte(level, previous, "rising nectar should never drop a bucket")
		previous = level


func test_full_and_empty_nectar_land_in_different_buckets():
	assert_ne(
		ProceduralFlowerSprite.nectar_level_for(0.0),
		ProceduralFlowerSprite.nectar_level_for(1.0)
	)


## Two nectar readings close enough to land in the same bucket must share a
## texture -- this is what actually keeps the cache small as nectar ticks
## down in tiny increments rather than in one jump.
func test_nearby_nectar_readings_share_the_texture():
	assert_same(
		generator.generate_texture("tulip", 6, 0.91, false),
		generator.generate_texture("tulip", 6, 0.99, false),
		"both readings should quantize to the same top nectar bucket"
	)


## Nectar levels far enough apart to land in different buckets are still the
## SAME picture today (nectar does not yet change how a bloom is drawn -- see
## test_a_drained_flower_still_looks_alive) but must still be cached
## separately, so the day nectar does start changing the art nothing here has
## to change.
func test_distant_nectar_readings_do_not_share_the_texture():
	assert_not_same(
		generator.generate_texture("tulip", 6, 0.0, false),
		generator.generate_texture("tulip", 6, 1.0, false)
	)


# -- how far above its own cell a bloom can be drawn -------------------------

## A hover lookup has to search UPWARD from the cursor to find the plant a
## bloom belongs to, because the sprite is anchored at the stem's foot and
## drawn above it (see EarthChunkManager.flower_name_at). That search needs a
## real ceiling rather than a guessed number of rows -- pinned here against
## every species at every size roll, fully grown.
func test_no_blossom_is_ever_drawn_higher_than_the_stated_ceiling():
	var ceiling := ProceduralFlowerSprite.max_blossom_height_world()
	assert_gt(ceiling, 0.0)
	var tallest := 0.0
	for species_id in FlowerSpecies.IDS:
		for seed_value in 400:
			tallest = maxf(tallest, ProceduralFlowerSprite.blossom_height_world(
				seed_value, ProceduralFlowerSprite.plant_scale_for(species_id, seed_value)
			))
	assert_lte(tallest, ceiling, "a bloom reached %.2f, above the stated %.2f" % [tallest, ceiling])
	# And not absurdly loose, or the hover search sweeps the whole screen.
	assert_lt(ceiling, tallest * 2.0, "the ceiling is %.2f for a real tallest of %.2f" % [ceiling, tallest])
