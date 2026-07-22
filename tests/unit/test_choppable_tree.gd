extends GutTest

const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")

var tree: ChoppableTree


func before_each():
	tree = ChoppableTree.new()
	tree.position = Vector2(50, 50)
	add_child(tree)


func after_each():
	if is_instance_valid(tree):
		remove_child(tree)
		tree.free()


func test_is_added_to_the_tree_group():
	assert_true(tree.is_in_group(ChoppableTree.GROUP_NAME))


func test_take_damage_reduces_health():
	var before := tree.health
	tree.take_damage(5.0)
	assert_eq(tree.health, before - 5.0)


func test_felling_drops_wood_and_sticks_via_the_world_item_bus():
	watch_signals(WorldItemBus)
	tree.take_damage(tree.health)
	# Two stacks: the wood drop and a stick drop (crafting the crude blade
	# needs sticks, and a felled tree is the natural stick source).
	assert_signal_emit_count(WorldItemBus, "item_dropped", 2)
	var second_stack = get_signal_parameters(WorldItemBus, "item_dropped", 1)[0]
	assert_eq(second_stack.item.id, "stick")


func test_felling_frees_the_node():
	tree.take_damage(tree.health)
	assert_true(tree.is_queued_for_deletion())


func test_a_non_lethal_hit_does_not_drop_wood_or_free_the_tree():
	watch_signals(WorldItemBus)
	tree.take_damage(1.0)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)
	assert_false(tree.is_queued_for_deletion())
