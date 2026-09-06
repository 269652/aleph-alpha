extends GutTest

## Spawns millipedes per chunk -- see docs/concept/soil_fauna.md
## "Millipedes: a dedicated autumn leaf-litter decomposer". Mirrors
## CaterpillarRenderer's own minimal shape (a guaranteed min/max count per
## qualifying biome), minus the one gate a millipede specifically does NOT
## need: no season restriction at all -- unlike a caterpillar, a real
## millipede is present year-round, and the entire point of this creature
## is to be there for the autumn leaf pile a caterpillar cannot touch.

const MillipedeRenderer = preload("res://src/rendering/millipede_renderer.gd")
const MillipedeMarker = preload("res://src/rendering/millipede_marker.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(50, 60)
const CHUNK_SIZE := 32

var renderer: MillipedeRenderer
var parent: Node2D


func before_each():
	renderer = MillipedeRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


func test_spawns_a_guaranteed_number_on_a_qualifying_biome():
	var markers := renderer.spawn_millipedes(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	assert_gte(markers.size(), MillipedeRenderer.MIN_MILLIPEDES_PER_CHUNK)
	assert_lte(markers.size(), MillipedeRenderer.MAX_MILLIPEDES_PER_CHUNK)
	assert_eq(parent.get_child_count(), markers.size())


func test_spawns_nothing_off_a_qualifying_biome():
	var markers := renderer.spawn_millipedes(parent, "desert", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	assert_eq(markers.size(), 0)


## The one thing CaterpillarRenderer's own identical shape gates and this
## must not: season. A millipede spawns in every season alike.
func test_spawns_in_every_season_alike():
	# spawn_millipedes takes no season parameter at all -- calling it
	# identically regardless of the world's current season, and getting a
	# real count back every time, IS the test: there is no seasonal knob to
	# turn off with.
	for i in 4:
		var markers := renderer.spawn_millipedes(parent, "forest", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, i)
		assert_gt(markers.size(), 0, "seed %d" % i)
		for m in markers:
			m.free()


func test_spawned_markers_stay_within_the_chunk_bounds():
	var markers := renderer.spawn_millipedes(parent, "forest", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2)
	var min_pos := Vector2(CHUNK_ORIGIN) * TILE_SIZE
	var max_pos := Vector2(CHUNK_ORIGIN + Vector2i(CHUNK_SIZE, CHUNK_SIZE)) * TILE_SIZE
	for marker in markers:
		assert_gte(marker.position.x, min_pos.x)
		assert_lte(marker.position.x, max_pos.x)
		assert_gte(marker.position.y, min_pos.y)
		assert_lte(marker.position.y, max_pos.y)


func test_spawning_is_deterministic_for_the_same_seed():
	var a := renderer.spawn_millipedes(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_a: Array = []
	for m in a:
		positions_a.append(m.position)
	for m in a:
		m.free()

	var b := renderer.spawn_millipedes(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_b: Array = []
	for m in b:
		positions_b.append(m.position)
	assert_eq(positions_a, positions_b)


func test_spawned_markers_are_real_millipede_markers():
	var markers := renderer.spawn_millipedes(parent, "grassland", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1)
	for m in markers:
		assert_true(m is MillipedeMarker)


## Wherever trees can grow leaf litter to decompose, mirroring
## CaterpillarRenderer.CATERPILLAR_BIOMES exactly -- not the wider,
## carrion-adjacent land set DecomposerRenderer's "bug" uses.
func test_qualifying_biomes_match_caterpillars_exactly():
	const CaterpillarRenderer = preload("res://src/rendering/caterpillar_renderer.gd")
	assert_eq(MillipedeRenderer.MILLIPEDE_BIOMES, CaterpillarRenderer.CATERPILLAR_BIOMES)
