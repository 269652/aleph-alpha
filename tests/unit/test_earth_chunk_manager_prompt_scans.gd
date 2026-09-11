extends GutTest

## EarthChunkManager's nearest-X-near scans behind the interaction prompt
## (World._update_interaction_prompt: nearest_npc_near, nearest_liftable_
## stone_near), scoped to the chunks a radius can actually touch (FPS
## regression round 11, docs/concept/soil_fauna.md). Both used to walk EVERY
## loaded chunk's list -- every stone, every village node in 30 chunks --
## for a radius of a few tiles, ~4 ms per call on a 13 Hz wall-clock cadence
## that is every frame at low fps. The registries are already keyed by chunk
## coord (the shape trees_near/flyers_near already exploit), so the scan now
## only visits the chunks within reach: `chunk_coords_within` is that pure
## square-of-chunks helper, pinned here, and the stone scan is proven to
## still find what it should across a chunk boundary and to ignore what it
## should beyond the radius. Registries are injected directly (this file's
## siblings' own "poke internal state" convention), no chunk load needed.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const CHUNK_PX := float(EarthChunkManager.CHUNK_SIZE * TerrainRenderer.TILE_SIZE)


## A liftable stone as the scan sees one: a positioned node with pick_up().
class _Stone extends Node2D:
	func pick_up() -> void:
		pass


var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _stone_at(pixel: Vector2) -> _Stone:
	var stone := _Stone.new()
	stone.position = pixel
	add_child_autofree(stone)
	var chunk := Vector2i(floori(pixel.x / CHUNK_PX), floori(pixel.y / CHUNK_PX))
	if not manager._loaded_stones.has(chunk):
		manager._loaded_stones[chunk] = []
	manager._loaded_stones[chunk].append(stone)
	return stone


# -- the pure helper ---------------------------------------------------------


func test_a_small_radius_well_inside_a_chunk_touches_only_that_chunk():
	var coords: Array = EarthChunkManager.chunk_coords_within(Vector2(CHUNK_PX * 0.5, CHUNK_PX * 0.5), 10.0)
	assert_eq(coords, [Vector2i(0, 0)])


func test_a_radius_crossing_a_chunk_boundary_touches_both_sides():
	var coords: Array = EarthChunkManager.chunk_coords_within(Vector2(CHUNK_PX - 1.0, CHUNK_PX * 0.5), 10.0)
	assert_eq(coords.size(), 2)
	assert_true(coords.has(Vector2i(0, 0)))
	assert_true(coords.has(Vector2i(1, 0)))


func test_a_radius_wider_than_a_chunk_touches_the_full_square_around_it():
	var coords: Array = EarthChunkManager.chunk_coords_within(Vector2(CHUNK_PX * 1.5, CHUNK_PX * 1.5), CHUNK_PX)
	assert_eq(coords.size(), 9, "a chunk on every side")
	for y in range(0, 3):
		for x in range(0, 3):
			assert_true(coords.has(Vector2i(x, y)))


func test_negative_coordinates_floor_correctly():
	var coords: Array = EarthChunkManager.chunk_coords_within(Vector2(-1.0, -1.0), 1.0)
	assert_eq(coords.size(), 4)
	assert_true(coords.has(Vector2i(-1, -1)))
	assert_true(coords.has(Vector2i(0, 0)))


# -- the stone scan through it ----------------------------------------------


func test_a_stone_just_across_a_chunk_boundary_but_within_reach_is_still_found():
	var here := Vector2(CHUNK_PX - 5.0, CHUNK_PX * 0.5)
	var across := _stone_at(here + Vector2(10.0, 0.0))  # 10px away, next chunk over
	assert_eq(manager.nearest_liftable_stone_near(here, 20.0), across)


func test_the_nearest_of_several_wins_regardless_of_which_chunk_holds_it():
	var here := Vector2(CHUNK_PX - 5.0, CHUNK_PX * 0.5)
	_stone_at(here + Vector2(-15.0, 0.0))  # same chunk, 15px
	var nearest := _stone_at(here + Vector2(8.0, 0.0))  # next chunk, 8px
	assert_eq(manager.nearest_liftable_stone_near(here, 20.0), nearest)


func test_a_stone_beyond_the_radius_is_not_returned_even_in_a_touched_chunk():
	var here := Vector2(CHUNK_PX * 0.5, CHUNK_PX * 0.5)
	_stone_at(here + Vector2(100.0, 0.0))
	assert_null(manager.nearest_liftable_stone_near(here, 20.0))


func test_a_stone_in_a_distant_loaded_chunk_is_never_returned():
	var here := Vector2(CHUNK_PX * 0.5, CHUNK_PX * 0.5)
	_stone_at(here + Vector2(CHUNK_PX * 5.0, 0.0))
	assert_null(manager.nearest_liftable_stone_near(here, 20.0))
