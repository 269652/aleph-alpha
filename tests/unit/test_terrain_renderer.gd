extends GutTest

const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ProceduralStructureSprite = preload("res://src/rendering/procedural_structure_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainAtlasCache = preload("res://src/rendering/terrain_atlas_cache.gd")
const ProceduralTerrainSprite = preload("res://src/rendering/procedural_terrain_sprite.gd")

## Shared across every test in this file (see docs/concept/
## art_resolution.md#boot-performance): the first build_tile_set() call
## populates this cache, and every later call/test in the same run hits it --
## a real speedup for the suite, not just test isolation from the actual
## user:// cache. Cache-behavior-specific tests below use their own separate
## path so they can freely write fake/stale content without corrupting this
## shared one for every other test.
const SHARED_TEST_CACHE_PATH := "user://test_terrain_renderer_shared_cache.png"
const SHARED_TEST_VERSION_PATH := "user://test_terrain_renderer_shared_version.txt"

var renderer: TerrainRenderer
var tile_map_layer: TileMapLayer


func before_each():
	renderer = TerrainRenderer.new()
	renderer.atlas_cache_path = SHARED_TEST_CACHE_PATH
	renderer.atlas_version_path = SHARED_TEST_VERSION_PATH
	tile_map_layer = TileMapLayer.new()


func after_each():
	tile_map_layer.free()


func after_all():
	var cache := TerrainAtlasCache.new()
	cache.wipe(SHARED_TEST_CACHE_PATH, SHARED_TEST_VERSION_PATH)


# -- world tile size vs art resolution (docs/concept/art_resolution.md) ------
# TILE_SIZE is how many WORLD UNITS one tile occupies -- every gameplay
# system (player movement, spawn math, fish/creature positioning, chunk
# streaming) is built on it, and the player's own 12-unit body is
# proportioned against it. ART_TILE_SIZE is how many PIXELS of art are
# painted per tile. Conflating them (the resolution pass's first attempt
# simply bumped TILE_SIZE 16->64) made every tile occupy 4x the world
# footprint: "water squares are gigantic compared to the player". The tile
# LAYERS render scaled by LAYER_SCALE instead, so a tile's on-screen/world
# footprint stays exactly what it always was while carrying 16x the art.

func test_world_tile_size_is_unchanged_by_the_art_resolution_pass():
	assert_eq(TerrainRenderer.TILE_SIZE, 16)


## Derived from ArtResolution rather than hardcoded: this asserted a literal
## 64 (a 4x multiplier) and went stale when the multiplier settled at 2,
## failing ever since while saying nothing useful about the invariant it
## actually cares about -- that terrain and sprites agree on how much detail
## a world unit carries.
func test_art_tile_size_follows_the_shared_detail_multiplier():
	assert_eq(
		TerrainRenderer.ART_TILE_SIZE,
		TerrainRenderer.TILE_SIZE * ArtResolution.DETAIL_MULTIPLIER
	)


## The invariant that keeps art resolution and world footprint independent:
## a layer drawing ART_TILE_SIZE-pixel tiles, scaled by LAYER_SCALE, spans
## exactly TILE_SIZE world units per tile.
func test_layer_scale_maps_art_pixels_back_onto_the_world_tile_footprint():
	assert_almost_eq(TerrainRenderer.LAYER_SCALE * TerrainRenderer.ART_TILE_SIZE, float(TerrainRenderer.TILE_SIZE), 0.0001)


func test_tile_set_texture_cells_are_art_resolution_sized():
	var tile_set := renderer.build_tile_set()
	assert_eq(tile_set.tile_size, Vector2i(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE))
	var source := tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(source.texture_region_size, Vector2i(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE))


# -- atlas disk cache (see docs/concept/art_resolution.md#boot-performance) --
# build_tile_set()'s pixel-painting is fully deterministic and expensive
# (thousands of tiles at the 4x resolution -- ~13.5s measured), so it's
# cached to disk after the first build and reloaded on every later call
# instead of regenerating. These tests use their own dedicated path,
# separate from SHARED_TEST_CACHE_PATH, so they can freely write fake/stale
# content without corrupting the cache every other test in this file relies
# on for speed.

const CACHE_BEHAVIOR_PATH := "user://test_terrain_renderer_cache_behavior.png"
const CACHE_BEHAVIOR_VERSION_PATH := "user://test_terrain_renderer_cache_behavior_version.txt"


func _wipe_cache_behavior_files():
	TerrainAtlasCache.new().wipe(CACHE_BEHAVIOR_PATH, CACHE_BEHAVIOR_VERSION_PATH)


## build_tile_set() still creates every biome/structure/blend tile's
## TileSetAtlasSource entry regardless of cache state (only the pixel
## painting is skipped) -- so a fake cached image must be the SAME full
## atlas size real generation would have produced, or Godot logs
## "room_for_tile" errors for every grid cell beyond the fake image's
## bounds. Mirrors build_tile_set()'s own size math exactly.
func _full_atlas_size() -> Vector2i:
	var total_cells: int = renderer._land_corner_base_linear() + renderer._corner_family_size()
	var rows := int(ceil(float(total_cells) / TerrainRenderer.ATLAS_COLUMNS))
	var art := TerrainRenderer.ART_TILE_SIZE
	return Vector2i(TerrainRenderer.ATLAS_COLUMNS * art, rows * art)


## Proves a valid cache is actually READ (not just present): a fake, easily
## identifiable image saved under the renderer's own current ATLAS_VERSION
## should be exactly what build_tile_set()'s resulting texture shows --
## real generated content is never a uniform solid color.
func test_build_tile_set_uses_a_valid_cache_instead_of_regenerating():
	_wipe_cache_behavior_files()
	renderer.atlas_cache_path = CACHE_BEHAVIOR_PATH
	renderer.atlas_version_path = CACHE_BEHAVIOR_VERSION_PATH

	var size := _full_atlas_size()
	var fake := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	fake.fill(Color(1.0, 0.0, 1.0, 1.0))  # solid magenta -- never produced by real generation
	TerrainAtlasCache.new().save(fake, TerrainRenderer.ATLAS_VERSION, CACHE_BEHAVIOR_PATH, CACHE_BEHAVIOR_VERSION_PATH)

	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image := source.texture.get_image()
	assert_eq(image.get_pixel(0, 0), Color(1.0, 0.0, 1.0, 1.0))
	_wipe_cache_behavior_files()


## No cache present -> build_tile_set() must generate fresh AND leave a
## valid cache behind for next time.
func test_build_tile_set_writes_a_fresh_cache_when_none_exists():
	_wipe_cache_behavior_files()
	renderer.atlas_cache_path = CACHE_BEHAVIOR_PATH
	renderer.atlas_version_path = CACHE_BEHAVIOR_VERSION_PATH

	renderer.build_tile_set()

	assert_true(
		TerrainAtlasCache.new().has_valid_cache(
			TerrainRenderer.ATLAS_VERSION, CACHE_BEHAVIOR_PATH, CACHE_BEHAVIOR_VERSION_PATH
		)
	)
	_wipe_cache_behavior_files()


## A cache saved under an older/different version must never be reused --
## the whole point of versioning it at all (see TerrainAtlasCache).
func test_build_tile_set_ignores_a_stale_version_cache():
	_wipe_cache_behavior_files()
	renderer.atlas_cache_path = CACHE_BEHAVIOR_PATH
	renderer.atlas_version_path = CACHE_BEHAVIOR_VERSION_PATH

	var size := _full_atlas_size()
	var fake := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	fake.fill(Color(1.0, 0.0, 1.0, 1.0))
	TerrainAtlasCache.new().save(fake, "a_stale_version_string", CACHE_BEHAVIOR_PATH, CACHE_BEHAVIOR_VERSION_PATH)

	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image := source.texture.get_image()
	assert_ne(image.get_pixel(0, 0), Color(1.0, 0.0, 1.0, 1.0))
	_wipe_cache_behavior_files()


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
		+ BuildingPiece.PIECE_IDS.size()
		+ n * (n - 1) * TerrainRenderer.DIRECTION_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
		# Corner-carve tiles, TWO families (see corner_direction_for): convex
		# (ocean-owning) and concave (land-owning) -- one per (biome ordinal
		# slot incl. ocean's own unused slot) x every non-empty subset of the
		# 4 diagonal corners (CORNER_MASK_COUNT, a cell can qualify on more
		# than one corner at once) x BLEND_VARIANTS, x2 for the two families.
		+ 2 * n * TerrainRenderer.CORNER_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
	)
	assert_eq(source.get_tiles_count(), expected)


