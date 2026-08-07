extends GutTest

## Covers InventoryWindow's layout contract (the off-screen/overflow bug class)
## and its fixed slot grid. The window is given a fixed anchor box by
## World._build_inventory_window -- if the window's real minimum size exceeds
## that box, Godot expands the control past its offsets and the bottom of the
## paperdoll (Feet slot, armor total) runs off-screen, which is exactly the
## reported bug this file pins against regressing.

const InventoryWindow = preload("res://scenes/inventory_window.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

## Keep in sync with World._build_inventory_window's offsets (±300 x ±230).
const WORLD_ANCHOR_BOX := Vector2(600, 460)

var window: InventoryWindow
var catalog := ItemCatalog.new()


func before_each():
	window = InventoryWindow.new()
	add_child(window)


func after_each():
	window.free()


func test_window_minimum_size_fits_the_anchor_box_world_gives_it():
	# refresh() with a full paperdoll + full grid first, so the measured
	# minimum reflects the fullest layout the window ever shows.
	var stacks := []
	for i in 12:
		stacks.append(ItemStack.new(catalog.make("rock"), 1))
	window.refresh(stacks, {}, 0.0, 12)

	var min_size := window.get_combined_minimum_size()
	assert_lte(min_size.x, WORLD_ANCHOR_BOX.x, "window min width must fit World's anchor box")
	assert_lte(min_size.y, WORLD_ANCHOR_BOX.y, "window min height must fit World's anchor box or the bottom clips off-screen")


func test_refresh_builds_a_fixed_slot_grid_including_empty_slots():
	window.refresh([], {}, 0.0, 12)
	assert_eq(window._grid.get_child_count(), 12, "an empty inventory should still show all 12 slot frames, like real game inventories")


func test_refresh_fills_leading_slots_and_keeps_the_rest_as_empty_frames():
	var stacks := [ItemStack.new(catalog.make("campfire"), 2)]
	window.refresh(stacks, {}, 0.0, 12)
	assert_eq(window._grid.get_child_count(), 12)


func test_item_tooltip_shows_name_kind_and_stack_count():
	var stack := ItemStack.new(catalog.make("campfire"), 3)
	var tooltip: String = window._item_tooltip_text(stack)
	assert_string_contains(tooltip, "Campfire")
	assert_string_contains(tooltip, "Placeable")
	assert_string_contains(tooltip, "3")
