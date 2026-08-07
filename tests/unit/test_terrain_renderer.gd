extends GutTest

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")

var renderer: TerrainRenderer
var tile_map_layer: TileMapLayer


func before_each():
	renderer = TerrainRenderer.new()
	tile_map_layer = TileMapLayer.new()


func after_each():
	tile_map_layer.free()


func test_build_tile_set_creates_one_atlas_tile_per_biome_variant_plus_the_buildable_and_structure_tiles():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	# +1: the player-placeable "earth" tile (see atlas_coords_for_modification).
	# + ProceduralStructureSprite.STRUCTURE_IDS.size(): one dedicated tile per
	# known placed structure (campfire, furnace), reserved right after earth.
	# + blend tiles: every ordered pair of *distinct* biomes (n*(n-1)) x every
	# non-empty subset of the 4 cardinal directions (DIRECTION_MASK_COUNT = 15)
	# x BLEND_VARIANTS (deliberately fewer than base variants -- border fringe
	# doesn't need six looks, and each extra costs 630 atlas images at build).
	# Note: animated biome tiles still count once each here -- their extra
	# FRAME_COUNT cells hold frames, not tiles.
	# Shorelines and rain are no longer baked tiles at all -- both moved to
	# the GPU WaterFx overlay (see build_water_overlay_tile_set,
	# water_shader.gd), which reads shore-distance as DATA instead of
	# swapping discrete art. Ocean is a plain animated biome tile like any
	# other, so this atlas has no water-specific terms anymore.
	var n := BiomeClassifier.KNOWN_BIOMES.size()
	var expected := (
		n * TerrainRenderer.VARIANTS_PER_BIOME + 1 + ProceduralStructureSprite.STRUCTURE_IDS.size()
		+ n * (n - 1) * TerrainRenderer.DIRECTION_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
	)
	assert_eq(source.get_tiles_count(), expected)


## Isolates the growth claim on its own: removing the structure tiles from
## the total should land exactly on the pre-structure-tiles tile count (the
## formula the test above used before campfire/furnace got their own art).
func test_build_tile_set_total_tile_count_grows_by_exactly_one_tile_per_structure_id():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var n := BiomeClassifier.KNOWN_BIOMES.size()
	var tile_count_without_structures := (
		n * TerrainRenderer.VARIANTS_PER_BIOME + 1
		+ n * (n - 1) * TerrainRenderer.DIRECTION_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
	)
	assert_eq(
		source.get_tiles_count() - tile_count_without_structures,
		ProceduralStructureSprite.STRUCTURE_IDS.size()
	)


func test_atlas_coords_for_modification_is_distinct_from_every_biome_variant():
	var modification_coords := renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID)
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			assert_ne(modification_coords, renderer.atlas_coords_for_biome(biome_name, variant))


## campfire/furnace (see item_catalog.gd's "placeable" kind) must each get
## their own atlas slot -- distinct from earth, from every biome tile, and
## from each other -- instead of all sharing the single earth slot.
func test_atlas_coords_for_campfire_is_distinct_from_earth_and_every_biome_variant():
	var campfire_coords := renderer.atlas_coords_for_modification("campfire")
	assert_ne(campfire_coords, renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID))
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			assert_ne(campfire_coords, renderer.atlas_coords_for_biome(biome_name, variant))


func test_atlas_coords_for_furnace_is_distinct_from_earth_and_every_biome_variant():
	var furnace_coords := renderer.atlas_coords_for_modification("furnace")
	assert_ne(furnace_coords, renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID))
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			assert_ne(furnace_coords, renderer.atlas_coords_for_biome(biome_name, variant))


func test_atlas_coords_for_campfire_and_furnace_are_distinct_from_each_other():
	assert_ne(
		renderer.atlas_coords_for_modification("campfire"),
		renderer.atlas_coords_for_modification("furnace")
	)


# -- real-time tile animation (base biome tiles play FRAME_COUNT frames) ------

