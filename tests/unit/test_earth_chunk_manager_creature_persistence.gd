extends GutTest

## EarthChunkManager._unload_chunk: a wild creature that has physically
## wandered into a NEIGHBOURING, still-loaded chunk must survive -- not be
## freed just because its bookkeeping (_loaded_creatures) still files it
## under the chunk it started in. Reported live: "animals (like a boar
## chasing or a deer being hunted) don't survive chunk borders and just
## disappear" (see docs/concept/ecosystem_dynamics.md "An individually-
## rendered creature crossing a chunk border").
##
## Deliberately a small, dedicated file rather than an addition to the
## giant, slow test_earth_chunk_manager.gd (see that file's own note on
## manager.update() costing ~101s/call) -- these tests never call
## update()/_load_chunk at all, the same minimal-manager, poke-internal-
## state style test_earth_chunk_manager_walnut_crush.gd already uses:
## _unload_chunk itself only ever touches a chunk's own recorded entries
## (dictionary .get/.erase with safe defaults throughout) and unconditionally
## erases whatever tiles sit under it (a harmless no-op on cells nothing
## ever painted), so no real chunk generation is needed to exercise it.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D

## An unrelated, out-of-the-way trio of coordinates -- not the "Berlin"
## fixture other EarthChunkManager tests share (see the shared user://
## data dir note in CONTRIBUTING.md), so this file's own kept-animals/
## growing-juveniles save files never collide with anyone else's.
const STALE_COORD := Vector2i(400, 400)
const NEIGHBOR_COORD := Vector2i(401, 400)
const FAR_UNLOADED_COORD := Vector2i(450, 450)


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	add_child(creatures_parent)
	manager._loaded_creatures[STALE_COORD] = []


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()
	for path in [manager._kept_animals_path(STALE_COORD), manager._growing_juveniles_path(STALE_COORD)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _spawn_wild_adult(species: String, pixel_position: Vector2) -> CreatureMarker:
	var creature := manager._creature_renderer.spawn_single(
		creatures_parent, species, pixel_position, manager, TerrainRenderer.TILE_SIZE
	)
	manager._loaded_creatures[STALE_COORD].append(creature)
	return creature


func _pixel_in_chunk(chunk_coord: Vector2i) -> Vector2:
	var tile := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(1, 1)
	return Vector2(tile) * TerrainRenderer.TILE_SIZE


func test_a_wild_adult_that_wandered_into_a_still_loaded_neighbor_survives_its_home_chunks_unload():
	manager._loaded_chunks[NEIGHBOR_COORD] = null
	var boar := _spawn_wild_adult("boar", _pixel_in_chunk(NEIGHBOR_COORD))

	manager._unload_chunk(STALE_COORD)

	assert_true(is_instance_valid(boar), "a creature standing in a still-loaded neighbor must not be freed")


func test_the_survivor_is_re_filed_under_its_own_current_chunk():
	manager._loaded_chunks[NEIGHBOR_COORD] = null
	var boar := _spawn_wild_adult("boar", _pixel_in_chunk(NEIGHBOR_COORD))

	manager._unload_chunk(STALE_COORD)

	assert_true(
		manager._loaded_creatures.get(NEIGHBOR_COORD, []).has(boar),
		"a rehomed creature must actually be findable under its new chunk"
	)
	assert_false(manager._loaded_creatures.has(STALE_COORD), "the stale chunk's own key is still dropped")


func test_a_wild_adult_that_never_left_its_own_chunk_is_still_freed():
	var boar := _spawn_wild_adult("boar", _pixel_in_chunk(STALE_COORD))

	manager._unload_chunk(STALE_COORD)

	assert_false(is_instance_valid(boar), "an animal that never left the unloading chunk is still culled normally")


func test_a_wild_adult_that_wandered_somewhere_not_currently_loaded_is_still_freed():
	var boar := _spawn_wild_adult("boar", _pixel_in_chunk(FAR_UNLOADED_COORD))

	manager._unload_chunk(STALE_COORD)

	assert_false(
		is_instance_valid(boar),
		"a creature that wandered somewhere not tracked as loaded at all has genuinely left the relevant area"
	)


## A tamed animal is already covered by _save_kept_animals/_restore_kept_
## animals -- rehoming the SAME live instance too would leave both a
## serialized record at the stale chunk's own path AND a still-alive
## wandered instance, spawning a duplicate the next time that chunk reloads.
func test_a_tamed_animal_stays_on_the_kept_animals_path_not_the_new_rehoming_path():
	manager._loaded_chunks[NEIGHBOR_COORD] = null
	var horse := _spawn_wild_adult("horse", _pixel_in_chunk(NEIGHBOR_COORD))
	horse.trust = 1.0

	manager._unload_chunk(STALE_COORD)

	assert_false(is_instance_valid(horse), "a tamed animal is freed here -- KeptAnimals is its one path back")
