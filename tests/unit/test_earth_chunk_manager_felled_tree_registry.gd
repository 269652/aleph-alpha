extends GutTest

## A felled tree stays in `_loaded_trees` after it frees itself --
## `ChoppableTree` calls `queue_free()` and leaves the array entry behind
## (see EarthChunkManager._append_if_near's own note, and
## _clear_vegetation_on_cells'). Every consumer of that registry therefore
## has to expect a dead entry.
##
## Reported in play: *"There are tons of errors saying 'Invalid Object base
## for in'"*. That is `step_tree_growth`'s `"planted_at" in tree` meeting a
## freed node, once per felled tree per tick.
##
## The damage is not the log line. A runtime error on a freed base ABORTS
## the enclosing call, so every tree AFTER the dead one in the array is
## skipped -- exactly the failure `_append_if_near` already documents
## ("every obstacle AFTER the dead one went unseen and creatures walked
## through standing trees"). So each test here puts the corpse FIRST and
## asserts the live tree behind it was still served.
##
## Same direct-injection shape as test_earth_chunk_manager_pollination.gd --
## never the slow real update().

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")

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


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _tree_at(position: Vector2) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = position
	tree.species_bias = ForageScheduler.new().genome_for(position).species_bias
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	var bucket: Array = manager._loaded_trees.get(_CHUNK, [])
	bucket.append(tree)
	manager._loaded_trees[_CHUNK] = bucket
	return tree


## Felling, as the registry really sees it: the node is gone, the entry is not.
func _fell(tree: ChoppableTree) -> void:
	tree.free()


# -- the reported error: step_tree_growth ----------------------------------

func test_a_felled_tree_does_not_stop_the_sapling_behind_it_from_growing():
	var dead := _tree_at(Vector2(100, 100))
	var sapling := _tree_at(Vector2(300, 100))
	sapling.planted_at = 10.0
	var before: float = sapling.growth_scale
	manager.set_world_age_seconds(10.0 + 60.0 * 60.0 * 24.0 * 400.0)
	_fell(dead)

	manager.step_tree_growth()

	assert_ne(
		sapling.growth_scale, before,
		"the sapling behind the felled tree must still be aged"
	)


# -- the same registry, the same hazard, the other unguarded walks ---------

func test_a_felled_tree_does_not_hide_the_position_of_the_tree_behind_it():
	var dead := _tree_at(Vector2(100, 100))
	var standing := _tree_at(Vector2(300, 100))
	_fell(dead)

	var positions: Array = manager._loaded_tree_positions()

	assert_has(positions, standing.position, "the standing tree is still there to be found")
	assert_eq(positions.size(), 1, "and the felled one is not reported as a position")


func test_a_felled_tree_does_not_stop_the_tree_behind_it_from_turning_its_leaves():
	var dead := _tree_at(Vector2(100, 100))
	var standing := _tree_at(Vector2(300, 100))
	_fell(dead)

	manager.sync_tree_season()

	assert_ne(
		standing.current_season(), "",
		"the tree behind the felled one must still be reached by the season pass"
	)


## The registry must not grow corpses forever either: a chunk that is never
## unloaded would otherwise accumulate one dead entry per tree ever felled,
## each one costing a validity check on every walk of the array.
func test_the_registry_drops_a_felled_tree_rather_than_keeping_its_corpse():
	var dead := _tree_at(Vector2(100, 100))
	_tree_at(Vector2(300, 100))
	_fell(dead)

	manager.step_tree_growth()

	assert_eq(manager._loaded_trees[_CHUNK].size(), 1)
	for tree in manager._loaded_trees[_CHUNK]:
		assert_true(is_instance_valid(tree), "only live trees are left in the registry")
