extends GutTest

## Hotbar: which item id sits in each hotbar slot. Previously the hotbar just
## mirrored the first N inventory stacks with no way to control it (so an item
## further down your pack could never be put on a key); this makes slots
## explicitly assignable (drag an item onto a slot) while still auto-filling
## empty slots so new pickups keep showing up on their own.

const Hotbar = preload("res://src/gameplay/hotbar.gd")

var hotbar: Hotbar


func before_each():
	hotbar = Hotbar.new(5)


func test_starts_empty():
	for i in 5:
		assert_eq(hotbar.item_id_at(i), "")


func test_assign_puts_an_item_in_a_slot():
	hotbar.assign(2, "fishing_rod")
	assert_eq(hotbar.item_id_at(2), "fishing_rod")


func test_assign_replaces_whatever_was_in_that_slot():
	hotbar.assign(0, "iron_sword")
	hotbar.assign(0, "fishing_rod")
	assert_eq(hotbar.item_id_at(0), "fishing_rod")


## Dragging an item onto a slot it's already in elsewhere should move it, not
## leave a duplicate on two keys.
func test_assigning_an_item_already_in_another_slot_moves_it():
	hotbar.assign(0, "fishing_rod")
	hotbar.assign(3, "fishing_rod")
	assert_eq(hotbar.item_id_at(0), "")
	assert_eq(hotbar.item_id_at(3), "fishing_rod")


func test_clear_empties_a_slot():
	hotbar.assign(1, "rock")
	hotbar.clear_slot(1)
	assert_eq(hotbar.item_id_at(1), "")


func test_out_of_range_slots_are_ignored_rather_than_crashing():
	hotbar.assign(-1, "rock")
	hotbar.assign(99, "rock")
	assert_eq(hotbar.item_id_at(-1), "")
	assert_eq(hotbar.item_id_at(99), "")


# -- auto-fill: new items still appear without the player doing anything -----

func test_auto_fill_puts_held_items_into_empty_slots():
	hotbar.auto_fill(["wood", "rock"])
	assert_eq(hotbar.item_id_at(0), "wood")
	assert_eq(hotbar.item_id_at(1), "rock")


func test_auto_fill_never_overwrites_an_explicit_assignment():
	hotbar.assign(0, "fishing_rod")
	hotbar.auto_fill(["wood", "rock"])
	assert_eq(hotbar.item_id_at(0), "fishing_rod", "an assigned slot must survive auto-fill")
	assert_eq(hotbar.item_id_at(1), "wood")


func test_auto_fill_does_not_duplicate_an_already_assigned_item():
	hotbar.assign(3, "wood")
	hotbar.auto_fill(["wood", "rock"])
	var wood_slots := 0
	for i in 5:
		if hotbar.item_id_at(i) == "wood":
			wood_slots += 1
	assert_eq(wood_slots, 1, "an item already on the bar shouldn't also auto-fill elsewhere")


func test_auto_fill_stops_when_slots_run_out():
	hotbar.auto_fill(["a", "b", "c", "d", "e", "f", "g"])
	for i in 5:
		assert_ne(hotbar.item_id_at(i), "")


## An item you no longer hold shouldn't keep occupying a key.
func test_prune_missing_clears_slots_for_items_no_longer_held():
	hotbar.assign(0, "fishing_rod")
	hotbar.assign(1, "wood")
	hotbar.prune_missing(["wood"])
	assert_eq(hotbar.item_id_at(0), "")
	assert_eq(hotbar.item_id_at(1), "wood")
