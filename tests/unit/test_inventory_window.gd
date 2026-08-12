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


# -- refresh() must be a no-op when called repeatedly with unchanged data ----
#
# World calls refresh() every frame while the window is visible (see
## World._update_inventory_window), not just on an actual inventory change.
# Before this, refresh() unconditionally destroyed and recreated every slot's
# Control each call -- no Control instance survived more than one frame, so
# Godot's native hover tooltip (which needs the mouse over the SAME instance
# continuously) could never complete its timer. Reported as "no info on
# hover" even though the tooltip text itself was always correct.

func test_repeated_identical_refresh_keeps_the_same_slot_control_instance():
	var stacks := [ItemStack.new(catalog.make("campfire"), 2)]
	window.refresh(stacks, {}, 0.0, 12)
	var first_slot := window._grid.get_child(0)

	window.refresh(stacks, {}, 0.0, 12)  # identical inputs, e.g. next frame's poll

	assert_eq(window._grid.get_child(0), first_slot, "an unchanged refresh should not recreate slot Controls")


func test_refresh_with_actually_different_stacks_does_rebuild():
	window.refresh([ItemStack.new(catalog.make("campfire"), 2)], {}, 0.0, 12)
	var first_slot := window._grid.get_child(0)

	window.refresh([ItemStack.new(catalog.make("rock"), 1)], {}, 0.0, 12)

	assert_ne(window._grid.get_child(0), first_slot, "a real inventory change must still rebuild the grid")


## Reproduces the reported live bug (Godot log: "Attempted to free a locked
## object (calling or emitting)" from inside refresh()): clicking an item
## slot synchronously triggers World -> Player -> InventoryWindow.refresh()
## again (see _on_item_gui_input/World._on_inventory_item_clicked), all
## still on that very slot Control's own gui_input call stack. The slot is
## "locked" (mid-signal-emission on itself) for that whole chain --
## Object.free() refuses to free a locked object, which used to abort the
## rebuild partway through and leave the grid showing only some items
## ("hides all other items in inventory").
func test_refresh_survives_being_called_from_within_a_slots_own_click_handler():
	var stacks := [
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
		ItemStack.new(catalog.make("rock"), 5),
	]
	window.refresh(stacks, {}, 0.0, 12)

	window.item_clicked.connect(func(_item_id):
		window.refresh(stacks, {"weapon": catalog.make("fishing_rod")}, 0.0, 12)
	)

	var fishing_rod_slot: Control = window._grid.get_child(1)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	fishing_rod_slot.gui_input.emit(event)  # what a real click ultimately does

	assert_eq(window._grid.get_child_count(), 12, "the grid should still show every slot, not just the one clicked")


func test_refresh_rebuilds_when_only_the_equipped_paperdoll_changes():
	var sword := catalog.make("iron_sword")
	window.refresh([], {}, 0.0, 12)
	var icon: TextureRect = window._paperdoll_icons["weapon"]
	assert_null(icon.texture)

	window.refresh([], {"weapon": sword}, 0.0, 12)

	assert_not_null(icon.texture)
