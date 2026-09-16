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


# -- villagers at home: found for their own house, skipped at the doorstep --
#
# docs/concept/building.md "Residents inside": a villager hidden "at home"
# is standing INSIDE their house now, not on its doorstep -- so the Talk
# scan must not find them there (reported: "Talk" won over "Enter" on a
# doorstep, greeting a villager through the wall), while the house itself
# must be able to find its own resident by the seed the record carries.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")


func _villager_at(pixel: Vector2, seed_value: int, at_home: bool) -> NpcMarker:
	var marker := NpcMarker.new()
	marker.identity = NpcIdentity.new(seed_value)
	marker.home_position = pixel
	marker.landmarks = {"well": pixel + Vector2(300, 0), "stall": pixel + Vector2(300, 50), "gate": pixel + Vector2(300, 100)}
	marker.schedule = [
		{"time_block": "morning", "location_tag": "home" if at_home else "stall", "activity": "idle"},
		{"time_block": "midday", "location_tag": "home" if at_home else "stall", "activity": "idle"},
		{"time_block": "evening", "location_tag": "home" if at_home else "stall", "activity": "idle"},
		{"time_block": "night", "location_tag": "home" if at_home else "stall", "activity": "idle"},
	]
	marker.position = pixel
	add_child_autofree(marker)
	marker._process(0.0)  # settles is_at_home() without moving anywhere
	var chunk := Vector2i(floori(pixel.x / CHUNK_PX), floori(pixel.y / CHUNK_PX))
	if not manager._loaded_villages.has(chunk):
		manager._loaded_villages[chunk] = []
	manager._loaded_villages[chunk].append(marker)
	return marker


func test_nearest_npc_near_skips_a_villager_who_is_at_home():
	var doorstep := Vector2(200, 200)
	var inside := _villager_at(doorstep, 11, true)
	assert_true(inside.is_at_home(), "precondition")
	assert_null(manager.nearest_npc_near(doorstep, 48.0), "a villager inside their house is not on the doorstep to talk to")


func test_nearest_npc_near_still_finds_a_villager_who_is_out():
	var pixel := Vector2(200, 200)
	var out := _villager_at(pixel, 12, false)
	assert_false(out.is_at_home(), "precondition")
	assert_eq(manager.nearest_npc_near(pixel, 48.0), out)


func test_resident_marker_for_finds_the_villager_by_the_records_own_seed():
	var doorstep := Vector2(200, 200)
	var other := _villager_at(doorstep + Vector2(64, 0), 21, true)
	var mine := _villager_at(doorstep, 22, true)
	var chunk := Vector2i(floori(doorstep.x / CHUNK_PX), floori(doorstep.y / CHUNK_PX))
	var record := {"chunk_coord": chunk, "resident_seed": 22, "doorstep_global": Vector2i(int(doorstep.x / 16.0), int(doorstep.y / 16.0))}
	assert_eq(manager.resident_marker_for(record), mine)
	assert_ne(manager.resident_marker_for(record), other)


## An older record (resident_seed 0, not yet healed by a village reload)
## still resolves through the villager whose home IS this doorstep.
func test_resident_marker_for_falls_back_to_whoever_lives_at_the_doorstep():
	var doorstep_tile := Vector2i(12, 12)
	var doorstep := (Vector2(doorstep_tile) + Vector2(0.5, 0.5)) * 16.0
	var mine := _villager_at(doorstep, 31, true)
	var chunk := Vector2i(floori(doorstep.x / CHUNK_PX), floori(doorstep.y / CHUNK_PX))
	var record := {"chunk_coord": chunk, "resident_seed": 0, "doorstep_global": doorstep_tile}
	assert_eq(manager.resident_marker_for(record), mine)


func test_resident_marker_for_is_null_for_a_house_nobody_lives_in():
	var record := {"chunk_coord": Vector2i(5, 5), "resident_seed": 99, "doorstep_global": Vector2i(170, 170)}
	assert_null(manager.resident_marker_for(record))
