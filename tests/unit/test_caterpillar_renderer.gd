extends GutTest

## Spawns caterpillars per chunk -- requested live: "wire caterpillars
## which live on trees and on the ground around them; they should also do
## groundforaging and eat green leaves (spring, summer only)". Mirrors
## DecomposerRenderer's own minimal shape (a guaranteed min/max count per
## qualifying chunk, no scent/species-pool machinery -- a caterpillar's
## placement doesn't depend on anything chunk-specific beyond biome), with
## one addition DecomposerRenderer doesn't need at all: a SEASON gate.
## Real caterpillars are a growing-season life stage, not a year-round
## presence -- see CaterpillarMarker's own doc comment for why this is
## checked here, at the spawn decision, rather than continuously at
## runtime (the same accepted approximation every other ambient decoration
## in this codebase already has).

const CaterpillarRenderer = preload("res://src/rendering/caterpillar_renderer.gd")
const CaterpillarMarker = preload("res://src/rendering/caterpillar_marker.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(50, 60)
const CHUNK_SIZE := 32

var renderer: CaterpillarRenderer
var parent: Node2D


func before_each():
	renderer = CaterpillarRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func test_spawns_a_guaranteed_number_on_a_qualifying_biome_in_season():
	var markers := renderer.spawn_caterpillars(
		parent, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_gte(markers.size(), CaterpillarRenderer.MIN_CATERPILLARS_PER_CHUNK)
	assert_lte(markers.size(), CaterpillarRenderer.MAX_CATERPILLARS_PER_CHUNK)
	assert_eq(parent.get_child_count(), markers.size())


func test_spawns_nothing_off_a_qualifying_biome():
	var markers := renderer.spawn_caterpillars(
		parent, "ocean", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_eq(markers.size(), 0)


## The one gate DecomposerRenderer's own identical shape doesn't need at
## all: caterpillars are a spring/summer life stage, not year-round.
func test_spawns_nothing_in_autumn_or_winter_even_on_a_qualifying_biome():
	for season in ["autumn", "winter"]:
		var markers := renderer.spawn_caterpillars(
			parent, "grassland", season, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
		)
		assert_eq(markers.size(), 0, season)


func test_spawns_in_both_spring_and_summer():
	for season in ["spring", "summer"]:
		var markers := renderer.spawn_caterpillars(
			parent, "grassland", season, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
		)
		assert_gt(markers.size(), 0, season)
		for m in markers:
			m.free()


func test_spawned_markers_stay_within_the_chunk_bounds():
	var markers := renderer.spawn_caterpillars(
		parent, "forest", "spring", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2
	)
	var min_pos := Vector2(CHUNK_ORIGIN) * TILE_SIZE
	var max_pos := Vector2(CHUNK_ORIGIN + Vector2i(CHUNK_SIZE, CHUNK_SIZE)) * TILE_SIZE
	for marker in markers:
		assert_gte(marker.position.x, min_pos.x)
		assert_lte(marker.position.x, max_pos.x)
		assert_gte(marker.position.y, min_pos.y)
		assert_lte(marker.position.y, max_pos.y)


func test_spawning_is_deterministic_for_the_same_seed():
	var a := renderer.spawn_caterpillars(parent, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_a: Array = []
	for m in a:
		positions_a.append(m.position)
	for m in a:
		m.free()

	var b := renderer.spawn_caterpillars(parent, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_b: Array = []
	for m in b:
		positions_b.append(m.position)
	assert_eq(positions_a, positions_b)


func test_spawned_markers_are_real_caterpillar_markers():
	var markers := renderer.spawn_caterpillars(
		parent, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	for m in markers:
		assert_true(m is CaterpillarMarker)
