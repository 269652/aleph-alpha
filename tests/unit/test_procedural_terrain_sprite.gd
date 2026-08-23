extends GutTest

const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")

var generator := ProceduralTerrainSprite.new()


func test_generates_an_image_of_the_expected_size():
	var image := generator.generate_image("grassland", 0)
	assert_eq(image.get_width(), ProceduralTerrainSprite.SIZE)
	assert_eq(image.get_height(), ProceduralTerrainSprite.SIZE)


func test_image_is_fully_opaque():
	var image := generator.generate_image("grassland", 0)
	for y in [0, ProceduralTerrainSprite.SIZE - 1]:
		for x in [0, ProceduralTerrainSprite.SIZE - 1]:
			assert_eq(image.get_pixel(x, y).a, 1.0)


func test_is_deterministic_for_the_same_biome_and_variant_seed():
	var a := generator.generate_image("forest", 3)
	var b := generator.generate_image("forest", 3)
	assert_eq(a.get_data(), b.get_data())


func test_different_variant_seeds_produce_different_looking_tiles():
	var a := generator.generate_image("grassland", 0)
	var b := generator.generate_image("grassland", 1)
	assert_ne(a.get_data(), b.get_data())


func test_water_is_blue():
	var image := generator.generate_image("ocean", 0)
	var color := _average_color(image)
	assert_gt(color.b, color.r)
	assert_gt(color.b, color.g)


func test_stone_is_grey_and_desaturated():
	var image := generator.generate_image("mountain", 0)
	var color := _average_color(image)
	assert_almost_eq(color.r, color.g, 0.1)
	assert_almost_eq(color.g, color.b, 0.1)


func test_forest_is_darker_than_grassland():
	var forest_color := _average_color(generator.generate_image("forest", 0))
	var grassland_color := _average_color(generator.generate_image("grassland", 0))
	assert_lt(forest_color.g, grassland_color.g)


func test_grass_and_forest_both_read_as_green():
	for biome_name in ["grassland", "forest"]:
		var color := _average_color(generator.generate_image(biome_name, 0))
		assert_gt(color.g, color.r)
		assert_gt(color.g, color.b)


## Art-direction pass: base biome colors read as a saturated Pokemon-route
## palette, not muddy. Grassland in particular should be a vivid green.
func test_grassland_base_is_vividly_saturated():
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	assert_gt(grassland.s, 0.66, "grassland should read as a vivid saturated green")


func test_ocean_base_is_vividly_saturated_blue():
	var ocean: Color = ProceduralTerrainSprite.BASE_COLORS["ocean"]
	assert_gt(ocean.s, 0.66, "ocean should read as a vivid saturated blue")
	assert_gt(ocean.b, ocean.r)
	assert_gt(ocean.b, ocean.g)


func test_unknown_biome_falls_back_to_a_valid_image_rather_than_crashing():
	var image := generator.generate_image("not_a_real_biome", 0)
	assert_eq(image.get_width(), ProceduralTerrainSprite.SIZE)


func test_directional_blend_image_is_the_expected_size_and_opaque():
	var image := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 0)
	assert_eq(image.get_width(), ProceduralTerrainSprite.SIZE)
	assert_eq(image.get_height(), ProceduralTerrainSprite.SIZE)
	assert_eq(image.get_pixel(0, 0).a, 1.0)


func test_directional_blend_image_is_deterministic_for_the_same_inputs():
	var a := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 2)
	var b := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 2)
	assert_eq(a.get_data(), b.get_data())


## direction=(0,-1) means the far biome (grassland) neighbor is to the
## north -- so the top edge of this tile should read mostly grassland, and
## the bottom edge (away from that neighbor) mostly forest, not a uniform
## random mix of both everywhere.
func test_directional_blend_leans_toward_the_far_biome_on_that_edge():
	var image := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 0)
	var forest_base: Color = ProceduralTerrainSprite.BASE_COLORS["forest"]
	var grassland_base: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]

	var top_grassland_leaning := 0
	var bottom_forest_leaning := 0
	var size := ProceduralTerrainSprite.SIZE
	for x in size:
		var top_pixel := image.get_pixel(x, 0)
		if _rgb_distance(top_pixel, grassland_base) < _rgb_distance(top_pixel, forest_base):
			top_grassland_leaning += 1
		var bottom_pixel := image.get_pixel(x, size - 1)
		if _rgb_distance(bottom_pixel, forest_base) < _rgb_distance(bottom_pixel, grassland_base):
			bottom_forest_leaning += 1

	assert_gt(top_grassland_leaning, size / 2, "top edge (toward the grassland neighbor) should mostly read grassland")
	assert_gt(bottom_forest_leaning, size / 2, "bottom edge (away from the neighbor) should mostly read forest")