## Isolates the growth claim on its own: removing the structure tiles from
## the total should land exactly on the pre-structure-tiles tile count (the
## formula the test above used before campfire/furnace got their own art).
func test_build_tile_set_total_tile_count_grows_by_exactly_one_tile_per_structure_id():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var n := BiomeClassifier.KNOWN_BIOMES.size()
	var tile_count_without_structures_or_pieces := (
		n * TerrainRenderer.VARIANTS_PER_BIOME + 1
		+ n * (n - 1) * TerrainRenderer.DIRECTION_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
		# Corner-carve tiles, TWO families (see corner_direction_for): convex
		# (ocean-owning) and concave (land-owning) -- one per (biome ordinal
		# slot incl. ocean's own unused slot) x every non-empty subset of the
		# 4 diagonal corners (CORNER_MASK_COUNT, a cell can qualify on more
		# than one corner at once) x BLEND_VARIANTS, x2 for the two families.
		+ 2 * n * TerrainRenderer.CORNER_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
	)
	assert_eq(
		source.get_tiles_count() - tile_count_without_structures_or_pieces - BuildingPiece.PIECE_IDS.size(),
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


# -- building pieces (see docs/concept/building.md, BuildingPiece.PIECE_IDS) --
# Same shape as the campfire/furnace structure tiles above: each of the 10
# piece ids (wood/stone x floor/wall/door/window/roof) gets its own reserved
# atlas slot, right after the structure tiles.

func test_atlas_coords_for_every_building_piece_is_distinct_from_earth_structures_and_biomes():
	for piece_id in BuildingPiece.PIECE_IDS:
		var coords := renderer.atlas_coords_for_modification(piece_id)
		assert_ne(coords, renderer.atlas_coords_for_modification(TerrainRenderer.EARTH_TILE_ID), piece_id)
		assert_ne(coords, renderer.atlas_coords_for_modification("campfire"), piece_id)
		assert_ne(coords, renderer.atlas_coords_for_modification("furnace"), piece_id)
		for biome_name in BiomeClassifier.KNOWN_BIOMES:
			assert_ne(coords, renderer.atlas_coords_for_biome(biome_name, 0), piece_id)


func test_atlas_coords_for_every_building_piece_is_distinct_from_every_other():
	for i in BuildingPiece.PIECE_IDS.size():
		for j in range(i + 1, BuildingPiece.PIECE_IDS.size()):
			var a: String = BuildingPiece.PIECE_IDS[i]
			var b: String = BuildingPiece.PIECE_IDS[j]
			assert_ne(
				renderer.atlas_coords_for_modification(a), renderer.atlas_coords_for_modification(b),
				"%s vs %s" % [a, b]
			)


func test_build_tile_set_total_tile_count_grows_by_exactly_one_tile_per_building_piece():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var n := BiomeClassifier.KNOWN_BIOMES.size()
	var tile_count_without_pieces := (
		n * TerrainRenderer.VARIANTS_PER_BIOME + 1 + ProceduralStructureSprite.STRUCTURE_IDS.size()
		+ n * (n - 1) * TerrainRenderer.DIRECTION_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
		# Corner-carve tiles, TWO families (see corner_direction_for): convex
		# (ocean-owning) and concave (land-owning) -- one per (biome ordinal
		# slot incl. ocean's own unused slot) x every non-empty subset of the
		# 4 diagonal corners (CORNER_MASK_COUNT, a cell can qualify on more
		# than one corner at once) x BLEND_VARIANTS, x2 for the two families.
		+ 2 * n * TerrainRenderer.CORNER_MASK_COUNT * TerrainRenderer.BLEND_VARIANTS
	)
	assert_eq(source.get_tiles_count() - tile_count_without_pieces, BuildingPiece.PIECE_IDS.size())


func test_building_piece_tiles_stay_static_single_frame():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for piece_id in BuildingPiece.PIECE_IDS:
		assert_eq(
			source.get_tile_animation_frames_count(renderer.atlas_coords_for_modification(piece_id)), 1, piece_id
		)


## More variation per biome: bumped from 4 to 6 to 25, then settled at 9 --
## the terrain art pipeline originally targeted a full 5x5/25-variant
## illustrated sheet per biome (see IllustratedTerrainSprite/docs/art/
## ai_sprite_prompts.md's terrain section), but real generation only
## reliably held a square-cell grid at 3x3. Every registered land-biome
## sheet is a real 3x3/9-variant grid, so 9 lets every baked atlas slot map
## to a genuinely distinct illustrated tile with none wasted on duplicates.
func test_variants_per_biome_matches_a_full_3x3_illustrated_sheet():
	assert_eq(TerrainRenderer.VARIANTS_PER_BIOME, 9)


# -- illustrated art plumbing (see IllustratedTerrainSprite) -----------------
#
# This pins the WIRING with a fake stand-in rather than exercising the real
# registered sheets (see test_illustrated_terrain_sprite.gd for that): when
# the illustrated source reports a biome as covered, its frame wins (reused
# across every animation frame, since an illustrated tile has no real
# animation of its own); when it doesn't, the procedural generator still
# runs exactly as it does today. The same has_X()-gated fallback
# test_stone_renderer.gd uses for IllustratedStoneSprite.

## Keyed by biome name so a test can register more than one biome at once
## (needed for blend/corner tests, which composite TWO biomes' images
## together).
class _FakeIllustratedTerrain:
	var canned_images: Dictionary = {}  # biome_name -> Image

	func has_variants(biome_name: String) -> bool:
		return canned_images.has(biome_name)

	func frame_for(biome_name: String, _variant: int) -> Image:
		return canned_images.get(biome_name)

	func register(biome_name: String, image: Image) -> void:
		canned_images[biome_name] = image


func test_biome_frame_image_uses_illustrated_art_when_the_biome_has_a_sheet():
	var fake := _FakeIllustratedTerrain.new()
	var canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fake.register("grassland", canned)
	renderer._illustrated_terrain = fake
	assert_eq(renderer._biome_frame_image("grassland", 3, 1), canned)


func test_biome_frame_image_falls_back_to_procedural_when_the_biome_has_no_sheet():
	var fake := _FakeIllustratedTerrain.new()
	var canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fake.register("grassland", canned)  # forest is NOT registered
	renderer._illustrated_terrain = fake
	var image: Image = renderer._biome_frame_image("forest", 3, 1)
	assert_not_null(image)
	assert_ne(image, canned)


func test_biome_frame_image_reuses_the_same_illustrated_frame_across_every_animation_frame():
	var fake := _FakeIllustratedTerrain.new()
	var canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	fake.register("desert", canned)
	renderer._illustrated_terrain = fake
	for frame in TerrainRenderer.FRAME_COUNT:
		assert_eq(renderer._biome_frame_image("desert", 2, frame), canned)


## Real end-to-end integration, no fake: a fresh renderer's OWN
## IllustratedTerrainSprite instance now has real sheets registered for
## every land biome (see assets/sprites/terrain/*.png, each a real 3x3
## variant grid) -- so a real land biome should draw from its own
## illustrated sheet rather than the procedural fallback. Ocean (no sheet,
## by design) still falls all the way through to procedural.
func test_a_real_land_biome_draws_from_its_registered_illustrated_sheet():
	var image := renderer._biome_frame_image("grassland", 3, 1)
	var expected: Image = renderer._illustrated_terrain.frame_for("grassland", 3)
	assert_not_null(expected, "the real grassland sheet should have produced a frame")
	assert_eq(image, expected)


func test_ocean_still_falls_back_to_procedural():
	var image := renderer._biome_frame_image("ocean", 3, 1)
	assert_not_null(image)
	assert_false(renderer._illustrated_terrain.has_variants("ocean"))


# -- blending real source images together, not flat synthesized color -------
#
# A border between two ILLUSTRATED biomes must dither their real art
# together, not ProceduralTerrainSprite's flat-color-plus-speckle blend
# (reported: illustrated ground next to a flat/procedural-looking border
# read as visibly inconsistent).

func test_blend_image_uses_illustrated_art_for_both_sides_when_both_are_registered():
	var fake := _FakeIllustratedTerrain.new()
	var near_canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	near_canned.fill(Color(1, 0, 0, 1))
	var far_canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	far_canned.fill(Color(0, 0, 1, 1))
	fake.register("forest", near_canned)
	fake.register("grassland", far_canned)
	renderer._illustrated_terrain = fake

	var image := renderer._blend_image("forest", "grassland", [Vector2i(0, -1)], 0)
	# Top row is entirely "far" (grassland) under the blend geometry -- see
	# generate_multi_directional_blend_image_from's own outer-quarter
	# behavior at t=1 (a whole-tile-solid-color source makes this trivial
	# to check without needing to know exactly where the band starts).
	assert_true(image.get_pixel(0, 0).is_equal_approx(Color(0, 0, 1, 1)))


## Falls back to procedural source images, but STILL composites at the real
## final size (ART_TILE_SIZE) rather than ProceduralTerrainSprite.SIZE --
## _normalized_for_compositing runs regardless of where the source images
## came from, so even an all-procedural blend now gets composited once at
## its real final resolution instead of _blit_tile downscaling the
## composite a second time afterward (the same lesson as illustrated
## tiles, just no longer illustrated-specific).
func test_blend_image_falls_back_to_procedural_when_neither_side_has_a_sheet():
	var fake := _FakeIllustratedTerrain.new()  # nothing registered
	renderer._illustrated_terrain = fake
	var image := renderer._blend_image("forest", "grassland", [Vector2i(0, -1)], 0)
	assert_not_null(image)
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE)


