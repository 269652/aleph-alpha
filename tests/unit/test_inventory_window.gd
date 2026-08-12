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


# -- drag and drop (reorder within the grid / drag out to the hotbar) --------

func test_item_slots_carry_a_drag_payload_naming_their_item_and_index():
	window.refresh([
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
	], {}, 0.0, 12)

	var payload = window._grid.get_child(1).drag_payload
	assert_eq(payload["item_id"], "fishing_rod")
	assert_eq(payload["index"], 1)
	assert_eq(payload["source"], InventoryWindow.DRAG_SOURCE_INVENTORY)


func test_item_slots_accept_an_inventory_drag_but_not_a_foreign_one():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)
	var slot = window._grid.get_child(0)

	assert_true(slot._can_drop_data(Vector2.ZERO, {"source": InventoryWindow.DRAG_SOURCE_INVENTORY, "index": 1}))
	assert_false(slot._can_drop_data(Vector2.ZERO, {"source": "somewhere_else"}))


func test_dropping_one_item_onto_another_emits_items_reordered():
	window.refresh([
		ItemStack.new(catalog.make("iron_sword"), 1),
		ItemStack.new(catalog.make("fishing_rod"), 1),
	], {}, 0.0, 12)

	var received := []
	window.items_reordered.connect(func(from_index, to_index): received.append([from_index, to_index]))

	# Drag slot 1 (rod) onto slot 0 (sword).
	window._grid.get_child(0)._drop_data(Vector2.ZERO, window._grid.get_child(1).drag_payload)

	assert_eq(received, [[1, 0]])


## Empty trailing slots take drops too (drag an item into empty space), so a
## reorder isn't limited to swapping with another occupied slot.
func test_dropping_onto_an_empty_slot_also_emits_items_reordered():
	window.refresh([ItemStack.new(catalog.make("iron_sword"), 1)], {}, 0.0, 12)

	var received := []
	window.items_reordered.connect(func(from_index, to_index): received.append([from_index, to_index]))

	window._grid.get_child(5)._drop_data(Vector2.ZERO, window._grid.get_child(0).drag_payload)

	assert_eq(received, [[0, 5]])


func test_empty_slots_are_not_themselves_draggable():
	window.refresh([], {}, 0.0, 12)
	assert_null(window._grid.get_child(0)._get_drag_data(Vector2.ZERO))


func test_refresh_rebuilds_when_only_the_equipped_paperdoll_changes():
	var sword := catalog.make("iron_sword")
	window.refresh([], {}, 0.0, 12)
	var icon: TextureRect = window._paperdoll_icons["weapon"]
	assert_null(icon.texture)

	window.refresh([], {"weapon": sword}, 0.0, 12)

	assert_not_null(icon.texture)
