extends GutTest

## SkillTreeWindow: the skill-tree spend menu (toggle K). Covers the same
## class of bug test_inventory_window.gd pins for InventoryWindow -- refresh()
## rebuilding rows can run synchronously from inside a row's OWN click
## handler.

const SkillTreeWindow = preload("res://scenes/skill_tree_window.gd")

var window: SkillTreeWindow


func before_each():
	window = SkillTreeWindow.new()
	add_child(window)


func after_each():
	window.free()


func test_refresh_builds_rows_for_nodes_and_keystones():
	window.refresh(10, {}, {})
	assert_gt(window._list.get_child_count(), 0)


## Reproduces the real bug (Godot log: "Attempted to free a locked object
## (calling or emitting)" from inside refresh()): clicking an allocatable row
## synchronously triggers World -> Player -> refresh() again, all still on
## that very row Control's own gui_input call stack (see _row's connected
## handler). The row is "locked" (mid-signal-emission on itself) for that
## whole chain -- Object.free() refuses to free a locked object, which used
## to abort the rebuild partway through.
func test_refresh_survives_being_called_from_within_a_rows_own_click_handler():
	# Enough unspent points that every stat node is affordable/clickable.
	window.refresh(1000, {}, {})
	var row_count_before := window._list.get_child_count()
	assert_gt(row_count_before, 0)

	window.node_allocated.connect(func(_node_id):
		window.refresh(1000, {}, {})
	)

	# First row is a heading (non-interactive); the first real node row is
	# index 1.
	var row: Control = window._list.get_child(1)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)  # what a real click ultimately does

	assert_eq(window._list.get_child_count(), row_count_before, "the skill list should still show every row, not be corrupted")