func test_corner_image_uses_illustrated_art_for_both_sides_when_both_are_registered():
	var fake := _FakeIllustratedTerrain.new()
	var own_canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	own_canned.fill(Color(1, 0, 0, 1))
	var other_canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	other_canned.fill(Color(0, 0, 1, 1))
	fake.register("mountain", own_canned)
	fake.register("tundra", other_canned)
	renderer._illustrated_terrain = fake

	var image := renderer._corner_image("mountain", "tundra", [Vector2i(1, -1)], 0)
	# Both fakes are 4x4 -- _normalized_for_compositing upscales them to the
	# real ART_TILE_SIZE before carving, so the named corner is at the
	# OUTPUT's own top-right pixel, not the fakes' original 4x4 one.
	var last := TerrainRenderer.ART_TILE_SIZE - 1
	assert_true(
		image.get_pixel(last, 0).is_equal_approx(Color(0, 0, 1, 1)),
		"the named (NE) corner should carve to the other biome's illustrated art"
	)
	assert_true(
		image.get_pixel(0, last).is_equal_approx(Color(1, 0, 0, 1)),
		"the opposite (SW) corner should stay the own biome's illustrated art"
	)


## The real production case: a corner ALWAYS involves ocean (still
## procedural, ProceduralTerrainSprite.SIZE) on one side and a land biome
## (illustrated, a different size) on the other -- confirms the size
## mismatch is normalized rather than crashing or silently misaligning.
func test_corner_image_normalizes_a_size_mismatch_between_illustrated_and_procedural_sides():
	var fake := _FakeIllustratedTerrain.new()
	var mountain_canned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	mountain_canned.fill(Color(1, 0, 0, 1))
	fake.register("mountain", mountain_canned)  # ocean is NOT registered -> procedural, SIZE-sized
	renderer._illustrated_terrain = fake

	var image := renderer._corner_image("mountain", "ocean", [Vector2i(1, -1)], 0)
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE)


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
	# Atlas pixel math is in ART pixels, not world units (see
	# TerrainRenderer.ART_TILE_SIZE) -- sampling with TILE_SIZE landed inside
	# the wrong atlas cell entirely once the two diverged.
	var art := TerrainRenderer.ART_TILE_SIZE
	var origin := Vector2i(coords.x * art, coords.y * art)
	var edge_pixel := image.get_pixel(origin.x + art / 2, origin.y)
	var far_pixel := image.get_pixel(origin.x + art / 2, origin.y + art - 1)
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
	# Strided by ART_TILE_SIZE, which is what the atlas is actually laid out
	# in -- this sampled at TILE_SIZE and so read the wrong pixel (and a
	# neighbouring tile's) once art tiles stopped being world-tile-sized.
	var ring1_value := image.get_pixel(ring1_coords.x * TerrainRenderer.ART_TILE_SIZE, 0).r
	var ring2_value := image.get_pixel(ring2_coords.x * TerrainRenderer.ART_TILE_SIZE, 0).r
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