func test_biome_tiles_are_registered_as_animated_with_the_pinned_frame_count():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var coords := renderer.atlas_coords_for_biome("ocean", 0)
	assert_eq(source.get_tile_animation_frames_count(coords), TerrainRenderer.FRAME_COUNT)
	# Frame duration is a tuned constant -- pinned here per the no-eyeballed-
	# values rule. Almost-eq: Godot stores durations as 32-bit floats, so the
	# 64-bit literal doesn't round-trip exactly.
	assert_almost_eq(
		source.get_tile_animation_frame_duration(coords, 0),
		TerrainRenderer.FRAME_DURATION_SECONDS,
		0.0001
	)
	# Grassland runs on its faster blade-sway clock.
	assert_almost_eq(
		source.get_tile_animation_frame_duration(renderer.atlas_coords_for_biome("grassland", 0), 0),
		TerrainRenderer.GRASS_FRAME_DURATION_SECONDS,
		0.0001
	)


func test_animation_frame_cells_are_not_separate_tiles():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var first := renderer.atlas_coords_for_biome("ocean", 0)
	# The cells to the right of an animated tile hold its frames, not tiles of
	# their own -- creating tiles there would corrupt the animation layout.
	assert_false(source.has_tile(first + Vector2i(1, 0)))


func test_earth_and_structure_tiles_stay_static_single_frame():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(source.get_tile_animation_frames_count(renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID)), 1)
	assert_eq(source.get_tile_animation_frames_count(renderer.atlas_coords_for_modification("campfire")), 1)


## Frame blocks must never wrap an atlas row (frames lay out horizontally), so
## the column count has to divide evenly into frame-sized blocks.
func test_atlas_columns_align_with_frame_blocks():
	assert_eq(TerrainRenderer.ATLAS_COLUMNS % TerrainRenderer.FRAME_COUNT, 0)


## More variation per biome: bumped from 4 so the ground reads as natural
## ground cover, not a short repeating texture loop.
func test_variants_per_biome_is_at_least_six():
	assert_gte(TerrainRenderer.VARIANTS_PER_BIOME, 6)


# -- water overlay tile set (shore-distance DATA for the GPU water shader) ---
#
# Shorelines and rain no longer live as discrete baked tiles at all -- both
# moved to the GPU WaterFx overlay layer (see water_shader.gd), which reads
# a small "shore distance" tile family as per-pixel data (not art) to blend
# and animate everything continuously. The base Terrain layer's ocean cells
# are now plain animated water tiles, same as every other biome (see
# test_paint_keeps_open_water_as_plain_animated_ocean below).

func test_water_overlay_tile_set_has_one_flat_tile_plus_masks_plus_rings():
	var overlay_set := renderer.build_water_overlay_tile_set()
	var source := overlay_set.get_source(0) as TileSetAtlasSource
	# 1 flat "deep water, no land within RING_MAX tiles" tile + one per
	# non-empty cardinal direction-mask (ring 0, touching land directly,
	# DIRECTION_MASK_COUNT = 15) + one flat tile per ring 1..RING_MAX-1 (see
	# RING_MAX's doc comment on why shore influence needs to span multiple
	# tiles, not just one).
	assert_eq(
		source.get_tiles_count(),
		1 + TerrainRenderer.DIRECTION_MASK_COUNT + (TerrainRenderer.RING_MAX - 1)
	)


func test_atlas_coords_for_water_overlay_differs_by_land_direction_set_at_ring_zero():
	var no_land := renderer.atlas_coords_for_water_overlay([])
	var north := renderer.atlas_coords_for_water_overlay([Vector2i(0, -1)], 0)
	var north_east := renderer.atlas_coords_for_water_overlay([Vector2i(0, -1), Vector2i(1, 0)], 0)
	assert_ne(no_land, north)
	assert_ne(north, north_east)


func test_atlas_coords_for_water_overlay_is_independent_of_direction_order():
	var a := renderer.atlas_coords_for_water_overlay([Vector2i(0, -1), Vector2i(1, 0)], 0)
	var b := renderer.atlas_coords_for_water_overlay([Vector2i(1, 0), Vector2i(0, -1)], 0)
	assert_eq(a, b)


func test_water_overlay_tiles_are_real_shore_distance_data_not_a_flat_fill():
	var overlay_set := renderer.build_water_overlay_tile_set()
	var source := overlay_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()
	var coords := renderer.atlas_coords_for_water_overlay([Vector2i(0, -1)], 0)
	var origin := Vector2i(coords.x * TerrainRenderer.TILE_SIZE, coords.y * TerrainRenderer.TILE_SIZE)
	var edge_pixel := image.get_pixel(origin.x + 8, origin.y)
	var far_pixel := image.get_pixel(origin.x + 8, origin.y + TerrainRenderer.TILE_SIZE - 1)
	assert_lt(edge_pixel.r, far_pixel.r, "the land-facing edge should read closer to shore than the far side")


