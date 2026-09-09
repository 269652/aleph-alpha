extends GutTest

## EarthChunkManager's cicada dispatch (see docs/concept/creature_and_
## footstep_audio.md's "Cicadas" section): a CicadaMarker per qualifying
## real tree, spawned on chunk load, freed on chunk unload. Mirrors
## test_earth_chunk_manager_bees.gd's own dedicated-file shape -- uses
## `_load_chunk` directly, never the slow real `update()` (see
## CONTRIBUTING.md / test_earth_chunk_manager.gd's own known-slow-file
## note).
##
## The real per-tree ROLL is non-deterministic by design (see
## CicadaPopulation's own doc comment) -- exactly like bee/wild-bee hive
## placement's own accepted probabilism in test_earth_chunk_manager_bees.gd,
## the actual spawn GLUE (_spawn_cicadas_for_indices) is tested here via a
## direct, deterministic call that bypasses the roll entirely, mirroring
## that file's own `manager._bee_colonies[coord] = colony` direct-injection
## precedent -- CicadaPopulation.cicada_tree_indices' own pure density/
## season logic is already fully covered deterministically in
## test_cicada_population.gd.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const CicadaMarker = preload("res://src/rendering/cicada_marker.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _berlin_tile: Vector2i
var _berlin_chunk: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	var geo_coordinates := GeoCoordinates.new()
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_berlin_chunk = Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Dispatch must actually run on every real chunk load -- proven by the
## dict key existing at all (even an empty array is a real "dispatch ran,
## nothing qualified this roll" result), regardless of the live season/roll
## outcome at test time.
func test_loading_a_chunk_runs_cicada_dispatch():
	manager._load_chunk(_berlin_chunk)
	assert_true(manager._cicada_markers.has(_berlin_chunk))


## The real spawn glue: given real trees and a deterministic index list
## (bypassing the roll, mirroring test_earth_chunk_manager_bees.gd's own
## direct-injection precedent), a marker actually gets created, positioned
## at its tree, added to the scene, and tracked for this chunk.
func test_spawning_for_a_qualifying_tree_creates_a_positioned_marker():
	manager._load_chunk(_berlin_chunk)
	var trees: Array = manager._loaded_trees.get(_berlin_chunk, [])
	if trees.is_empty():
		pending("this run's real chunk generation placed no trees in Berlin's chunk")
		return

	manager._spawn_cicadas_for_indices(_berlin_chunk, trees, [0])

	var markers: Array = manager._cicada_markers.get(_berlin_chunk, [])
	assert_eq(markers.size(), 1)
	assert_eq(markers[0].species, "cicada")
	assert_eq(markers[0].position, trees[0].position)
	assert_true(markers[0].is_inside_tree(), "a spawned marker should actually be added to the scene")


## Unloading a chunk must free every cicada marker it holds, the identical
## `for marker in ...get(chunk_coord, []): marker.free()` / `...erase(
## chunk_coord)` discipline every other per-chunk marker collection in this
## file already gets (trees, stones, cave-entrance markers, bee hives) --
## otherwise a cicada silently outlives the chunk it was anchored to.
func test_unloading_a_chunk_frees_its_cicada_markers():
	manager._load_chunk(_berlin_chunk)
	var trees: Array = manager._loaded_trees.get(_berlin_chunk, [])
	if trees.is_empty():
		pending("this run's real chunk generation placed no trees in Berlin's chunk")
		return
	manager._spawn_cicadas_for_indices(_berlin_chunk, trees, [0])
	var marker = manager._cicada_markers[_berlin_chunk][0]

	manager._unload_chunk(_berlin_chunk)

	assert_true(not is_instance_valid(marker) or marker.is_queued_for_deletion())
	assert_false(manager._cicada_markers.has(_berlin_chunk))