func test_multi_directional_blend_is_the_expected_size_opaque_and_deterministic():
	var a := generator.generate_multi_directional_blend_image("forest", "grassland", [Vector2i(0, -1), Vector2i(1, 0)], 2)
	var b := generator.generate_multi_directional_blend_image("forest", "grassland", [Vector2i(0, -1), Vector2i(1, 0)], 2)
	assert_eq(a.get_width(), ProceduralTerrainSprite.SIZE)
	assert_eq(a.get_height(), ProceduralTerrainSprite.SIZE)
	assert_eq(a.get_pixel(0, 0).a, 1.0)
	assert_eq(a.get_data(), b.get_data(), "same inputs should be deterministic")


func test_single_direction_blend_matches_the_multi_direction_form():
	# The single-direction convenience form must be exactly the one-element
	# multi-direction case, so old callers and the atlas stay consistent.
	var single := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 5)
	var multi := generator.generate_multi_directional_blend_image("forest", "grassland", [Vector2i(0, -1)], 5)
	assert_eq(single.get_data(), multi.get_data())


## Far neighbor to the north AND east -> the top edge and the right edge both
## read mostly far (grassland), while the far bottom-left corner (away from both
## neighbors) still reads near (forest). This is the corner-aware behavior the
## square-border fix depends on.
func test_multi_directional_blend_leans_toward_far_on_every_active_edge():
	var image := generator.generate_multi_directional_blend_image("forest", "grassland", [Vector2i(0, -1), Vector2i(1, 0)], 0)
	var forest_base: Color = ProceduralTerrainSprite.BASE_COLORS["forest"]
	var grassland_base: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	var size := ProceduralTerrainSprite.SIZE

	var top_grassland_leaning := 0
	var right_grassland_leaning := 0
	for i in size:
		var top_pixel := image.get_pixel(i, 0)
		if _rgb_distance(top_pixel, grassland_base) < _rgb_distance(top_pixel, forest_base):
			top_grassland_leaning += 1
		var right_pixel := image.get_pixel(size - 1, i)
		if _rgb_distance(right_pixel, grassland_base) < _rgb_distance(right_pixel, forest_base):
			right_grassland_leaning += 1

	assert_gt(top_grassland_leaning, size / 2, "top edge (toward the north neighbor) should mostly read grassland")
	assert_gt(right_grassland_leaning, size / 2, "right edge (toward the east neighbor) should mostly read grassland")

	# The corner opposite both neighbors stays true to the cell's own biome.
	var far_corner := image.get_pixel(0, size - 1)
	assert_lt(
		_rgb_distance(far_corner, forest_base), _rgb_distance(far_corner, grassland_base),
		"the corner away from both neighbors should still read forest"
	)


## The transition must read as a coherent gradient, not random static: for a
## north-facing blend, the far-leaning pixel count may never grow (beyond a
## small jitter allowance) as rows move away from the far edge. A per-pixel
## random dither violates this constantly; an ordered dither holds it -- but
## only once aggregated over one full Bayer cycle (4 rows, the matrix's own
## fixed period, independent of tile SIZE): within a cycle, individual rows
## can jump as different threshold-sharing columns (SIZE / 4 of them, one
## quartet of Bayer thresholds per row) flip together, so comparing raw
## per-row counts with a fixed pixel-count tolerance only worked by
## coincidence at the original 16px tile and stopped generalizing once SIZE
## grew (see docs/concept/art_resolution.md) -- block-level comparison is the
## actual guarantee ordered dithering provides.
func test_directional_blend_far_fraction_grows_monotonically_toward_the_far_edge():
	var image := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 0)
	var size := ProceduralTerrainSprite.SIZE
	const BAYER_CYCLE := 4
	var previous_total := size * BAYER_CYCLE + 1  # first block is nearest the far (north) neighbor
	var y := 0
	while y < size:
		var total := 0
		for row in range(y, mini(y + BAYER_CYCLE, size)):
			total += _far_leaning_count_in_row(image, row, "grassland", "forest")
		assert_true(
			total <= previous_total + BAYER_CYCLE,
			"rows %d..%d have %d far pixels total, more than the block above (%d) -- transition should fade, not flicker" % [y, y + BAYER_CYCLE - 1, total, previous_total]
		)
		previous_total = total
		y += BAYER_CYCLE


