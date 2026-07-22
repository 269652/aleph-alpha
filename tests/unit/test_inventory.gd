extends GutTest

const Item = preload("res://src/gameplay/item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

var inventory: Inventory


func before_each():
	inventory = Inventory.new(4)  # 4 slots


func _meat() -> Item:
	return Item.new("meat", "Meat", "food", 20)


func _hide() -> Item:
	return Item.new("hide", "Hide", "material", 40)


func test_starts_empty():
	assert_eq(inventory.count_of("meat"), 0)
	assert_false(inventory.has("meat"))
	assert_eq(inventory.used_slots(), 0)


func test_adding_an_item_stores_it():
	inventory.add(_meat(), 3)
	assert_eq(inventory.count_of("meat"), 3)
	assert_true(inventory.has("meat"))
	assert_eq(inventory.used_slots(), 1)


func test_adding_the_same_item_stacks_into_one_slot():
	inventory.add(_meat(), 3)
	inventory.add(_meat(), 4)
	assert_eq(inventory.count_of("meat"), 7)
	assert_eq(inventory.used_slots(), 1)


func test_adding_beyond_a_stack_spills_into_another_slot():
	inventory.add(_meat(), 18)
	inventory.add(_meat(), 5)  # 23 total, stack cap 20 -> 20 + 3 in a new slot
	assert_eq(inventory.count_of("meat"), 23)
	assert_eq(inventory.used_slots(), 2)


func test_different_items_use_separate_slots():
	inventory.add(_meat(), 3)
	inventory.add(_hide(), 2)
	assert_eq(inventory.used_slots(), 2)
	assert_eq(inventory.count_of("meat"), 3)
	assert_eq(inventory.count_of("hide"), 2)


func test_add_returns_the_amount_that_did_not_fit_when_full():
	# 4 slots, meat stacks to 20 -> capacity 80.
	var overflow := inventory.add(_meat(), 100)
	assert_eq(overflow, 20)
	assert_eq(inventory.count_of("meat"), 80)


func test_is_full_true_only_when_all_slots_are_used():
	assert_false(inventory.is_full())
	inventory.add(Item.new("a", "A", "material", 1), 1)
	inventory.add(Item.new("b", "B", "material", 1), 1)
	inventory.add(Item.new("c", "C", "material", 1), 1)
	assert_false(inventory.is_full())
	inventory.add(Item.new("d", "D", "material", 1), 1)
	assert_true(inventory.is_full())


func test_remove_reduces_the_count():
	inventory.add(_meat(), 7)
	var removed := inventory.remove("meat", 3)
	assert_eq(removed, 3)
	assert_eq(inventory.count_of("meat"), 4)


func test_remove_more_than_present_removes_only_what_exists():
	inventory.add(_meat(), 2)
	var removed := inventory.remove("meat", 10)
	assert_eq(removed, 2)
	assert_eq(inventory.count_of("meat"), 0)
	assert_eq(inventory.used_slots(), 0)


func test_stacks_lists_current_contents():
	inventory.add(_meat(), 3)
	inventory.add(_hide(), 2)
	var ids := []
	for stack in inventory.stacks():
		ids.append(stack.item.id)
	assert_true(ids.has("meat"))
	assert_true(ids.has("hide"))
