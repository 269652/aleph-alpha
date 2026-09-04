extends GutTest

## Spawns ants/bugs per chunk -- see docs/concept/carrion.md. Mirrors
## WildCropRenderer's minimal shape rather than AmbientFlyerRenderer's
## fuller scent/species-pool machinery: a decomposer's placement doesn't
## depend on anything chunk-specific beyond biome, just a guaranteed
## min/max count like AmbientFlyerRenderer's own butterflies/bees.

const DecomposerRenderer = preload("res://src/rendering/decomposer_renderer.gd")
const DecomposerMarker = preload("res://src/rendering/decomposer_marker.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(50, 60)
const CHUNK_SIZE := 32

var renderer: DecomposerRenderer
var parent: Node2D


func before_each():
	renderer = DecomposerRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func test_spawns_a_guaranteed_number_on_a_land_biome():
	var markers := renderer.spawn_decomposers(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	assert_gte(markers.size(), DecomposerRenderer.MIN_ANTS_PER_CHUNK + DecomposerRenderer.MIN_BUGS_PER_CHUNK)
	assert_lte(markers.size(), DecomposerRenderer.MAX_ANTS_PER_CHUNK + DecomposerRenderer.MAX_BUGS_PER_CHUNK)
	assert_eq(parent.get_child_count(), markers.size())


func test_spawns_nothing_on_ocean():
	var markers := renderer.spawn_decomposers(parent, "ocean", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	assert_eq(markers.size(), 0)


func test_spawned_markers_stay_within_the_chunk_bounds():
	var markers := renderer.spawn_decomposers(parent, "forest", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2)
	var min_pos := Vector2(CHUNK_ORIGIN) * TILE_SIZE
	var max_pos := Vector2(CHUNK_ORIGIN + Vector2i(CHUNK_SIZE, CHUNK_SIZE)) * TILE_SIZE
	for marker in markers:
		assert_gte(marker.position.x, min_pos.x)
		assert_lte(marker.position.x, max_pos.x)
		assert_gte(marker.position.y, min_pos.y)
		assert_lte(marker.position.y, max_pos.y)


func test_spawning_is_deterministic_for_the_same_seed():
	var a := renderer.spawn_decomposers(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_a: Array = []
	for m in a:
		positions_a.append(m.position)
	for m in a:
		m.free()

	var b := renderer.spawn_decomposers(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_b: Array = []
	for m in b:
		positions_b.append(m.position)
	assert_eq(positions_a, positions_b)


func test_both_ants_and_bugs_can_appear():
	var species_seen := {}
	for chunk_seed in 20:
		var markers := renderer.spawn_decomposers(
			parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, chunk_seed
		)
		for m in markers:
			species_seen[m.species] = true
		for m in markers:
			m.free()
	assert_true(species_seen.has("ant"))
	assert_true(species_seen.has("bug"))


# -- dormant under lying snow (see docs/concept/carrion.md) -------------------


func test_spawns_surface_active_on_bare_ground_by_default():
	var markers := renderer.spawn_decomposers(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	assert_gt(markers.size(), 0)
	for marker in markers:
		assert_false(marker.is_snow_dormant())
		assert_true(marker.visible)


## A chunk loaded mid-winter must not spawn a live ant onto the snow for
## even one frame -- the spawn itself takes the current snow depth.
func test_spawns_already_dormant_under_lying_snow():
	var markers := renderer.spawn_decomposers(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1, 0.5)
	assert_gt(markers.size(), 0)
	for marker in markers:
		assert_true(marker.is_snow_dormant())
		assert_false(marker.visible)
		assert_false(marker.is_processing())