## The blend band must be tight: the quarter of the tile nearest its own
## (near) side stays essentially pure near-biome, and the quarter nearest the
## far neighbor essentially pure far-biome -- so a blend tile connects
## seamlessly to the plain tiles on both sides instead of speckling the whole
## cell.
func test_directional_blend_keeps_the_outer_quarters_essentially_pure():
	var image := generator.generate_directional_blend_image("forest", "grassland", Vector2i(0, -1), 0)
	var size := ProceduralTerrainSprite.SIZE
	var quarter := size / 4

	for y in quarter:  # rows nearest the far (north/grassland) neighbor
		var far_count := _far_leaning_count_in_row(image, y, "grassland", "forest")
		assert_gt(far_count, size - 2, "row %d near the far edge should be almost entirely grassland" % y)

	for y in range(size - quarter, size):  # rows nearest the near (forest) side
		var far_count := _far_leaning_count_in_row(image, y, "grassland", "forest")
		assert_lt(far_count, 2, "row %d near the near edge should be almost entirely forest" % y)


## Counts pixels in row `y` that read as far_biome rather than near_biome --
## compared against each biome's own REAL generated pixel at that exact
## position (seed 0, matching every caller here), not a flat BASE_COLORS
## reference. A blend tile now sources real per-pixel texture (grass
## blades, speckle, ...) rather than a flat color plus a synthesized
## speckle roll (see generate_multi_directional_blend_image_from's own doc
## comment) -- comparing against the real textured pixel is what "reads as
## that biome at this exact spot" actually means once the source is real
## art, not an approximation that happens to coincide with a flat color.
func _far_leaning_count_in_row(image: Image, y: int, far_biome: String, near_biome: String) -> int:
	var far_image := generator.generate_image(far_biome, 0)
	var near_image := generator.generate_image(near_biome, 0)
	var count := 0
	for x in ProceduralTerrainSprite.SIZE:
		var pixel := image.get_pixel(x, y)
		if _rgb_distance(pixel, far_image.get_pixel(x, y)) < _rgb_distance(pixel, near_image.get_pixel(x, y)):
			count += 1
	return count


# -- blending real source images together, not flat synthesized color -------
#
# TerrainRenderer needs a border between two ILLUSTRATED biomes to dither
# their real art together (reported: illustrated ground next to a flat
# procedural-looking border read as visibly inconsistent). The *_from
# variants take pre-resolved images (illustrated or procedural, caller's
# choice) instead of biome names, so the same dither-mask/wedge-mask math
# works regardless of where the pixels came from. No variant_seed: the
# mask itself is purely positional (Bayer dither / wedge geometry), and any
# per-pixel texture now comes from the real source images, not a
# synthesized speckle layered on top of a flat color.

