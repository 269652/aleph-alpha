extends GutTest

## Red-first spec for the smallest real per-NPC/household inventory
## (docs/concept/npc_instructions.md's `inventory_at_least` primitive needs
## a real Dictionary of item_id -> int count to check against; before this,
## NpcMarker._instruction_frame() always reported an empty inventory,
## honestly, because nothing real existed to read). This is deliberately NOT
## a general-purpose inventory system -- no capacity limits, no stacking
## rules, no UI, no shop/crafting integration -- just pure add/remove/count
## helpers over a plain Dictionary, mirroring the pure-static-module pattern
## npc_instruction_primitives.gd already uses.
##
## add/remove are pure: they return a NEW Dictionary rather than mutating
## the one passed in, the same "caller stores the result" contract
## pet_loyalty.gd's feed()/neglect() already establish for a different
## piece of per-entity state.

const NpcInventory = preload("res://src/world/npc_inventory.gd")


# --- count_of ----------------------------------------------------------------

func test_count_of_an_absent_item_is_zero():
	assert_eq(NpcInventory.count_of({}, "wood"), 0)


func test_count_of_reads_the_stored_count():
	assert_eq(NpcInventory.count_of({"wood": 5}, "wood"), 5)


# --- add -----------------------------------------------------------------------

func test_add_creates_a_new_entry_for_an_unheld_item():
	var result: Dictionary = NpcInventory.add({}, "wood", 3)
	assert_eq(NpcInventory.count_of(result, "wood"), 3)


func test_add_increases_an_existing_entrys_count():
	var result: Dictionary = NpcInventory.add({"wood": 5}, "wood", 2)
	assert_eq(NpcInventory.count_of(result, "wood"), 7)


func test_add_does_not_mutate_the_passed_in_dictionary():
	var original := {"wood": 5}
	NpcInventory.add(original, "wood", 2)
	assert_eq(original["wood"], 5, "add must be pure -- the caller's Dictionary is untouched")


func test_add_of_zero_or_fewer_is_a_no_op():
	var result: Dictionary = NpcInventory.add({"wood": 5}, "wood", 0)
	assert_eq(NpcInventory.count_of(result, "wood"), 5)
	var negative_result: Dictionary = NpcInventory.add({"wood": 5}, "wood", -3)
	assert_eq(NpcInventory.count_of(negative_result, "wood"), 5)


# --- remove: fails closed / clamps at 0, never negative, never crashes -------

func test_remove_decreases_an_existing_entrys_count():
	var result: Dictionary = NpcInventory.remove({"wood": 5}, "wood", 2)
	assert_eq(NpcInventory.count_of(result, "wood"), 3)


func test_remove_more_than_held_clamps_at_zero_rather_than_going_negative():
	var result: Dictionary = NpcInventory.remove({"wood": 5}, "wood", 999)
	assert_eq(NpcInventory.count_of(result, "wood"), 0)


func test_remove_from_an_item_never_held_never_crashes_and_stays_at_zero():
	var result: Dictionary = NpcInventory.remove({}, "wood", 5)
	assert_eq(NpcInventory.count_of(result, "wood"), 0)


func test_remove_does_not_mutate_the_passed_in_dictionary():
	var original := {"wood": 5}
	NpcInventory.remove(original, "wood", 2)
	assert_eq(original["wood"], 5, "remove must be pure -- the caller's Dictionary is untouched")


func test_remove_of_zero_or_fewer_is_a_no_op():
	var result: Dictionary = NpcInventory.remove({"wood": 5}, "wood", 0)
	assert_eq(NpcInventory.count_of(result, "wood"), 5)
	var negative_result: Dictionary = NpcInventory.remove({"wood": 5}, "wood", -3)
	assert_eq(NpcInventory.count_of(negative_result, "wood"), 5)


# --- add/remove compose --------------------------------------------------------

func test_add_then_remove_round_trips_to_the_original_count():
	var after_add: Dictionary = NpcInventory.add({"wood": 5}, "wood", 10)
	var after_remove: Dictionary = NpcInventory.remove(after_add, "wood", 10)
	assert_eq(NpcInventory.count_of(after_remove, "wood"), 5)
