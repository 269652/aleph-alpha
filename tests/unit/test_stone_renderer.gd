extends GutTest

const StoneRenderer = preload("res://src/rendering/stone_renderer.gd")
const StonePlacement = preload("res://src/world/stone_placement.gd")
const Chunk = preload("res://src/world/chunk.gd")

var renderer: StoneRenderer
var parent: Node2D
var stone_placement := StonePlacement.new()

const TILE_SIZE := 16
const CHUNK_ORIGIN := Vector2i(300, 500)


func before_each():
	renderer = StoneRenderer.new()
	parent = Node2D.new()


func after_each():
	parent.free()


func _make_grassland_chunk(size: int = 16) -> Chunk:
	var chunk := Chunk.new()
	chunk.width = size
	chunk.height = size
	chunk.elevation = PackedFloat32Array()
	chunk.elevation.resize(size * size)
	chunk.biome = PackedStringArray()
	for i in size * size:
		chunk.biome.append("grassland")
	return chunk


func test_spawns_one_node_per_stone_cell():
	var chunk := _make_grassland_chunk()
	var expected := stone_placement.stones_in_chunk(
		CHUNK_ORIGIN, chunk.biome, chunk.width, chunk.height
	).size()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), expected)
	assert_eq(parent.get_child_count(), spawned.size())


func test_no_stones_spawn_on_an_ocean_chunk():
	var chunk := _make_grassland_chunk(8)
	for i in chunk.biome.size():
		chunk.biome[i] = "ocean"
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	assert_eq(spawned.size(), 0)


func test_spawned_stones_are_collidable_bodies_positioned_at_their_tile_center():
	var chunk := _make_grassland_chunk()
	var spawned := renderer.spawn_stones(parent, chunk, CHUNK_ORIGIN, TILE_SIZE)
	if spawned.is_empty():
		pass_test("no stone cells rolled in this chunk; covered by the count test")
		return
	var stone: Node2D = spawned[0]
	assert_true(stone is StaticBody2D, "stones should block movement like trees do")
	var cells := stone_placement.stones_in_chunk(CHUNK_ORIGIN, chunk.biome, chunk.width, chunk.height)
	var expected_position := Vector2(
		(CHUNK_ORIGIN.x + cells[0].x + 0.5) * TILE_SIZE,
		(CHUNK_ORIGIN.y + cells[0].y + 0.5) * TILE_SIZE
	)
	assert_eq(stone.position, expected_position)