# -- multi-tile shore rings (interference needs room to be visible) -----------

func test_atlas_coords_for_water_overlay_differs_by_ring_distance():
	var touching := renderer.atlas_coords_for_water_overlay([Vector2i(0, -1)], 0)
	var one_tile_out := renderer.atlas_coords_for_water_overlay([], 1)
	var two_tiles_out := renderer.atlas_coords_for_water_overlay([], 2)
	assert_ne(touching, one_tile_out)
	assert_ne(one_tile_out, two_tiles_out)


func test_atlas_coords_for_water_overlay_treats_ring_at_or_beyond_ring_max_as_open_water():
	var at_max := renderer.atlas_coords_for_water_overlay([], TerrainRenderer.RING_MAX)
	var past_max := renderer.atlas_coords_for_water_overlay([], TerrainRenderer.RING_MAX + 5)
	var open_water := renderer.atlas_coords_for_water_overlay([])
	assert_eq(at_max, open_water)
	assert_eq(past_max, open_water)


func test_ring_tiles_step_toward_the_open_water_value():
	var overlay_set := renderer.build_water_overlay_tile_set()
	var source := overlay_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()
	var ring1_coords := renderer.atlas_coords_for_water_overlay([], 1)
	var ring2_coords := renderer.atlas_coords_for_water_overlay([], 2)
	var ring1_value := image.get_pixel(ring1_coords.x * TerrainRenderer.TILE_SIZE, 0).r
	var ring2_value := image.get_pixel(ring2_coords.x * TerrainRenderer.TILE_SIZE, 0).r
	assert_lt(ring1_value, ring2_value, "farther rings should read closer to open water")


func test_paint_keeps_open_water_as_plain_animated_ocean():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 1
	chunk.elevation = PackedFloat32Array([0.1, 0.1])
	chunk.biome = PackedStringArray(["ocean", "ocean"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("ocean", variant)
	)


## Fail-safe default (matching this codebase's `.get(x, default)` convention):
## an unrecognized modification tile_id must never crash -- it falls back to
## the plain-earth slot, same as EARTH_TILE_ID itself.
func test_atlas_coords_for_modification_falls_back_to_earth_for_an_unrecognized_tile_id():
	assert_eq(
		renderer.atlas_coords_for_modification("some_unknown_future_structure"),
		renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID)
	)


func test_build_tile_set_uses_real_procedural_art_not_a_flat_color_fill():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()

	var coords := renderer.atlas_coords_for_biome("grassland", 0)
	var origin := Vector2i(coords.x * TerrainRenderer.TILE_SIZE, coords.y * TerrainRenderer.TILE_SIZE)
	var tile_image := image.get_region(Rect2i(origin, Vector2i(TerrainRenderer.TILE_SIZE, TerrainRenderer.TILE_SIZE)))

	var first_pixel := tile_image.get_pixel(0, 0)
	var all_same_color := true
	for y in TerrainRenderer.TILE_SIZE:
		for x in TerrainRenderer.TILE_SIZE:
			if tile_image.get_pixel(x, y) != first_pixel:
				all_same_color = false
	assert_false(all_same_color, "grassland tile should use real procedural texture, not a flat color fill")


func test_build_tile_set_uses_real_procedural_art_for_campfire_not_a_flat_color_fill():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()

	var coords := renderer.atlas_coords_for_modification("campfire")
	var origin := Vector2i(coords.x * TerrainRenderer.TILE_SIZE, coords.y * TerrainRenderer.TILE_SIZE)
	var tile_image := image.get_region(Rect2i(origin, Vector2i(TerrainRenderer.TILE_SIZE, TerrainRenderer.TILE_SIZE)))

	var first_pixel := tile_image.get_pixel(0, 0)
	var all_same_color := true
	for y in TerrainRenderer.TILE_SIZE:
		for x in TerrainRenderer.TILE_SIZE:
			if tile_image.get_pixel(x, y) != first_pixel:
				all_same_color = false
	assert_false(all_same_color, "campfire tile should use real procedural texture, not a flat color fill")