# -- roof layer (see Chunk.roof_modifications, docs/concept/building.md) ----
#
# A roof shares its CELL with the floor beneath it, so it can't live in the
# same `modifications` dict (one tile id per cell). It paints onto its own
# TileMapLayer instead, and that layer's whole point is that it can be
# selectively hidden per-cell while the player is indoors under it.

func test_paint_roofs_sets_a_cell_for_every_roof_modification():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.roof_modifications[Vector2i(0, 0)] = "wood_roof"
	chunk.roof_modifications[Vector2i(1, 1)] = "stone_roof"

	renderer.paint_roofs(tile_map_layer, chunk)

	assert_eq(tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)), renderer.atlas_coords_for_modification("wood_roof"))
	assert_eq(tile_map_layer.get_cell_atlas_coords(Vector2i(1, 1)), renderer.atlas_coords_for_modification("stone_roof"))


func test_paint_roofs_only_touches_cells_with_a_roof_modification():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.roof_modifications[Vector2i(0, 0)] = "wood_roof"

	renderer.paint_roofs(tile_map_layer, chunk)

	assert_eq(tile_map_layer.get_cell_source_id(Vector2i(1, 1)), -1, "a cell with no roof stays untouched")


func test_paint_roofs_offsets_cells_by_the_given_origin():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.roof_modifications[Vector2i(0, 0)] = "wood_roof"

	renderer.paint_roofs(tile_map_layer, chunk, Vector2i(100, 200))

	assert_eq(tile_map_layer.get_cell_atlas_coords(Vector2i(100, 200)), renderer.atlas_coords_for_modification("wood_roof"))
	assert_eq(tile_map_layer.get_cell_source_id(Vector2i(0, 0)), -1)


