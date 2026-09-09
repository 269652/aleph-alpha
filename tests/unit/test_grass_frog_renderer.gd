extends GutTest

## Spawns grass frogs per chunk -- part of the seasonal-behavior epic's
## phase 10 (docs/concept/seasonal_behavior.md): a real biology-grounded
## presence brand new to the game. Mirrors CaterpillarRenderer's own
## minimal shape exactly (a guaranteed min/max count per qualifying chunk,
## no scent/species-pool machinery), with the season gate flipped to real
## grass frog biology -- active spring through autumn, brumates buried in
## mud/leaf litter through winter -- and one addition CaterpillarRenderer
## doesn't need at all: a real WATER-PRESENCE gate (a grass frog needs
## actual water nearby, not just the right land biome), reusing
## WaterAreaSurvey.interior_water_cell_count -- the same real "how much
## water is in this chunk" signal the aquatic fish population model
## already uses, rather than inventing a second one.

const GrassFrogRenderer = preload("res://src/rendering/grass_frog_renderer.gd")
const GrassFrogMarker = preload("res://src/rendering/grass_frog_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16.0
const CHUNK_ORIGIN := Vector2i(50, 60)
const CHUNK_SIZE := 32

var renderer: GrassFrogRenderer
var parent: Node2D


func before_each():
	renderer = GrassFrogRenderer.new()
	parent = Node2D.new()
	add_child_autofree(parent)


## A chunk that is entirely one biome, with (or without) real water cells --
## mirrors test_water_area_survey.gd's own _make_chunk fixture.
func _make_chunk(biome_name: String, with_water: bool, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.biome = PackedStringArray()
	chunk.biome.resize(size * size)
	chunk.biome.fill(biome_name)
	if with_water:
		chunk.is_river = PackedByteArray()
		chunk.is_river.resize(size * size)
		chunk.is_river.fill(1)
	return chunk


func test_spawns_a_guaranteed_number_near_water_on_a_qualifying_biome_in_season():
	var chunk := _make_chunk("grassland", true)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_gte(markers.size(), GrassFrogRenderer.MIN_GRASS_FROGS_PER_CHUNK)
	assert_lte(markers.size(), GrassFrogRenderer.MAX_GRASS_FROGS_PER_CHUNK)
	assert_eq(parent.get_child_count(), markers.size())


func test_spawns_nothing_off_a_qualifying_biome_even_with_water():
	var chunk := _make_chunk("desert", true)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "desert", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_eq(markers.size(), 0)


## The one gate CaterpillarRenderer's own identical shape doesn't need at
## all: a grass frog needs REAL water nearby, not just the right land
## biome -- a grassland chunk with no river/lake/ocean cell in it at all is
## not pond-adjacent no matter what biome name it carries.
func test_spawns_nothing_on_a_qualifying_biome_with_no_water():
	var chunk := _make_chunk("grassland", false)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_eq(markers.size(), 0, "a grassland chunk with no real water cell has no pond to sit beside")


## Real biology: a grass frog brumates (buries into mud/leaf litter,
## inactive) through winter, mirroring the same accepted "spawn-time gate,
## not a per-frame one" shape as CaterpillarRenderer's own ACTIVE_SEASONS.
func test_spawns_nothing_in_winter_even_near_water_on_a_qualifying_biome():
	var chunk := _make_chunk("grassland", true)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "grassland", "winter", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_eq(markers.size(), 0, "a grass frog is brumating, buried through winter")


func test_spawns_in_spring_summer_and_autumn():
	for season in ["spring", "summer", "autumn"]:
		var chunk := _make_chunk("grassland", true)
		var markers := renderer.spawn_grass_frogs(
			parent, chunk, "grassland", season, CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
		)
		assert_gt(markers.size(), 0, season)
		for m in markers:
			m.free()


func test_spawned_markers_stay_within_the_chunk_bounds():
	var chunk := _make_chunk("forest", true)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "forest", "spring", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 2
	)
	var min_pos := Vector2(CHUNK_ORIGIN) * TILE_SIZE
	var max_pos := Vector2(CHUNK_ORIGIN + Vector2i(CHUNK_SIZE, CHUNK_SIZE)) * TILE_SIZE
	for marker in markers:
		assert_gte(marker.position.x, min_pos.x)
		assert_lte(marker.position.x, max_pos.x)
		assert_gte(marker.position.y, min_pos.y)
		assert_lte(marker.position.y, max_pos.y)


func test_spawning_is_deterministic_for_the_same_seed():
	var chunk := _make_chunk("grassland", true)
	var a := renderer.spawn_grass_frogs(parent, chunk, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_a: Array = []
	for m in a:
		positions_a.append(m.position)
	for m in a:
		m.free()

	var b := renderer.spawn_grass_frogs(parent, chunk, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 5)
	var positions_b: Array = []
	for m in b:
		positions_b.append(m.position)
	assert_eq(positions_a, positions_b)


func test_spawned_markers_are_real_grass_frog_markers():
	var chunk := _make_chunk("grassland", true)
	var markers := renderer.spawn_grass_frogs(
		parent, chunk, "grassland", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	for m in markers:
		assert_true(m is GrassFrogMarker)


## Lake cells count as real water too (WaterAreaSurvey.is_water_cell), not
## just rivers -- an inland pond is exactly as real a frog habitat as a
## riverbank. Uses a genuine land biome (forest) with an is_lake overlay,
## mirroring test_water_area_survey.gd's own lake case -- "ocean" itself
## isn't in GRASS_FROG_BIOMES, so an all-ocean chunk would fail the biome
## gate regardless of how much water it has.
func test_lake_cells_count_as_water_too():
	var lake_chunk := Chunk.new()
	lake_chunk.width = CHUNK_SIZE
	lake_chunk.height = CHUNK_SIZE
	lake_chunk.biome = PackedStringArray()
	lake_chunk.biome.resize(CHUNK_SIZE * CHUNK_SIZE)
	lake_chunk.biome.fill("forest")
	lake_chunk.is_lake = PackedByteArray()
	lake_chunk.is_lake.resize(CHUNK_SIZE * CHUNK_SIZE)
	lake_chunk.is_lake.fill(1)
	var markers := renderer.spawn_grass_frogs(
		parent, lake_chunk, "forest", "summer", CHUNK_ORIGIN, CHUNK_SIZE, TILE_SIZE, 1
	)
	assert_gt(markers.size(), 0, "a lake cell is real water too")