func _solid_image(color: Color) -> Image:
	var image := Image.create(ProceduralTerrainSprite.SIZE, ProceduralTerrainSprite.SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func test_multi_directional_blend_from_sources_the_real_given_pixels():
	var near_image := _solid_image(Color(1, 0, 0, 1))
	var far_image := _solid_image(Color(0, 0, 1, 1))
	var image := generator.generate_multi_directional_blend_image_from(near_image, far_image, [Vector2i(0, -1)])
	assert_eq(image.get_width(), near_image.get_width())
	assert_eq(image.get_height(), near_image.get_height())

	var size := near_image.get_width()
	var top_far_leaning := 0
	var bottom_near_leaning := 0
	for x in size:
		var top_pixel := image.get_pixel(x, 0)
		if _rgb_distance(top_pixel, Color(0, 0, 1)) < _rgb_distance(top_pixel, Color(1, 0, 0)):
			top_far_leaning += 1
		var bottom_pixel := image.get_pixel(x, size - 1)
		if _rgb_distance(bottom_pixel, Color(1, 0, 0)) < _rgb_distance(bottom_pixel, Color(0, 0, 1)):
			bottom_near_leaning += 1
	assert_gt(top_far_leaning, size / 2, "top edge (toward far) should mostly read the far image's color")
	assert_gt(bottom_near_leaning, size / 2, "bottom edge (away from far) should mostly read the near image's color")

	# Every output pixel must be EXACTLY one of the two source colors --
	# proves real pixels are sourced verbatim, with no synthesized speckle
	# blended in on top (unlike the biome-name-based wrapper's source
	# images, which already carry their own real texture before this ever
	# runs).
	for x in size:
		var p := image.get_pixel(x, 0)
		assert_true(
			p.is_equal_approx(Color(1, 0, 0, 1)) or p.is_equal_approx(Color(0, 0, 1, 1)),
			"pixel (%d, 0) should be exactly one of the two source colors, got %s" % [x, p]
		)


func test_generate_multi_directional_blend_image_matches_the_from_variant_given_its_own_sources():
	var near_image := generator.generate_image("forest", 3)
	var far_image := generator.generate_image("grassland", 3)
	var via_biomes := generator.generate_multi_directional_blend_image("forest", "grassland", [Vector2i(0, -1)], 3)
	var via_from := generator.generate_multi_directional_blend_image_from(near_image, far_image, [Vector2i(0, -1)])
	assert_eq(via_biomes.get_data(), via_from.get_data(), "the biome-name wrapper should just be generate_image + _from")


func test_corner_image_from_sources_the_real_given_pixels():
	var own_image := _solid_image(Color(1, 0, 0, 1))
	var other_image := _solid_image(Color(0, 0, 1, 1))
	var image := generator.generate_corner_image_from(own_image, other_image, [Vector2i(1, -1)])
	var size := own_image.get_width()
	assert_true(
		image.get_pixel(size - 1, 0).is_equal_approx(Color(0, 0, 1, 1)),
		"the named (NE) corner should be carved to other_image's real pixel"
	)
	assert_true(
		image.get_pixel(0, size - 1).is_equal_approx(Color(1, 0, 0, 1)),
		"the opposite (SW) corner should stay own_image's real pixel"
	)


func test_generate_corner_image_matches_the_from_variant_given_its_own_sources():
	var own_image := generator.generate_image("mountain", 4)
	var other_image := generator.generate_image("ocean", 4)
	var via_biomes := generator.generate_corner_image("mountain", "ocean", [Vector2i(1, -1)], 4)
	var via_from := generator.generate_corner_image_from(own_image, other_image, [Vector2i(1, -1)])
	assert_eq(via_biomes.get_data(), via_from.get_data(), "the biome-name wrapper should just be generate_image + _from")


# -- real-time tile animation frames (see TerrainRenderer's animated tiles) --

func test_frame_zero_matches_the_plain_generate_image():
	var plain := generator.generate_image("grassland", 2)
	var frame_zero := generator.generate_frame_image("grassland", 2, 0)
	assert_eq(plain.get_data(), frame_zero.get_data())


## Water visibly moves: wave streaks scroll one row per frame, and the cycle
## is seamless (frame FRAME_COUNT wraps back to frame 0's look).
func test_ocean_frames_differ_and_loop_seamlessly():
	var f0 := generator.generate_frame_image("ocean", 0, 0)
	var f1 := generator.generate_frame_image("ocean", 0, 1)
	var wrapped := generator.generate_frame_image("ocean", 0, ProceduralTerrainSprite.FRAME_COUNT)
	assert_ne(f0.get_data(), f1.get_data(), "ocean frames should visibly differ (moving waves)")
	assert_eq(f0.get_data(), wrapped.get_data(), "the animation cycle should loop seamlessly")


## Baked grassland tiles are deliberately STATIC: a 1px blade tip jumping
## across 4 tile frames reads as flicker, never wind. The GPU micro-blade
## field that used to carry real motion was removed (flat, non-interactive
## rectangles) -- decorative grass motion is expected to return via a real
## illustrated grass layer, not by animating the baked tile itself.
func test_grassland_frames_are_identical_no_baked_flicker():
	var f0 := generator.generate_frame_image("grassland", 0, 0)
	var f1 := generator.generate_frame_image("grassland", 0, 1)
	assert_eq(f0.get_data(), f1.get_data(), "baked grassland frames must not flicker")


## Arid/rocky biomes stay static -- identical frames, deliberately, so their
## animation costs nothing visually or at build time to reason about.
func test_desert_frames_are_identical():
	var f0 := generator.generate_frame_image("desert", 0, 0)
	var f1 := generator.generate_frame_image("desert", 0, 1)
	assert_eq(f0.get_data(), f1.get_data())


func test_frame_images_are_deterministic():
	var a := generator.generate_frame_image("ocean", 3, 2)
	var b := generator.generate_frame_image("ocean", 3, 2)
	assert_eq(a.get_data(), b.get_data())


## Richness pin: a grassland tile is no longer just base+speckle -- tufts and
## flower accents push it past a handful of distinct colors.
func test_grassland_tile_has_rich_color_variety():
	var image := generator.generate_frame_image("grassland", 0, 0)
	var distinct := {}
	for y in ProceduralTerrainSprite.SIZE:
		for x in ProceduralTerrainSprite.SIZE:
			distinct[image.get_pixel(x, y)] = true
	assert_gte(distinct.size(), 5, "grassland should layer tufts/flowers over the base speckle")


# -- rounded tile corners (real pixel-art geometry, not an alpha overlay) -----
#
# Where a biome only touches a different one at a single tile's actual
# geometric corner (e.g. an ocean cell with land to both its north AND east),
# a plain per-cell tile grid reads as a hard right-angle notch cut into the
# shape -- reported directly: tile borders look "square" instead of rounded.
# generate_corner_image paints own_biome's own tile as normal, except for a
# quarter-circle wedge right at the named corner (radius
# CORNER_RADIUS_PIXELS, 8px at this generator's SIZE resolution), which is
# replaced pixel-for-pixel with other_biome's own tile texture -- a real
# carved shape in the opaque BASE tile layer
# (TerrainRenderer.paint()'s TileMapLayer), not a translucent GPU overlay
# effect (see the earlier, rejected attempt at shore-distance alpha
# rounding: that overlay sits on top of this fully-opaque base tile and can
# never change the base tile's own square silhouette).

func test_corner_image_is_the_expected_size_and_opaque():
	var image := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 0)
	assert_eq(image.get_width(), ProceduralTerrainSprite.SIZE)
	assert_eq(image.get_height(), ProceduralTerrainSprite.SIZE)
	assert_eq(image.get_pixel(0, 0).a, 1.0)