## The whole reason this layer exists: a roof cell listed in `hidden_cells`
## erases instead of painting -- so the player can see inside while standing
## under it -- and a cell that WAS hidden but no longer is gets repainted
## back, rather than staying erased forever.
func test_paint_roofs_erases_hidden_cells_instead_of_painting_them():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.roof_modifications[Vector2i(0, 0)] = "wood_roof"
	chunk.roof_modifications[Vector2i(1, 1)] = "wood_roof"

	renderer.paint_roofs(tile_map_layer, chunk, Vector2i.ZERO, {Vector2i(0, 0): true})

	assert_eq(tile_map_layer.get_cell_source_id(Vector2i(0, 0)), -1, "hidden cell should be erased")
	assert_ne(tile_map_layer.get_cell_source_id(Vector2i(1, 1)), -1, "cell not in hidden_cells should still paint")


func test_paint_roofs_restores_a_cell_that_is_no_longer_hidden():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := _make_chunk()
	chunk.roof_modifications[Vector2i(0, 0)] = "wood_roof"

	renderer.paint_roofs(tile_map_layer, chunk, Vector2i.ZERO, {Vector2i(0, 0): true})
	renderer.paint_roofs(tile_map_layer, chunk, Vector2i.ZERO, {})

	assert_ne(tile_map_layer.get_cell_source_id(Vector2i(0, 0)), -1, "should repaint once no longer hidden")


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


# -- rounded shoreline corners (real base-layer tile geometry) ---------------
#
# The GPU WaterFx overlay (build_water_overlay_tile_set/water_shader.gd) is
# a translucent layer drawn ON TOP of this fully-opaque base layer -- it can
# fade alpha, but it can never change the base tile's own hard-edged square
# silhouette underneath it. An ocean cell with land on two PERPENDICULAR
# cardinal sides (e.g. north AND east) sits at a real geometric right-angle
# corner of the tile grid; corner_direction_for/atlas_coords_for_corner
# carve that specific corner with a rounded quarter-circle into the other
# biome's own texture, directly in the base layer (see
# ProceduralTerrainSprite.generate_corner_image), instead of leaving a hard
# square notch (reported: tile borders read "square" instead of rounded).
#
# A real, irregular (non-rectangular) coastline produces this corner shape
# on BOTH sides of the shoreline, not just the water one -- an ocean cell
# with land poking into it (CONVEX, a peninsula tip) and a land cell with
# water poking into it (CONCAVE, a bay tip) are both real 90-degree turns
# that need carving. A first pass only ever checked the ocean side, which
# left the majority of corners on an irregular lake/coastline still hard
# right angles (reported directly, with an in-game screenshot: "a couple of
# corners... show a visible small rounded step-down, but the large majority
# of corners... are still hard right angles").