func test_build_tile_set_uses_real_procedural_art_for_furnace_not_a_flat_color_fill():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()

	var coords := renderer.atlas_coords_for_modification("furnace")
	var origin := Vector2i(coords.x * TerrainRenderer.TILE_SIZE, coords.y * TerrainRenderer.TILE_SIZE)
	var tile_image := image.get_region(Rect2i(origin, Vector2i(TerrainRenderer.TILE_SIZE, TerrainRenderer.TILE_SIZE)))

	var first_pixel := tile_image.get_pixel(0, 0)
	var all_same_color := true
	for y in TerrainRenderer.TILE_SIZE:
		for x in TerrainRenderer.TILE_SIZE:
			if tile_image.get_pixel(x, y) != first_pixel:
				all_same_color = false
	assert_false(all_same_color, "furnace tile should use real procedural texture, not a flat color fill")


func test_atlas_coords_are_unique_across_every_biome_and_variant():
	var seen := {}
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			var coords: Vector2i = renderer.atlas_coords_for_biome(biome_name, variant)
			assert_false(seen.has(coords), "duplicate atlas coords for %s variant %d: %s" % [biome_name, variant, coords])
			seen[coords] = true


func test_variant_index_for_position_is_deterministic():
	var a := renderer.variant_index_for_position(42, 7)
	var b := renderer.variant_index_for_position(42, 7)
	assert_eq(a, b)


func test_variant_index_for_position_stays_within_bounds():
	for i in 20:
		var variant := renderer.variant_index_for_position(i * 13, i * 29)
		assert_between(variant, 0, TerrainRenderer.VARIANTS_PER_BIOME - 1)


func test_variant_index_varies_across_positions():
	var variants := {}
	for i in 20:
		variants[renderer.variant_index_for_position(i, i * 3)] = true
	assert_gt(variants.size(), 1, "expected more than one variant across sampled positions")


func _make_chunk() -> Chunk:
	# Uniform biome: every cell's cardinal neighbors match, so no cell blends
	# (all differing neighbors now blend -- see the dedicated blending tests
	# below). These are the plain paint() tests.
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.4, 0.4, 0.4, 0.4])
	chunk.biome = PackedStringArray(["grassland", "grassland", "grassland", "grassland"])
	return chunk


func test_paint_sets_a_cell_for_every_chunk_position():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()

	renderer.paint(tile_map_layer, chunk)

	for y in chunk.height:
		for x in chunk.width:
			assert_ne(tile_map_layer.get_cell_source_id(Vector2i(x, y)), -1)


func test_paint_uses_a_valid_variant_of_the_correct_biome_per_cell():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()

	renderer.paint(tile_map_layer, chunk)

	var expected_variant_00 := renderer.variant_index_for_position(0, 0)
	var expected_variant_11 := renderer.variant_index_for_position(1, 1)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("grassland", expected_variant_00)
	)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(1, 1)),
		renderer.atlas_coords_for_biome("grassland", expected_variant_11)
	)


func test_paint_offsets_cells_by_the_given_origin():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()

	renderer.paint(tile_map_layer, chunk, Vector2i(100, 200))

	var expected_variant := renderer.variant_index_for_position(100, 200)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(100, 200)),
		renderer.atlas_coords_for_biome("grassland", expected_variant)
	)
	assert_eq(tile_map_layer.get_cell_source_id(Vector2i(0, 0)), -1)


func test_paint_uses_the_modification_tile_when_a_cell_has_one():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.modifications[Vector2i(0, 0)] = TerrainRenderer.EARTH_TILE_ID

	renderer.paint(tile_map_layer, chunk)

	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID)
	)


func test_paint_falls_back_to_the_biome_tile_when_a_cell_has_no_modification():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.modifications[Vector2i(0, 0)] = TerrainRenderer.EARTH_TILE_ID

	renderer.paint(tile_map_layer, chunk)

	var expected_variant := renderer.variant_index_for_position(1, 1)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(1, 1)),
		renderer.atlas_coords_for_biome("grassland", expected_variant)
	)


func test_erase_clears_a_previously_painted_region():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	renderer.paint(tile_map_layer, chunk, Vector2i(50, 50))

	renderer.erase(tile_map_layer, 2, Vector2i(50, 50))

	for y in chunk.height:
		for x in chunk.width:
			assert_eq(tile_map_layer.get_cell_source_id(Vector2i(50 + x, 50 + y)), -1)


# -- biome border blending (corner-aware, every differing pair) --------------