## The tile's own true corner pixel (in the direction being rounded, here
## north-east) sits inside the carved wedge, so it must read as EXACTLY the
## other biome's texture at that pixel -- not a blend, a real replacement.
func test_the_named_corners_own_pixel_is_replaced_by_the_other_biome():
	var corner := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 0)
	var other := generator.generate_image("grassland", 0)
	var size := ProceduralTerrainSprite.SIZE
	assert_eq(
		corner.get_pixel(size - 1, 0), other.get_pixel(size - 1, 0),
		"the NE tile corner pixel should be carved out to the other biome's own texture"
	)


## Far from the named corner -- either along the straight edges nearest the
## OTHER three (untouched) corners, or deep in the tile's own interior --
## the tile must render pixel-identical to its own plain, uncarved image.
func test_pixels_far_from_the_named_corner_are_untouched():
	var corner := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 0)
	var own := generator.generate_image("ocean", 0)
	var size := ProceduralTerrainSprite.SIZE
	# The other three tile corners (SW, SE, NW) -- none of these should be
	# touched by an NE-only carve.
	for point in [Vector2i(0, 0), Vector2i(0, size - 1), Vector2i(size - 1, size - 1)]:
		assert_eq(
			corner.get_pixel(point.x, point.y), own.get_pixel(point.x, point.y),
			"corner %s must be untouched by an NE-only carve" % point
		)
	# Near the tile's own center, well outside the carve radius.
	assert_eq(corner.get_pixel(size / 2, size / 2), own.get_pixel(size / 2, size / 2))


func test_generate_corner_image_is_deterministic():
	var a := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 2)
	var b := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 2)
	assert_eq(a.get_data(), b.get_data())


## Rounding a different named corner carves a DIFFERENT quadrant -- proof the
## carve genuinely follows `corner_direction` rather than always cutting the
## same fixed corner.
func test_a_different_corner_direction_carves_a_different_quadrant():
	var size := ProceduralTerrainSprite.SIZE
	var ne := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1)], 0)
	var sw := generator.generate_corner_image("ocean", "grassland", [Vector2i(-1, 1)], 0)
	var own := generator.generate_image("ocean", 0)
	# NE corner pixel is carved by the NE image but not by the SW image.
	assert_ne(ne.get_pixel(size - 1, 0), sw.get_pixel(size - 1, 0))
	assert_eq(sw.get_pixel(size - 1, 0), own.get_pixel(size - 1, 0))
	# SW corner pixel is carved by the SW image but not by the NE image.
	assert_ne(sw.get_pixel(0, size - 1), ne.get_pixel(0, size - 1))
	assert_eq(ne.get_pixel(0, size - 1), own.get_pixel(0, size - 1))


## A cell can qualify on more than one corner at once -- a single-tile spit
## with water on three sides, or a lone one-tile pond surrounded on all four
## (measured directly against real generated chunks: 859 of 3355 real corner
## cells qualify on more than one corner simultaneously). Passing multiple
## directions must carve EVERY one of them, not just the first -- silently
## dropping the rest is exactly why some corners on a real coastline carved
## while others on the same tile stayed hard right angles (reported: "still
## not giving every corner a border radius").
func test_multiple_corner_directions_all_carve_on_the_same_tile():
	var size := ProceduralTerrainSprite.SIZE
	var multi := generator.generate_corner_image("ocean", "grassland", [Vector2i(1, -1), Vector2i(-1, 1)], 0)
	var other := generator.generate_image("grassland", 0)
	var own := generator.generate_image("ocean", 0)
	# Both the NE and SW true corner pixels must be carved...
	assert_eq(
		multi.get_pixel(size - 1, 0), other.get_pixel(size - 1, 0),
		"the NE corner should be carved when NE is one of several requested directions"
	)
	assert_eq(
		multi.get_pixel(0, size - 1), other.get_pixel(0, size - 1),
		"the SW corner should be carved when SW is one of several requested directions"
	)
	# ...while the two UNREQUESTED corners (SE, NW) stay untouched.
	assert_eq(multi.get_pixel(size - 1, size - 1), own.get_pixel(size - 1, size - 1))
	assert_eq(multi.get_pixel(0, 0), own.get_pixel(0, 0))