func test_corner_direction_for_finds_a_convex_corner_ocean_cell_with_land_on_two_sides():
	# Ocean with land north AND east (same biome on both) -> a real corner,
	# rounded toward the NE, carved into the land biome.
	var result := renderer.corner_direction_for(
		"ocean", {Vector2i(0, -1): "grassland", Vector2i(1, 0): "grassland", Vector2i(-1, 0): "ocean"}
	)
	assert_eq(result.partner, "grassland")
	assert_eq(result.directions, [Vector2i(1, -1)])


## The concave mirror image, previously entirely unhandled: a LAND cell with
## OCEAN on two perpendicular sides (a bay/inlet tip narrowing the land) is
## just as real a 90-degree corner as the water-side case above, and must
## carve toward ocean.
func test_corner_direction_for_finds_a_concave_corner_land_cell_with_ocean_on_two_sides():
	var result := renderer.corner_direction_for(
		"grassland", {Vector2i(0, -1): "ocean", Vector2i(1, 0): "ocean", Vector2i(-1, 0): "grassland"}
	)
	assert_eq(result.partner, "ocean")
	assert_eq(result.directions, [Vector2i(1, -1)])


## Real coastlines routinely have two DIFFERENT land biomes flanking the
## same water corner (their own border rarely lines up with a shore corner)
## -- this must still carve, not bail out, toward whichever neighbor
## dominates BLEND_PRIORITY (same tie-break convention as dominant_blend_for).
func test_corner_direction_for_still_carves_when_the_two_flanking_land_biomes_differ():
	var result := renderer.corner_direction_for(
		"ocean", {Vector2i(0, -1): "grassland", Vector2i(1, 0): "desert"}
	)
	assert_false(result.is_empty(), "a mixed-biome corner is still a real corner and must carve")
	assert_eq(result.partner, "grassland", "grassland (priority 3) should dominate desert (priority 1)")
	assert_eq(result.directions, [Vector2i(1, -1)])


func test_corner_direction_for_is_empty_for_a_straight_shore():
	# Only one land side -- a plain straight edge, not a corner.
	var result := renderer.corner_direction_for("ocean", {Vector2i(0, -1): "grassland"})
	assert_true(result.is_empty())


func test_corner_direction_for_is_empty_for_opposite_sides():
	# North and south are not perpendicular -- no corner exists between them.
	var result := renderer.corner_direction_for(
		"ocean", {Vector2i(0, -1): "grassland", Vector2i(0, 1): "grassland"}
	)
	assert_true(result.is_empty())


## A land cell with only one ocean-flanking side (no perpendicular partner)
## stays a plain straight shore too -- mirrors the ocean-side straight-shore
## case above.
func test_corner_direction_for_is_empty_for_a_land_cell_with_only_one_ocean_side():
	var result := renderer.corner_direction_for("grassland", {Vector2i(0, -1): "ocean"})
	assert_true(result.is_empty())


## A cell can qualify on more than one corner at once -- measured directly
## against real generated chunks: 859 of 3355 real corner cells qualify on
## more than one corner simultaneously (4522 total qualifying corner-
## instances). A single-tile-wide spit (land with ocean on three sides) has
## TWO simultaneous qualifying corners. An earlier version of this function
## returned only the FIRST direction found via an early `return`, silently
## dropping the rest -- exactly why some corners on a real coastline carved
## while others on the same tile stayed hard right angles (reported: "still
## not giving every corner a border radius"). Both corners must now be
## returned together.
func test_corner_direction_for_returns_every_qualifying_corner_on_a_land_spit():
	# Land cell with ocean north, ocean east, grassland (own biome) west --
	# NE and SE both qualify (only west, not south, is missing/land).
	var result := renderer.corner_direction_for(
		"grassland",
		{Vector2i(0, -1): "ocean", Vector2i(1, 0): "ocean", Vector2i(0, 1): "ocean", Vector2i(-1, 0): "grassland"}
	)
	assert_eq(result.partner, "ocean")
	assert_eq(result.directions.size(), 2)
	assert_true(result.directions.has(Vector2i(1, -1)), "NE (north+east both ocean) should qualify")
	assert_true(result.directions.has(Vector2i(1, 1)), "SE (south+east both ocean) should qualify")


## The maximal real case: a lone one-tile pond/island qualifies on all FOUR
## corners simultaneously (every cardinal neighbor differs).
func test_corner_direction_for_returns_all_four_corners_for_an_isolated_water_tile():
	var result := renderer.corner_direction_for(
		"ocean",
		{
			Vector2i(0, -1): "grassland", Vector2i(0, 1): "grassland",
			Vector2i(-1, 0): "grassland", Vector2i(1, 0): "grassland",
		}
	)
	assert_eq(result.partner, "grassland")
	assert_eq(result.directions.size(), 4)


func test_atlas_coords_for_corner_is_distinct_from_plain_and_blend_tiles():
	var corner_coords := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	for biome_name in BiomeClassifier.KNOWN_BIOMES:
		for variant in TerrainRenderer.VARIANTS_PER_BIOME:
			assert_ne(corner_coords, renderer.atlas_coords_for_biome(biome_name, variant))
	assert_ne(corner_coords, renderer.atlas_coords_for_directional_blend("ocean", "grassland", [Vector2i(0, -1)], 0))


