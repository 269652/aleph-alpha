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


func _far_leaning_count_in_row(image: Image, y: int, far_biome: String, near_biome: String) -> int:
	var far_base: Color = ProceduralTerrainSprite.BASE_COLORS[far_biome]
	var near_base: Color = ProceduralTerrainSprite.BASE_COLORS[near_biome]
	var count := 0
	for x in ProceduralTerrainSprite.SIZE:
		var pixel := image.get_pixel(x, y)
		if _rgb_distance(pixel, far_base) < _rgb_distance(pixel, near_base):
			count += 1
	return count


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
## across 4 tile frames reads as flicker, never wind. Real blade motion is
## owned by the GPU micro-blade field (grass_blade_field.gd), which sways
## continuously at any frame rate.
func test_grassland_frames_are_identical_motion_lives_in_the_gpu_field():
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