## All four corners at once (a lone one-tile pond/island) must carve all
## four -- the maximal real case found in real generated chunk data.
func test_all_four_corner_directions_carve_simultaneously():
	var size := ProceduralTerrainSprite.SIZE
	var all_four := generator.generate_corner_image(
		"ocean", "grassland", ProceduralTerrainSprite.CORNER_DIRECTIONS, 0
	)
	var other := generator.generate_image("grassland", 0)
	for point in [Vector2i(size - 1, 0), Vector2i(size - 1, size - 1), Vector2i(0, size - 1), Vector2i(0, 0)]:
		assert_eq(
			all_four.get_pixel(point.x, point.y), other.get_pixel(point.x, point.y),
			"corner %s should be carved when every direction is requested" % point
		)


## Named/tested per CLAUDE.md's "no eyeballed tuning" rule: the radius is
## tuned in ART-PIXEL units (the unit a human actually picks a border-radius
## in), pinned to exactly 8px at this generator's SIZE (== TerrainRenderer.
## ART_TILE_SIZE) resolution -- not just "some fraction".
func test_corner_radius_is_exactly_8_pixels_at_art_tile_size_resolution():
	assert_eq(ProceduralTerrainSprite.CORNER_RADIUS_PIXELS, 8.0)
	assert_eq(ProceduralTerrainSprite.SIZE, 64, "the 8px figure is calibrated against this exact tile resolution")


func test_corner_radius_fraction_is_derived_from_the_pixel_constant_and_stays_reasonable():
	assert_eq(
		ProceduralTerrainSprite.CORNER_RADIUS_FRACTION,
		ProceduralTerrainSprite.CORNER_RADIUS_PIXELS / ProceduralTerrainSprite.SIZE,
		"the fraction generate_corner_image uses must be derived from the tested pixel constant, not a separate literal"
	)
	# Bounded well below half the tile (a radius at/above 0.5 would consume
	# the entire tile edge-to-edge, no longer reading as a corner carve).
	assert_gt(ProceduralTerrainSprite.CORNER_RADIUS_FRACTION, 0.0)
	assert_lt(ProceduralTerrainSprite.CORNER_RADIUS_FRACTION, 0.5)


func test_corner_directions_are_exactly_the_four_diagonals():
	var directions: Array = ProceduralTerrainSprite.CORNER_DIRECTIONS
	assert_eq(directions.size(), 4)
	for direction in directions:
		assert_eq(absi(direction.x), 1, "every corner direction must be a true diagonal")
		assert_eq(absi(direction.y), 1, "every corner direction must be a true diagonal")


# -- individually varied grass blades -----------------------------------------
#
# Shoreline foam and rain-ripple rings used to be baked-tile tests here; both
# moved to the GPU WaterFx overlay (see test_water_shader.gd and
# test_procedural_shore_distance_sprite.gd) -- shore/rain are now continuous
# per-pixel GPU effects, not discrete tile art this generator produces.

## Grass blades are individuals: deterministic per (seed, index), with real
## variety in height and color across a tile -- not six clones of one blade.
func test_blade_specs_are_deterministic_and_varied():
	var heights := {}
	var colors := {}
	for seed_value in 3:
		for i in ProceduralTerrainSprite.BLADE_COUNT:
			var spec := generator.blade_spec(seed_value, i)
			assert_eq(spec, generator.blade_spec(seed_value, i))
			assert_between(spec.height, 8, 26)
			heights[spec.height] = true
			colors[spec.color_index] = true
	assert_gt(heights.size(), 1, "blades should vary in height")
	assert_gt(colors.size(), 1, "blades should vary in color")


## Grass must read as a dense MEADOW of individual blades, not a handful of
## strokes on a flat field -- reported as "the grass tiles don't look nice
## anymore, make it look more like real grass blades". A 64px tile has room
## for a real blade population; pinning the count stops it silently
## regressing to the sparse look.
func test_grassland_is_densely_covered_in_blades():
	assert_gte(ProceduralTerrainSprite.BLADE_COUNT, 40, "a 64px tile needs a real blade population to read as meadow")


## Real blades taper: wide at the root, single-pixel at the tip. A uniform
## 2px-wide stroke reads as a painted stripe, not a blade.
func test_blades_taper_from_root_to_tip():
	assert_eq(generator.blade_width_at(0.0), ProceduralTerrainSprite.BLADE_ROOT_WIDTH, "root is the widest point")
	assert_eq(generator.blade_width_at(1.0), 1, "the tip narrows to a single pixel")
	assert_gt(ProceduralTerrainSprite.BLADE_ROOT_WIDTH, 1, "a blade must actually taper, not be uniform")


