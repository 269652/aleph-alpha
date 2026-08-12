extends GutTest

## CraftingWindow: the recipe list (toggle C). Covers the same class of bug
## test_inventory_window.gd pins for InventoryWindow -- refresh() rebuilding
## rows can run synchronously from inside a row's OWN click handler.

const CraftingWindow = preload("res://scenes/crafting_window.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

var window: CraftingWindow


func before_each():
	window = CraftingWindow.new()
	add_child(window)


func after_each():
	window.free()


func test_refresh_builds_one_row_per_recipe():
	window.refresh({})
	assert_gt(window._list.get_child_count(), 0)


## Reproduces the real bug (Godot log: "Attempted to free a locked object
## (calling or emitting)" from inside refresh()): clicking a craftable row
## synchronously triggers World -> Player.craft() -> refresh() again, all
## still on that very row Control's own gui_input call stack (see
## _on_row_gui_input). The row is "locked" (mid-signal-emission on itself)
## for that whole chain -- Object.free() refuses to free a locked object,
## which used to abort the rebuild partway through.
func test_refresh_survives_being_called_from_within_a_rows_own_click_handler():
	# A counts dict affording every recipe (every known item id, generously
	# stocked), so every row is clickable.
	var counts := {}
	for item_id in ItemCatalog.new().known_ids():
		counts[item_id] = 999
	window.refresh(counts)
	var row_count_before := window._list.get_child_count()
	assert_gt(row_count_before, 0)

	window.craft_requested.connect(func(_recipe_id):
		window.refresh(counts)
	)

	var row: Control = window._list.get_child(0)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)  # what a real click ultimately does

	assert_eq(window._list.get_child_count(), row_count_before, "the recipe list should still show every row, not be corrupted")
