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


# -- reordering (dragging one item onto another in the inventory grid) -------

func test_swap_slots_exchanges_two_stacks():
	inventory.add(_meat(), 3)
	inventory.add(_hide(), 2)

	inventory.swap_slots(0, 1)

	assert_eq(inventory.stacks()[0].item.id, "hide")
	assert_eq(inventory.stacks()[1].item.id, "meat")


func test_swap_slots_with_itself_changes_nothing():
	inventory.add(_meat(), 3)
	inventory.swap_slots(0, 0)
	assert_eq(inventory.stacks()[0].item.id, "meat")


func test_swap_slots_out_of_range_is_a_no_op():
	inventory.add(_meat(), 3)
	inventory.swap_slots(0, 99)
	inventory.swap_slots(-1, 0)
	assert_eq(inventory.stacks()[0].item.id, "meat")


func test_swap_slots_preserves_stack_counts():
	inventory.add(_meat(), 3)
	inventory.add(_hide(), 2)

	inventory.swap_slots(0, 1)

	assert_eq(inventory.stacks()[0].count, 2)
	assert_eq(inventory.stacks()[1].count, 3)


func test_move_to_end_puts_a_stack_last():
	inventory.add(_meat(), 3)
	inventory.add(_hide(), 2)

	inventory.move_to_end(0)

	assert_eq(inventory.stacks()[1].item.id, "meat")


func test_move_to_end_out_of_range_is_a_no_op():
	inventory.add(_meat(), 3)
	inventory.move_to_end(99)
	assert_eq(inventory.stacks()[0].item.id, "meat")


# --- containers: a loaded bottle is not an empty one ------------------------
# (docs/concept/capture_dsl.md. Found at the 2026-09-05 merge: main started
# granting an empty glass bottle from the start, and `add` merged a freshly
# loaded bottle into that stack by id alone -- the creature vanished.
# ItemStack.can_stack_with already knew better; `add` never asked it.)

func _bottle(species: String = "") -> Item:
	var bottle := Item.new("glass_bottle", "Glass Bottle", "material", 20)
	bottle.captive_species = species
	return bottle


func test_a_loaded_container_does_not_merge_into_a_stack_of_empty_ones():
	inventory.add(_bottle(), 1)
	inventory.add(_bottle("monarch"), 1)
	assert_eq(inventory.used_slots(), 2, "same id, different contents -- two stacks")
	var loaded := 0
	for stack in inventory.stacks():
		if stack.item.captive_species == "monarch":
			loaded += stack.count
	assert_eq(loaded, 1, "the creature survives being put in the pack")
	assert_eq(inventory.count_of("glass_bottle"), 2)


func test_two_loaded_containers_of_the_same_creature_still_stack():
	inventory.add(_bottle("monarch"), 1)
	inventory.add(_bottle("monarch"), 1)
	assert_eq(inventory.used_slots(), 1)


func test_count_of_and_has_can_ask_for_one_kind_of_contents_only():
	inventory.add(_bottle("monarch"), 1)
	assert_eq(inventory.count_of("glass_bottle"), 1)
	assert_eq(inventory.count_of("glass_bottle", ""), 0)
	assert_false(inventory.has("glass_bottle", ""))
	inventory.add(_bottle(), 2)
	assert_eq(inventory.count_of("glass_bottle", ""), 2)
	assert_eq(inventory.count_of("glass_bottle", "monarch"), 1)
	assert_true(inventory.has("glass_bottle", ""))
	assert_eq(inventory.count_of("glass_bottle"), 3, "no filter still counts everything")


func test_remove_with_a_contents_filter_never_spends_a_loaded_container():
	inventory.add(_bottle("monarch"), 1)
	inventory.add(_bottle(), 1)
	assert_eq(inventory.remove("glass_bottle", 1, ""), 1)
	assert_eq(inventory.count_of("glass_bottle", ""), 0)
	assert_eq(inventory.count_of("glass_bottle", "monarch"), 1, "the loaded bottle is untouched")
	assert_eq(inventory.remove("glass_bottle", 1, ""), 0, "nothing empty left to remove")
	assert_eq(inventory.count_of("glass_bottle", "monarch"), 1)


func test_remove_without_a_filter_keeps_its_old_meaning():
	inventory.add(_bottle("monarch"), 1)
	assert_eq(inventory.remove("glass_bottle", 1), 1)
	assert_eq(inventory.count_of("glass_bottle"), 0)