## Blades curve rather than standing as straight lines -- the lean grows
## non-linearly from a planted root, so a tuft reads as bending grass.
func test_blade_curve_accelerates_toward_the_tip():
	var lower := generator.blade_curve_fraction(0.5)
	assert_almost_eq(generator.blade_curve_fraction(0.0), 0.0, 0.0001, "the root stays planted")
	assert_almost_eq(generator.blade_curve_fraction(1.0), 1.0, 0.0001, "the tip carries the full lean")
	assert_lt(lower, 0.5, "mid-blade should lag a straight line -- a curve, not a diagonal")


## Regression for the 4x resolution pass (docs/concept/art_resolution.md):
## a naive nearest-neighbour upscale of the old 16x16 art would repeat each
## source pixel across a 4x4 block, so every pixel in that block would be
## identical. This generator paints per-pixel at the tile's real (now 64x64)
## resolution instead, so at least some 4x4 block somewhere on a speckled
## tile must contain genuine internal variation -- proof the extra
## resolution carries real information, not just a blown-up copy of the
## smaller tile.
func test_speckled_texture_has_genuine_per_pixel_detail_not_upscaled_blocks():
	var image := generator.generate_image("mountain", 0)
	var size := ProceduralTerrainSprite.SIZE
	var found_internal_variation := false
	var block := 0
	while block * 4 + 3 < size and not found_internal_variation:
		var bx := block * 4
		var by := block * 4
		var first := image.get_pixel(bx, by)
		for dy in 4:
			for dx in 4:
				if image.get_pixel(bx + dx, by + dy) != first:
					found_internal_variation = true
		block += 1
	assert_true(
		found_internal_variation,
		"expected at least one 4x4 block with internal pixel variation -- texture reads as upscaled, not native-resolution"
	)


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _average_color(image: Image) -> Color:
	var total := Color(0, 0, 0, 0)
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			total += image.get_pixel(x, y)
			count += 1
	return total / count


# -- moss patches must be organic, not stamped squares -----------------------
#
# _paint_moss filled a perfect axis-aligned _MOSS_BLOB_SIZE square of flat
# colour, three times per forest tile. Across a forest that read as a litter
# of hard green rectangles lying on the ground (reported: "there are these
# green square patches which look horrible"). A patch is now a ragged blob
# whose rim wanders per direction.

func test_a_moss_patch_is_not_a_filled_rectangle():
	var offsets := ProceduralTerrainSprite.moss_patch_offsets(4242, 0)
	assert_gt(offsets.size(), 0, "a patch should cover some ground")

	var min_x := 9999
	var max_x := -9999
	var min_y := 9999
	var max_y := -9999
	for offset in offsets:
		min_x = mini(min_x, offset.x)
		max_x = maxi(max_x, offset.x)
		min_y = mini(min_y, offset.y)
		max_y = maxi(max_y, offset.y)
	var bounding_area := (max_x - min_x + 1) * (max_y - min_y + 1)
	assert_lt(
		float(offsets.size()), float(bounding_area) * 0.92,
		"a moss patch must not fill its own bounding box -- that is a rectangle"
	)


## A ragged rim means the patch's width genuinely varies row to row. A disc
## would also pass the bounding-box test above, so this pins the wobble.
func test_a_moss_patchs_outline_is_ragged_not_a_clean_disc():
	var widths := {}
	for index in 4:
		var rows := {}
		for offset in ProceduralTerrainSprite.moss_patch_offsets(99, index):
			rows[offset.y] = int(rows.get(offset.y, 0)) + 1
		for row in rows:
			widths[rows[row]] = true
	assert_gt(widths.size(), 3, "patch rows should vary in width, not step like a circle")


func test_moss_patches_are_deterministic_and_vary_by_seed():
	assert_eq(
		ProceduralTerrainSprite.moss_patch_offsets(7, 1),
		ProceduralTerrainSprite.moss_patch_offsets(7, 1)
	)
	assert_ne(
		ProceduralTerrainSprite.moss_patch_offsets(7, 1),
		ProceduralTerrainSprite.moss_patch_offsets(8, 1)
	)


## Neighbouring patches on the same tile must differ too -- three identical
## blobs at three positions is still a stamped look.
func test_patches_on_the_same_tile_differ_from_each_other():
	assert_ne(
		ProceduralTerrainSprite.moss_patch_offsets(31, 0),
		ProceduralTerrainSprite.moss_patch_offsets(31, 1)
	)


# -- ground texture reads as texture, not as static --------------------------
#
# Every tile was filled with INDEPENDENT per-pixel noise at 35% density: a
# third of all pixels randomly darkened or lightened, each one on its own.
# That is the definition of grain, and under the old non-pixel-perfect
# fullscreen upscale it shimmered as well (reported: "the graphics look coarse
# and grainy"). Real pixel-art ground is made of deliberate MARKS -- clumps,
# dashes, patches -- with clean ground showing between them.

