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
	var spawned := renderer.spawn_piscivore_birds(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


func test_never_exceeds_max_per_chunk_on_a_large_ocean_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_piscivore_birds(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_lte(spawned.size(), PiscivoreBirdRenderer.MAX_PER_CHUNK)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_piscivore_birds(parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE)

	var other_parent := Node2D.new()
	var second := renderer.spawn_piscivore_birds(other_parent, Vector2i(2, 2), chunk, CHUNK_ORIGIN, TILE_SIZE)

	var first_positions: Array[Vector2] = []
	for bird in first:
		first_positions.append(bird.position)
	var second_positions: Array[Vector2] = []
	for bird in second:
		second_positions.append(bird.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


## Sample several chunk coords to find one that actually rolls a spawn
## (SPAWN_CHANCE is intentionally rare -- a special sight, not filling the sky).
func test_spawned_bird_is_a_piscivore_bird_marker_with_a_texture():
	var found := false
	for coord_x in range(50):
		var chunk := _make_chunk("ocean")
		var spawned := renderer.spawn_piscivore_birds(
			parent, Vector2i(coord_x, 0), chunk, CHUNK_ORIGIN, TILE_SIZE
		)
		if not spawned.is_empty():
			found = true
			assert_true(spawned[0] is PiscivoreBirdMarker)
			assert_not_null(spawned[0].texture)
			break
	assert_true(found, "expected at least one kingfisher spawn across 50 sampled water chunks")
