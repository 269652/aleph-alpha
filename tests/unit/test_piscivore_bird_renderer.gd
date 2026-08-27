extends GutTest

## Chunk-based spawn/despawn of fish-eating birds (kingfishers) -- gated by
## water presence (not a land biome pool, unlike AmbientFlyerRenderer),
## since piscivores hunt over water specifically. See
## docs/concept/ecosystem_dynamics.md's "fish-eating birds".

const PiscivoreBirdRenderer = preload("res://src/rendering/piscivore_bird_renderer.gd")
const PiscivoreBirdMarker = preload("res://src/rendering/piscivore_bird_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

var renderer: PiscivoreBirdRenderer
var parent: Node2D


func before_each():
	renderer = PiscivoreBirdRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_chunk(biome_name: String, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append(biome_name)
	return chunk


func test_spawns_nothing_on_a_chunk_with_no_water():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_eq(spawned.size(), 0)


func test_never_exceeds_max_per_chunk_on_a_large_ocean_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 500.0
	)
	assert_lte(spawned.size(), PiscivoreBirdRenderer.MAX_PER_CHUNK)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_piscivore_birds(
		parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)

	var other_parent := Node2D.new()
	var second := renderer.spawn_piscivore_birds(
		other_parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)

	var first_positions: Array[Vector2] = []
	for bird in first:
		first_positions.append(bird.position)
	var second_positions: Array[Vector2] = []
	for bird in second:
		second_positions.append(bird.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_spawned_bird_is_a_piscivore_bird_marker_with_a_texture():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 5.0
	)
	assert_eq(spawned.size(), 1)
	assert_true(spawned[0] is PiscivoreBirdMarker)
	assert_not_null(spawned[0].texture)


# -- promoted from the real aggregate kingfisher population, not a die roll --
#
# A kingfisher used to appear on a flat SPAWN_CHANCE roll regardless of
# whether the water it hunts had any fish at all. Presence is now driven by
# EcosystemSimulation.kingfisher_population -- itself derived from the
# EXISTING fish population (see KingfisherPopulationModel) -- mirroring
# CreatureRenderer's aggregate-population-to-marker-count promotion.

func test_spawns_nothing_without_a_kingfisher_population():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 0.0
	)
	assert_eq(spawned.size(), 0)


func test_spawns_a_kingfisher_once_population_reaches_one():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(
		parent, Vector2i(0, 0), chunk, CHUNK_ORIGIN, TILE_SIZE, null, 0.6
	)
	assert_eq(spawned.size(), 1)
