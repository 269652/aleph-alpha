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


## And drops nothing yet -- the timber is still in the tree.
func test_felling_alone_yields_no_drops():
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


# -- stage 1: the crown comes off first, as sticks (see
# docs/concept/woodworking.md) -- limbing before bucking, real forestry
# practice, not an invented game step. Does not consume a trunk cut.

func test_the_first_swing_on_a_felled_tree_removes_the_canopy_not_the_trunk():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)
	assert_false(tree.is_queued_for_deletion(), "one swing should never clear a whole trunk")
	var sticks := 0
	for stack in _drops:
		if stack.item.id == "stick":
			sticks += stack.count
	assert_gt(sticks, 0, "removing the canopy should give sticks")


func test_canopy_removal_does_not_consume_a_trunk_cut():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)  # every real trunk cut
	assert_true(tree.is_queued_for_deletion(), "canopy removal must not eat into CUTS_TO_CLEAR")


# -- stage 2: the bare trunk is bucked into logs -----------------------------

## Working a bare trunk is what actually produces logs.
func test_chopping_a_bare_trunk_yields_logs():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off first
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)
	var logs := 0
	for stack in _drops:
		if stack.item.id == "log":
			logs += stack.count
	assert_gt(logs, 0, "bucking a bare trunk should give logs")


func test_a_bare_trunk_takes_several_cuts():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # first real trunk cut
	assert_false(
		tree.is_queued_for_deletion(), "one trunk swing should not clear a whole trunk"
	)


func test_a_worked_out_trunk_is_gone():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)
	assert_true(tree.is_queued_for_deletion(), "a trunk cut up should be gone")


## A bigger tree is more timber -- cutting up a sapling is not the same haul
## as cutting up an oak.
func test_a_bigger_tree_yields_more_timber():
	assert_gt(FelledTree.timber_for(1.0), FelledTree.timber_for(0.4))


func test_even_a_small_tree_yields_something():
	assert_gt(FelledTree.timber_for(0.2), 0)


## The whole trunk comes out across its cuts, rather than each cut giving a
## full tree's worth.
func test_the_cuts_add_up_to_roughly_the_whole_trunk():
	var per_cut := FelledTree.logs_per_cut(1.0) * FelledTree.CUTS_TO_CLEAR
	assert_gte(per_cut, FelledTree.timber_for(1.0))
	assert_lte(per_cut, FelledTree.timber_for(1.0) + FelledTree.CUTS_TO_CLEAR)


# -- sawing: a saw + enough Carpentry turns the whole remaining bare trunk
# straight into construction lumber, in one action, instead of one log per
# swing (see docs/concept/woodworking.md) --------------------------------

func test_sticks_from_canopy_scale_with_tree_size():
	assert_gt(FelledTree.sticks_from_canopy(1.0), FelledTree.sticks_from_canopy(0.3))


func test_beams_and_planks_scale_with_remaining_cuts():
	var one_cut_left := FelledTree.beams_from_trunk(1.0, 1) + FelledTree.planks_from_trunk(1.0, 1)
	var all_cuts_left := (
		FelledTree.beams_from_trunk(1.0, FelledTree.CUTS_TO_CLEAR)
		+ FelledTree.planks_from_trunk(1.0, FelledTree.CUTS_TO_CLEAR)
	)
	assert_gt(all_cuts_left, one_cut_left)


func test_sawing_yields_both_beams_and_planks():
	assert_gt(FelledTree.beams_from_trunk(1.0, FelledTree.CUTS_TO_CLEAR), 0)
	assert_gt(FelledTree.planks_from_trunk(1.0, FelledTree.CUTS_TO_CLEAR), 0)


func test_saw_up_fails_on_a_standing_tree():
	var tree := ChoppableTree.new()
	add_child_autofree(tree)
	assert_false(tree.saw_up())


func test_saw_up_fails_while_the_canopy_is_still_on():
	var tree := _felled()
	assert_false(tree.saw_up())


func test_saw_up_succeeds_on_a_bare_trunk_and_clears_it_in_one_action():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off
	assert_true(tree.saw_up())
	assert_true(tree.is_queued_for_deletion())
	var beams := 0
	var planks := 0
	for stack in _drops:
		if stack.item.id == "beam":
			beams += stack.count
		elif stack.item.id == "plank":
			planks += stack.count
	assert_gt(beams, 0)
	assert_gt(planks, 0)


func test_saw_up_fails_once_the_trunk_is_already_fully_worked():
	var tree := _felled()
	tree.take_damage(ChoppableTree.MAX_HEALTH)  # canopy off
	for step in FelledTree.CUTS_TO_CLEAR:
		tree.take_damage(ChoppableTree.MAX_HEALTH)
	assert_true(tree.is_queued_for_deletion(), "precondition: the trunk is fully worked")
	assert_false(tree.saw_up())
