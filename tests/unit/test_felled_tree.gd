extends GutTest

## A felled tree lies where it fell until it is cut up (see
## docs/concept/flora.md).
##
## Felling used to delete the tree and spray items on the ground, which reads
## as the tree evaporating. A tree you cut down should be a thing lying there:
## the same trunk and crown, on its side, waiting to be worked.

const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const FelledTree = preload("res://src/rendering/felled_tree.gd")

var _drops: Array = []


func before_each():
	_drops = []
	WorldItemBus.item_dropped.connect(_record)


func after_each():
	if WorldItemBus.item_dropped.is_connected(_record):
		WorldItemBus.item_dropped.disconnect(_record)


func _record(stack, _position) -> void:
	_drops.append(stack)


func _felled() -> ChoppableTree:
	var tree := ChoppableTree.new()
	add_child_autofree(tree)
	tree.take_damage(ChoppableTree.MAX_HEALTH)
	return tree


# -- felling leaves something behind -----------------------------------------

## The tree does not evaporate: it falls over.
func test_felling_leaves_the_tree_lying_there():
	var tree := _felled()
	assert_true(tree.is_felled(), "a felled tree should still be there, on its side")
	assert_false(tree.is_queued_for_deletion())


## And drops nothing yet -- the wood is still in the trunk.
func test_felling_alone_yields_no_wood():
	_felled()
	assert_eq(_drops.size(), 0, "a fallen tree is not a pile of logs yet")


## It is lying down: the same sprite, turned on its side, rather than a
## different drawing.
func test_a_felled_tree_lies_on_its_side():
	var tree := _felled()
	assert_almost_eq(absf(tree.rotation), FelledTree.FALLEN_ROTATION, 0.35)


## Which way it falls depends on the tree, so a cleared wood is not a row of
## trunks all pointing the same way.
func test_trees_do_not_all_fall_the_same_way():
	var directions := {}
	for seed_value in 40:
		directions[FelledTree.fall_direction(seed_value)] = true
	assert_gt(directions.size(), 1, "every tree falls the same way")


func test_a_given_tree_always_falls_the_same_way():
	assert_eq(FelledTree.fall_direction(7), FelledTree.fall_direction(7))


# -- cutting it up -----------------------------------------------------------

## Working a fallen trunk is what actually produces the wood.
func test_chopping_a_fallen_tree_yields_wood():
	var tree := _felled()
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)
	var wood := 0
	for stack in _drops:
		if stack.item.id == "wood":
			wood += stack.count
	assert_gt(wood, 0, "cutting up a trunk should give wood")


func test_a_trunk_takes_several_cuts():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)
	assert_false(
		tree.is_queued_for_deletion(), "one swing should not clear a whole trunk"
	)


func test_a_worked_out_trunk_is_gone():
	var tree := _felled()
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)
	assert_true(tree.is_queued_for_deletion(), "a trunk cut up should be gone")


## A bigger tree is more wood -- cutting up a sapling is not the same haul as
## cutting up an oak.
func test_a_bigger_tree_yields_more_wood():
	assert_gt(FelledTree.wood_for(1.0), FelledTree.wood_for(0.4))


func test_even_a_small_tree_yields_something():
	assert_gt(FelledTree.wood_for(0.2), 0)


## The whole trunk comes out across its cuts, rather than each cut giving a
## full tree's worth.
func test_the_cuts_add_up_to_roughly_the_whole_trunk():
	var per_cut := FelledTree.wood_per_cut(1.0) * FelledTree.CUTS_TO_CLEAR
	assert_gte(per_cut, FelledTree.wood_for(1.0))
	assert_lte(per_cut, FelledTree.wood_for(1.0) + FelledTree.CUTS_TO_CLEAR)