func test_atlas_coords_for_corner_differs_by_direction():
	var ne := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	var sw := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(-1, 1)], 0)
	assert_ne(ne, sw)


func test_atlas_coords_for_corner_differs_by_partner_biome():
	var grassland := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	var desert := renderer.atlas_coords_for_corner("ocean", "desert", [Vector2i(1, -1)], 0)
	assert_ne(grassland, desert)


## A single-direction tile must be a genuinely different atlas cell from a
## multi-direction one covering that same direction -- otherwise a lone
## corner and a two-or-four-corner tile would collide.
func test_atlas_coords_for_corner_differs_by_direction_set():
	var single := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	var multi := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1), Vector2i(1, 1)], 0)
	assert_ne(single, multi)


func test_atlas_coords_for_corner_is_independent_of_direction_order():
	var a := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1), Vector2i(1, 1)], 0)
	var b := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, 1), Vector2i(1, -1)], 0)
	assert_eq(a, b)


## The concave (land-owning) family must occupy genuinely separate atlas
## cells from the convex (ocean-owning) one -- otherwise a bay tile and a
## peninsula tile carved with the same biome/direction/variant would
## silently collide and overwrite each other in the atlas.
func test_atlas_coords_for_corner_differs_by_which_side_owns_the_tile():
	var convex := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	var concave := renderer.atlas_coords_for_corner("grassland", "ocean", [Vector2i(1, -1)], 0)
	assert_ne(convex, concave)


func test_atlas_coords_for_corner_is_a_created_tile_in_the_atlas():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var convex_coords := renderer.atlas_coords_for_corner(
		"ocean", "mountain", [Vector2i(-1, -1)], TerrainRenderer.VARIANTS_PER_BIOME - 1
	)
	assert_true(source.has_tile(convex_coords), "convex corner tile %s should exist in the atlas" % convex_coords)
	var concave_coords := renderer.atlas_coords_for_corner(
		"mountain", "ocean", [Vector2i(-1, -1)], TerrainRenderer.VARIANTS_PER_BIOME - 1
	)
	assert_true(source.has_tile(concave_coords), "concave corner tile %s should exist in the atlas" % concave_coords)
	# All four corners at once (the isolated-pond case) must exist too.
	var all_four_coords := renderer.atlas_coords_for_corner(
		"ocean", "mountain", ProceduralTerrainSprite.CORNER_DIRECTIONS, TerrainRenderer.VARIANTS_PER_BIOME - 1
	)
	assert_true(source.has_tile(all_four_coords), "all-four-corner tile %s should exist in the atlas" % all_four_coords)


func test_paint_carves_a_rounded_convex_corner_for_an_ocean_cell_touching_land_on_two_perpendicular_sides():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.1, 0.4, 0.4, 0.4])
	# (0,0) ocean, with grassland to its east (1,0) and south (0,1) -> a
	# real corner rounded toward the south-east.
	chunk.biome = PackedStringArray(["ocean", "grassland", "grassland", "grassland"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, 1)], variant)
	)


## The concave mirror: a LAND cell with ocean on two perpendicular sides (a
## bay tip) must carve too -- previously always fell through to the plain
## grassland tile since corner_direction_for only ever checked ocean cells.
func test_paint_carves_a_rounded_concave_corner_for_a_land_cell_touching_ocean_on_two_perpendicular_sides():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.4, 0.1, 0.1, 0.1])
	# (0,0) grassland, with ocean to its east (1,0) and south (0,1) -> a bay
	# tip carved toward the south-east.
	chunk.biome = PackedStringArray(["grassland", "ocean", "ocean", "ocean"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_corner("grassland", "ocean", [Vector2i(1, 1)], variant)
	)


## Mixed land biomes flanking the same water corner (their border doesn't
## line up with the shore) must still carve, per corner_direction_for's own
## dominance tie-break.
func test_paint_carves_a_convex_corner_toward_the_dominant_biome_when_flanking_land_biomes_differ():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.1, 0.4, 0.4, 0.4])
	# (0,0) ocean, grassland east (1,0), desert south (0,1) -- grassland
	# (priority 3) dominates desert (priority 1).
	chunk.biome = PackedStringArray(["ocean", "grassland", "desert", "desert"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, 1)], variant)
	)


## A cell qualifying on multiple corners at once (a land spit with ocean on
## three sides) must have paint() actually carve BOTH corners on that same
## tile, not just one -- the real-world case measured to be missing before
## this pass (859 of 3355 real corner cells).
func test_paint_carves_multiple_corners_on_the_same_tile_for_a_land_spit():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 3
	chunk.elevation = PackedFloat32Array([0.1, 0.1, 0.4, 0.1, 0.1, 0.1])
	# Column x=0 is the spit: (0,1) grassland has ocean north (0,0), east
	# (1,1), AND south (0,2) -- a real single-tile-wide land spit poking
	# into the water, with two simultaneous qualifying corners (NE and SE).
	chunk.biome = PackedStringArray(["ocean", "ocean", "grassland", "ocean", "ocean", "ocean"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 1)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 1)),
		renderer.atlas_coords_for_corner("grassland", "ocean", [Vector2i(1, -1), Vector2i(1, 1)], variant),
		"both real corners of the land spit should be carved on the same painted tile, not just one"
	)


