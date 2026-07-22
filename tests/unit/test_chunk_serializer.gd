extends GutTest

const Chunk = preload("res://src/world/chunk.gd")
const ChunkSerializer = preload("res://src/world/chunk_serializer.gd")

const TEST_PATH := "user://test_chunk.bin"

var serializer: ChunkSerializer


func before_each():
	serializer = ChunkSerializer.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func _make_chunk() -> Chunk:
	var chunk := Chunk.new()
	chunk.width = 2
	chunk.height = 2
	chunk.elevation = PackedFloat32Array([0.1, 0.2, 0.3, 0.4])
	chunk.biome = PackedStringArray(["ocean", "grassland", "desert", "forest"])
	chunk.modifications = {Vector2i(1, 1): "built_wall"}
	return chunk


func test_save_then_load_round_trips_dimensions_and_terrain_data():
	var chunk := _make_chunk()
	serializer.save_chunk(chunk, TEST_PATH)
	var loaded: Chunk = serializer.load_chunk(TEST_PATH)
	assert_eq(loaded.width, 2)
	assert_eq(loaded.height, 2)
	assert_eq(loaded.elevation, chunk.elevation)
	assert_eq(loaded.biome, chunk.biome)


func test_save_then_load_round_trips_player_modifications():
	var chunk := _make_chunk()
	serializer.save_chunk(chunk, TEST_PATH)
	var loaded: Chunk = serializer.load_chunk(TEST_PATH)
	assert_eq(loaded.modifications, {Vector2i(1, 1): "built_wall"})


func test_loading_a_missing_chunk_file_returns_null():
	assert_eq(serializer.load_chunk("user://does_not_exist.bin"), null)


func test_save_then_load_modifications_round_trips():
	var modifications := {Vector2i(3, 4): "wall"}
	serializer.save_modifications(modifications, TEST_PATH)
	assert_eq(serializer.load_modifications(TEST_PATH), modifications)


func test_loading_missing_modifications_returns_an_empty_dictionary():
	assert_eq(serializer.load_modifications("user://does_not_exist.bin"), {})


func test_save_then_load_planted_trees_round_trips():
	var planted_trees := [
		{"position": Vector2(120.0, 340.0), "planted_at": 12.5},
		{"position": Vector2(140.0, 340.0), "planted_at": 40.0},
	]
	serializer.save_planted_trees(planted_trees, TEST_PATH)
	assert_eq(serializer.load_planted_trees(TEST_PATH), planted_trees)


func test_loading_missing_planted_trees_returns_an_empty_array():
	assert_eq(serializer.load_planted_trees("user://does_not_exist.bin"), [])