func test_dominant_blend_for_returns_the_partner_and_all_of_its_directions():
	# grassland cell with desert to the north AND east -> blend desert on both.
	var result := renderer.dominant_blend_for(
		"grassland", {Vector2i(0, -1): "desert", Vector2i(1, 0): "desert", Vector2i(-1, 0): "grassland"}
	)
	assert_eq(result.partner, "desert")
	assert_eq(result.directions.size(), 2)
	assert_true(result.directions.has(Vector2i(0, -1)))
	assert_true(result.directions.has(Vector2i(1, 0)))


func test_dominant_blend_for_returns_empty_when_no_neighbor_differs():
	var result := renderer.dominant_blend_for("forest", {Vector2i(-1, 0): "forest", Vector2i(1, 0): "forest"})
	assert_true(result.is_empty())


## Water is a special case: land is never allowed to blend toward ocean at
## all (unlike every other biome pair), because the shoreline transition now
## belongs entirely to the GPU WaterFx overlay (see water_shader.gd) -- a
## land-side dithered fringe here would visually fight the overlay's own
## shore-distance blending on the water side (the reported "shoreline is
## backwards" bug: two independent transition treatments on opposite sides
## of the same border).
func test_dominant_blend_for_never_blends_land_toward_ocean():
	var result := renderer.dominant_blend_for("grassland", {Vector2i(1, 0): "ocean"})
	assert_true(result.is_empty(), "land must not blend toward ocean -- the GPU overlay owns the shoreline")


func test_dominant_blend_for_picks_the_biome_covering_the_most_edges():
	# desert on two edges beats tundra on one -> desert dominates.
	var result := renderer.dominant_blend_for(
		"grassland", {Vector2i(0, -1): "desert", Vector2i(0, 1): "desert", Vector2i(1, 0): "tundra"}
	)
	assert_eq(result.partner, "desert")
	assert_eq(result.directions.size(), 2)


func test_atlas_coords_for_directional_blend_is_distinct_from_plain_biome_tiles():
	var blend_coords := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(0, -1)], 0)
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			assert_ne(blend_coords, renderer.atlas_coords_for_biome(biome_name, variant))


func test_atlas_coords_for_directional_blend_differs_by_direction_set():
	var north := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(0, -1)], 0)
	var north_east := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(0, -1), Vector2i(1, 0)], 0)
	assert_ne(north, north_east)


func test_atlas_coords_for_directional_blend_is_independent_of_direction_order():
	var a := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(0, -1), Vector2i(1, 0)], 0)
	var b := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(1, 0), Vector2i(0, -1)], 0)
	assert_eq(a, b)


func test_atlas_coords_for_directional_blend_differs_by_which_side_is_near():
	var forest_near := renderer.atlas_coords_for_directional_blend("forest", "grassland", [Vector2i(0, -1)], 0)
	var grassland_near := renderer.atlas_coords_for_directional_blend("grassland", "forest", [Vector2i(0, -1)], 0)
	assert_ne(forest_near, grassland_near)


func test_atlas_coords_for_directional_blend_is_a_created_tile_in_the_atlas():
	# Guards the grid layout: a many-direction, high-index blend must actually
	# be a real tile in the source, not off the edge of the texture.
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var coords := renderer.atlas_coords_for_directional_blend(
		"desert", "rainforest", [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)], TerrainRenderer.VARIANTS_PER_BIOME - 1
	)
	assert_true(source.has_tile(coords), "blend tile %s should exist in the atlas" % coords)


func _make_desert_corner_chunk() -> Chunk:
	# 2x2 where the top-left cell is grassland with desert to its east and
	# south -- a corner that must blend toward both neighbors at once.
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.4, 0.4, 0.4, 0.4])
	chunk.biome = PackedStringArray(["grassland", "desert", "desert", "grassland"])
	return chunk


func test_paint_blends_a_corner_toward_multiple_differing_neighbors():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_desert_corner_chunk()

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	# Cell (0,0) grassland: desert east (1,0) and desert south (0,1).
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_directional_blend("grassland", "desert", [Vector2i(1, 0), Vector2i(0, 1)], variant)
	)


