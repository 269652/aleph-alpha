extends GutTest

## A farmstead clears its own ground (docs/concept/village_farms.md).
##
## Reported in play with the enclosure in shot: *"the Farmhouse should clear
## trees in its bed enclosure"*. Every other real placement path here already
## fells what is in its way -- place_building and build_at_global both clear
## the cells they write -- but a farmstead's BEDS are not written tiles, so
## nothing ever cleared them, and a farmer tilling one has no axe.
##
## `clear_vegetation_at_global` is the public door onto that same sweep. Same
## direct-injection shape as test_earth_chunk_manager_felled_tree_registry.gd
## -- never the slow real update().

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const Chunk = preload("res://src/world/chunk.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const _CHUNK := Vector2i(0, 0)

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	manager._loaded_chunks[_CHUNK] = Chunk.new()


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _centre_of(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)


func _tree_at(cell: Vector2i) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = _centre_of(cell)
	tree.species_bias = ForageScheduler.new().genome_for(tree.position).species_bias
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	var bucket: Array = manager._loaded_trees.get(_CHUNK, [])
	bucket.append(tree)
	manager._loaded_trees[_CHUNK] = bucket
	return tree


func test_a_tree_standing_in_a_cleared_cell_comes_down():
	var doomed := _tree_at(Vector2i(4, 4))

	manager.clear_vegetation_at_global([Vector2i(4, 4)])

	assert_true(doomed.is_queued_for_deletion(), "the oak in the bed is felled")


## And only that cell: a village fells the timber it needs, not the wood it
## is standing near.
func test_a_tree_beside_a_cleared_cell_is_left_standing():
	var spared := _tree_at(Vector2i(9, 9))

	manager.clear_vegetation_at_global([Vector2i(4, 4)])

	assert_false(spared.is_queued_for_deletion())
	assert_true(manager._loaded_trees[_CHUNK].has(spared), "and stays on the register")


## The whole bed set in one call, which is how a farmstead asks.
func test_every_cell_of_a_whole_field_is_cleared_at_once():
	var beds: Array = []
	var doomed: Array = []
	for y in range(3, 5):
		for x in range(3, 6):
			beds.append(Vector2i(x, y))
			doomed.append(_tree_at(Vector2i(x, y)))

	manager.clear_vegetation_at_global(beds)

	for tree in doomed:
		assert_true(tree.is_queued_for_deletion(), "a 3x2 field is cleared whole")


## Running it again over ground already cleared changes nothing and crashes
## nothing -- which is what lets a village re-run it on every visit and heal
## a farmstead founded before this existed.
func test_clearing_the_same_ground_twice_is_a_no_op():
	_tree_at(Vector2i(4, 4))
	manager.clear_vegetation_at_global([Vector2i(4, 4)])

	manager.clear_vegetation_at_global([Vector2i(4, 4)])

	assert_true(manager._loaded_trees[_CHUNK].is_empty(), "nothing left to fell, and nothing broke")


## Cells in a chunk nobody has loaded are skipped: a village only ever clears
## ground it is standing on.
func test_cells_in_an_unloaded_chunk_are_skipped():
	var far := Vector2i(EarthChunkManager.CHUNK_SIZE * 40, EarthChunkManager.CHUNK_SIZE * 40)
	manager.clear_vegetation_at_global([far])
	assert_true(true, "nothing to clear, nothing to crash on")


func test_clearing_nothing_at_all_is_a_no_op():
	manager.clear_vegetation_at_global([])
	assert_true(true)


## The persisted record goes with it: a tree the village felled must not come
## back on the next load.
func test_a_cleared_cell_loses_its_planted_tree_record():
	var chunk: Chunk = manager._loaded_chunks[_CHUNK]
	chunk.planted_trees = [
		{"position": _centre_of(Vector2i(4, 4))},
		{"position": _centre_of(Vector2i(9, 9))},
	]

	manager.clear_vegetation_at_global([Vector2i(4, 4)])

	assert_eq(chunk.planted_trees.size(), 1, "the felled one is off the record")
	assert_eq(chunk.planted_trees[0]["position"], _centre_of(Vector2i(9, 9)))