## How often the tile CHANGES appearance from one pixel to the next, along a
## row. This is the direct measure of graininess: independent per-pixel noise
## changes at nearly every step (~0.5 for 35%-density static), while texture
## made of real marks holds the same value for a run of pixels and changes
## only at a mark's edge.
func _horizontal_transition_rate(image: Image) -> float:
	var size := ProceduralTerrainSprite.SIZE
	var changes := 0
	var pairs := 0
	for y in size:
		for x in range(size - 1):
			pairs += 1
			if image.get_pixel(x, y) != image.get_pixel(x + 1, y):
				changes += 1
	if pairs == 0:
		return 0.0
	return float(changes) / float(pairs)


func test_ground_marks_clump_together_instead_of_speckling_at_random():
	var image := generator.generate_image("mountain", 7)
	assert_lt(
		_horizontal_transition_rate(image), 0.3,
		"the tile must not change appearance at nearly every pixel -- that IS the grain"
	)


## Neatness: clean ground has to show between the marks, or the tile is just
## noise of a different shape.
func test_clean_ground_shows_between_the_marks():
	var base: Color = ProceduralTerrainSprite.BASE_COLORS["mountain"]
	var image := generator.generate_image("mountain", 3)
	var size := ProceduralTerrainSprite.SIZE
	var clean := 0
	for y in size:
		for x in size:
			if _rgb_distance(image.get_pixel(x, y), base) < 0.01:
				clean += 1
	var fraction := float(clean) / float(size * size)
	assert_gt(fraction, 0.72, "the ground should read as ground with marks on it")
	assert_lt(fraction, 0.95, "...but not as a flat untextured slab")


## The calm must not come from painting in blocks -- that would be the
## upscaled look the resolution pass exists to avoid. Marks keep ragged,
## per-pixel edges.
func test_marks_still_have_per_pixel_ragged_edges():
	var base: Color = ProceduralTerrainSprite.BASE_COLORS["mountain"]
	var image := generator.generate_image("mountain", 11)
	var size := ProceduralTerrainSprite.SIZE
	var odd_edges := 0
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			# A mark edge landing on an ODD x cannot be a 2x2 block boundary,
			# so counting those proves the marks are not block-aligned.
			var here_is_mark := _rgb_distance(image.get_pixel(x, y), base) >= 0.01
			var right_is_clean := _rgb_distance(image.get_pixel(x + 1, y), base) < 0.01
			if x % 2 == 1 and here_is_mark and right_is_clean:
				odd_edges += 1
	assert_gt(odd_edges, 15, "mark edges must be genuinely per-pixel, not block-aligned")


## Transition rate measured along an arbitrary direction, so the texture can
## be checked for GRAIN as well as for noisiness.
func _transition_rate_along(image: Image, dx: int, dy: int) -> float:
	var size := ProceduralTerrainSprite.SIZE
	var changes := 0
	var pairs := 0
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			pairs += 1
			if image.get_pixel(x, y) != image.get_pixel(x + dx, y + dy):
				changes += 1
	if pairs == 0:
		return 0.0
	return float(changes) / float(pairs)


## Ground must have no DIRECTION to it.
##
## The first attempt at clustering marks took its cell roll from Godot's
## string hash, which correlates across near-identical inputs -- the exact
## trap PixelNoise exists to avoid, and which this file was already bitten by
## twice (village houses all one size, whole rows of leaves at one angle).
## The result was ground visibly striped along one diagonal: not static any
## more, but combed. The transition-rate test could not see it, because
## banding lowers the horizontal rate exactly as clean marks do -- it only
## showed up on looking at the pixels.
func test_the_ground_texture_has_no_directional_grain():
	for biome in ["mountain", "tundra", "forest"]:
		var image := generator.generate_image(biome, 5)
		var rates := [
			_transition_rate_along(image, 1, 0),
			_transition_rate_along(image, 0, 1),
			_transition_rate_along(image, 1, 1),
			_transition_rate_along(image, 1, -1),
		]
		var lowest: float = rates[0]
		var highest: float = rates[0]
		for rate in rates:
			lowest = minf(lowest, float(rate))
			highest = maxf(highest, float(rate))
		assert_lt(
			highest - lowest, 0.1,
			"%s is combed: transition rates by direction were %s" % [biome, str(rates)]
		)


func test_the_texture_is_still_deterministic():
	assert_eq(
		generator.generate_image("grassland", 5).get_data(),
		generator.generate_image("grassland", 5).get_data()
	)
	assert_ne(
		generator.generate_image("grassland", 5).get_data(),
		generator.generate_image("grassland", 6).get_data()
	)