## The check every earlier corner test was missing: those all compared an
## atlas COORDINATE against atlas_coords_for_corner(), but both sides come
## from the same _corner_linear math -- self-consistent, and blind to what
## PIXELS are actually baked at that coordinate. This reads the real built
## atlas texture and asserts all four corners of an isolated-pond tile are
## genuinely the partner biome's color.
##
## Caught a real, invisible-until-now bug: ProceduralTerrainSprite generates
## SIZE (64px) tiles but ART_TILE_SIZE is 32, and _blit_tile blitted a
## Rect2i(0, 0, ART_TILE_SIZE, ART_TILE_SIZE) source region -- i.e. it
## CROPPED every generated terrain tile to its top-left quadrant. Three of
## an isolated pond's four carved corners were simply thrown away before
## ever reaching the atlas (only the NW one survived), which is why the
## in-game pond still read as a hard square no matter how correct the carve
## logic was (reported: isolated single-tile ponds "rendering as perfect
## hard squares"). It silently degraded every other terrain tile too --
## blend gradients, grass blades, moss -- all showing only their top-left
## quarter.
func test_baked_atlas_pixels_for_an_isolated_pond_are_carved_on_all_four_corners():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()

	var all_four: Array = ProceduralTerrainSprite.CORNER_DIRECTIONS
	var coords := renderer.atlas_coords_for_corner("ocean", "grassland", all_four, 0)
	var art := TerrainRenderer.ART_TILE_SIZE
	var origin := Vector2i(coords.x * art, coords.y * art)
	var tile := image.get_region(Rect2i(origin, Vector2i(art, art)))

	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	var ocean: Color = ProceduralTerrainSprite.BASE_COLORS["ocean"]
	for point in [Vector2i(0, 0), Vector2i(art - 1, 0), Vector2i(0, art - 1), Vector2i(art - 1, art - 1)]:
		var pixel := tile.get_pixel(point.x, point.y)
		assert_lt(
			_rgb_distance(pixel, grassland), _rgb_distance(pixel, ocean),
			"baked corner pixel %s of an isolated pond should read grassland (carved), not ocean" % point
		)

	# The tile's center must still be plain water -- the carve is corners only.
	var center := tile.get_pixel(art / 2, art / 2)
	assert_lt(
		_rgb_distance(center, ocean), _rgb_distance(center, grassland),
		"the pond tile's center should still read as water"
	)


## The invariant the bug above violated: whatever a generator's own SIZE is,
## the tile that lands in the atlas must represent the WHOLE generated tile,
## never a cropped sub-region of it. Pinned directly so a future
## DETAIL_MULTIPLIER/SIZE divergence can't silently start cropping art again.
func test_baked_tiles_represent_the_whole_generated_tile_not_a_cropped_corner():
	var tile_set := renderer.build_tile_set()
	var source := tile_set.get_source(0) as TileSetAtlasSource
	var image: Image = source.texture.get_image()
	var art := TerrainRenderer.ART_TILE_SIZE

	# A single-direction NE carve: the NE corner must be carved in the baked
	# tile. Under the cropping bug the baked tile only ever held the source's
	# top-left quadrant, so its NE corner showed plain ocean instead.
	var coords := renderer.atlas_coords_for_corner("ocean", "grassland", [Vector2i(1, -1)], 0)
	var tile := image.get_region(Rect2i(Vector2i(coords.x * art, coords.y * art), Vector2i(art, art)))
	var grassland: Color = ProceduralTerrainSprite.BASE_COLORS["grassland"]
	var ocean: Color = ProceduralTerrainSprite.BASE_COLORS["ocean"]

	var ne_pixel := tile.get_pixel(art - 1, 0)
	assert_lt(
		_rgb_distance(ne_pixel, grassland), _rgb_distance(ne_pixel, ocean),
		"an NE-carved tile's baked NE corner must be carved -- a cropped blit would show plain ocean here"
	)
	var sw_pixel := tile.get_pixel(0, art - 1)
	assert_lt(
		_rgb_distance(sw_pixel, ocean), _rgb_distance(sw_pixel, grassland),
		"the UNcarved SW corner of that same tile must still read as water"
	)


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func test_paint_keeps_a_straight_ocean_shore_unrounded():
	var tile_set := renderer.build_tile_set()
	tile_map_layer.tile_set = tile_set
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 1
	chunk.elevation = PackedFloat32Array([0.1, 0.4])
	chunk.biome = PackedStringArray(["ocean", "grassland"])

	renderer.paint(tile_map_layer, chunk)

	var variant := renderer.variant_index_for_position(0, 0)
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(Vector2i(0, 0)),
		renderer.atlas_coords_for_biome("ocean", variant),
		"a single-sided (straight) shore must stay the plain animated ocean tile, not a corner carve"
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