## Only ONE side of a border renders a transition tile in general -- the
## higher-priority ("outer") biome fringes over its lower-priority neighbor,
## which stays a pure tile (both sides blending doubles the fringe into a
## mushy two-tile band). Ocean is the one exception: it never receives a
## blend from EITHER side -- land no longer dithers toward it either (see
## test_dominant_blend_for_never_blends_land_toward_ocean), because the
## shoreline transition belongs entirely to the GPU WaterFx overlay now, not
## the base Terrain layer. Both cells here must render as plain, unblended
## biome tiles.
func test_paint_never_blends_a_land_ocean_border_on_the_base_layer():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 1
	chunk.elevation = PackedFloat32Array([0.1, 0.4])
	chunk.biome = PackedStringArray(["ocean", "grassland"])

	renderer.paint(tile_map_layer, chunk)

	var ocean_variant := renderer.variant_index_for_position(0, 0)
	var grassland_variant := renderer.variant_index_for_position(1, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("ocean", ocean_variant),
		"the ocean side stays plain animated water on the base layer"
	)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(1, 0)),
		renderer.atlas_coords_for_biome("grassland", grassland_variant),
		"the grassland side stays plain too -- no land-side shore dithering anymore"
	)


## A non-water border still blends normally (only the higher-priority side
## fringes) -- the ocean carve-out above is specific to water, not a general
## regression in border blending.
func test_paint_still_blends_normal_land_borders():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 1
	chunk.elevation = PackedFloat32Array([0.4, 0.4])
	chunk.biome = PackedStringArray(["desert", "grassland"])

	renderer.paint(tile_map_layer, chunk)

	var desert_variant := renderer.variant_index_for_position(0, 0)
	var grassland_variant := renderer.variant_index_for_position(1, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("desert", desert_variant),
		"desert (lower-priority) stays plain"
	)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(1, 0)),
		renderer.atlas_coords_for_directional_blend("grassland", "desert", [Vector2i(-1, 0)], grassland_variant),
		"grassland (higher-priority) carries the transition"
	)


func test_dominant_blend_for_ignores_higher_priority_neighbors():
	# A grassland cell next to forest: forest outranks grassland, so the
	# grassland cell stays pure -- the forest cell is the one that fringes.
	var result := renderer.dominant_blend_for("grassland", {Vector2i(0, -1): "forest"})
	assert_true(result.is_empty(), "grassland must not blend toward higher-priority forest")

	var forest_result := renderer.dominant_blend_for("forest", {Vector2i(0, 1): "grassland"})
	assert_eq(forest_result.partner, "grassland")


# -- cross-chunk border blending (via a global neighbor lookup) ---------------

func _uniform_chunk(biome_name: String) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.4, 0.4, 0.4, 0.4])
	chunk.biome = PackedStringArray([biome_name, biome_name, biome_name, biome_name])
	return chunk


func test_paint_blends_a_chunk_edge_cell_toward_a_differing_out_of_chunk_neighbor():
	# A uniform grassland chunk painted with a lookup that says everything
	# outside the chunk is desert: the top-left cell must blend toward its
	# out-of-chunk north and west neighbors instead of hard-cutting at the
	# seam. (Not ocean here -- land never blends toward ocean at all, see
	# test_dominant_blend_for_never_blends_land_toward_ocean; this test is
	# about the cross-chunk lookup mechanism itself, which any differing
	# land biome exercises just as well.)
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _uniform_chunk("grassland")

	renderer.paint(tile_map_layer, chunk, Vector2i.ZERO, func(_gx: int, _gy: int) -> String: return "desert")

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_directional_blend(
			"grassland", "desert", [Vector2i(0, -1), Vector2i(-1, 0)], variant
		)
	)


func test_paint_does_not_blend_when_the_out_of_chunk_neighbor_matches():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _uniform_chunk("grassland")

	renderer.paint(tile_map_layer, chunk, Vector2i.ZERO, func(_gx: int, _gy: int) -> String: return "grassland")

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("grassland", variant)
	)


func test_paint_lookup_receives_global_not_local_coordinates():
	# Painting at an origin: the lookup for cell (0,0)'s north neighbor must be
	# asked about global (10, 9), not local (0, -1). We make the lookup return a
	# differing biome only at exactly that global coordinate.
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _uniform_chunk("grassland")

	var lookup := func(gx: int, gy: int) -> String:
		return "desert" if Vector2i(gx, gy) == Vector2i(10, 9) else "grassland"
	renderer.paint(tile_map_layer, chunk, Vector2i(10, 10), lookup)

	var variant := renderer.variant_index_for_position(10, 10)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(10, 10)),
		renderer.atlas_coords_for_directional_blend("grassland", "desert", [Vector2i(0, -1)], variant)
	)


func test_paint_without_a_lookup_still_ignores_out_of_chunk_neighbors():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _uniform_chunk("grassland")

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("grassland", variant)
	)
