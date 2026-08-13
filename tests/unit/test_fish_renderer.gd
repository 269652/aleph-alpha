extends GutTest

## FishRenderer: chunk-based spawn/despawn of visible, catchable fish on
## ocean cells -- same "one node per qualifying tile, deterministic per
## global coordinate, capped so a huge water body doesn't spawn hundreds of
## nodes" shape as TreeRenderer/CreatureRenderer.

const FishRenderer = preload("res://src/rendering/fish_renderer.gd")
const FishMarker = preload("res://src/rendering/fish_marker.gd")
const Chunk = preload("res://src/world/chunk.gd")

const TILE_SIZE := 16
const CHUNK_SIZE := 32
const CHUNK_ORIGIN := Vector2i(64, 128)

var renderer: FishRenderer
var parent: Node2D


func before_each():
	renderer = FishRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_chunk(biome_name: String, size: int = CHUNK_SIZE) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append(biome_name)
	return chunk


func test_spawns_nothing_on_a_chunk_with_no_ocean():
	var chunk := _make_chunk("grassland")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


func test_spawns_some_fish_on_a_large_ocean_chunk():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	assert_eq(parent.get_child_count(), spawned.size())


func test_never_exceeds_the_per_chunk_fish_cap():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_lte(spawned.size(), FishRenderer.MAX_FISH_PER_CHUNK)


func test_fish_are_positioned_within_the_chunk_bounds():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(2, 3), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		var tile_x := int(fish.position.x / TILE_SIZE)
		var tile_y := int(fish.position.y / TILE_SIZE)
		assert_between(tile_x, CHUNK_ORIGIN.x, CHUNK_ORIGIN.x + CHUNK_SIZE - 1)
		assert_between(tile_y, CHUNK_ORIGIN.y, CHUNK_ORIGIN.y + CHUNK_SIZE - 1)


func test_positions_are_deterministic_for_the_same_inputs():
	var chunk := _make_chunk("ocean")
	var first := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var first_positions: Array[Vector2] = []
	for fish in first:
		first_positions.append(fish.position)

	var other_parent := Node2D.new()
	var second := renderer.spawn_fish(other_parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var second_positions: Array[Vector2] = []
	for fish in second:
		second_positions.append(fish.position)
	other_parent.free()

	assert_eq(first_positions, second_positions)


func test_spawned_fish_are_fish_markers_with_a_texture():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		assert_true(fish is FishMarker)
		assert_not_null(fish.texture)


## The stranding fix's spawn half: fish must only spawn on INTERIOR water
## cells (all four cardinal neighbors also water), never on a cell touching
## the shore -- a shore-adjacent spawn starts life half-beached and, with the
## clearance rule (see FishMarker.CLEARANCE_PX), barely able to move.
func test_fish_never_spawn_on_water_cells_touching_land():
	var chunk := _make_chunk("ocean")
	# Carve a land column through the middle -- its water neighbors become
	# shore cells no fish may spawn on.
	var land_x := CHUNK_SIZE / 2
	for y in CHUNK_SIZE:
		chunk.biome[y * CHUNK_SIZE + land_x] = "grassland"

	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	for fish in spawned:
		var tile_x := int(fish.position.x / TILE_SIZE) - CHUNK_ORIGIN.x
		assert_ne(tile_x, land_x - 1, "fish spawned on the shore cell west of the land column")
		assert_ne(tile_x, land_x + 1, "fish spawned on the shore cell east of the land column")
		assert_ne(tile_x, land_x, "fish spawned on land itself")


func test_fish_never_spawn_on_the_chunks_edge_cells():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(1, 1), chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_gt(spawned.size(), 0)
	for fish in spawned:
		var tile := Vector2i(int(fish.position.x / TILE_SIZE), int(fish.position.y / TILE_SIZE)) - CHUNK_ORIGIN
		assert_gt(tile.x, 0)
		assert_gt(tile.y, 0)
		assert_lt(tile.x, CHUNK_SIZE - 1)
		assert_lt(tile.y, CHUNK_SIZE - 1)


## Colorful and multiple varieties, in practice: across a large enough ocean
## chunk, more than one species should show up.
func test_a_large_ocean_chunk_spawns_a_mix_of_species():
	var chunk := _make_chunk("ocean")
	var spawned := renderer.spawn_fish(parent, Vector2i(4, 4), chunk, CHUNK_ORIGIN, TILE_SIZE)
	var species_seen := {}
	for fish in spawned:
		species_seen[fish.species] = true
	assert_gt(species_seen.size(), 1, "expected more than one species across a large ocean chunk")
