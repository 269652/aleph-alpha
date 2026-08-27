extends GutTest

## SkillTreeWindow: the skill-tree spend menu (toggle L). Covers the same
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


## land_sense (see KeystonePassive) is a REVEAL keystone, not a stat bump --
## its row must show its real description, not the ordinary "+0.0 stat"
## phrasing every other keystone row uses (see KeystonePassive.keystone_info's
## own doc comment on why its stat_name is deliberately empty).
func test_keystone_row_shows_a_description_for_a_reveal_keystone_not_a_bonus_number():
	window.refresh(1000, {}, {})
	var found := false
	for row in window._list.get_children():
		if not (row is HBoxContainer):
			continue
		var label := row.get_child(0) as Label
		if label.text.findn("Land Sense") == -1:
			continue
		found = true
		assert_eq(label.text.findn("+0"), -1, "reveal keystone row should not show a '+0' bonus number")
	assert_true(found, "expected a Land Sense keystone row to be rendered")


# -- rows must read as prose, not as internal identifiers -------------------
#
# Every row was formatted straight off skill_tree.gd's own table keys:
# "Vitality 1  +10.0 max_health  (1 pt)". max_health / stamina_regen /
# attack_damage / meat_yield / carpentry_level are internal stat identifiers,
# and "Berserkers Fury" is a String.capitalize() of an identifier that cannot
# produce the apostrophe.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Every internal stat key skill_tree.gd's/keystone_passive.gd's tables use.
const RAW_STAT_KEYS := [
	"max_health", "stamina_regen", "attack_damage", "meat_yield", "carpentry_level",
]


## World._build_skill_window anchors this window at PRESET_CENTER_LEFT with
## offset_left 8 / offset_top -150 in a 960x540 viewport, and Godot grows a
## Control down/right from its offsets when its own minimum exceeds them --
## so the room genuinely available before anything runs off-screen is 952
## wide and 420 tall (top -150 through the viewport's bottom edge at +270).
const WORLD_AVAILABLE_BOX := Vector2(952, 420)


func _row_labels() -> Array:
	var labels := []
	for row in window._list.get_children():
		if row is HBoxContainer:
			labels.append(row.get_child(0) as Label)
	return labels


func test_no_skill_row_ever_shows_a_raw_internal_stat_key():
	window.refresh(1000, {}, {})
	for label in _row_labels():
		for key in RAW_STAT_KEYS:
			assert_eq(label.text.find(key), -1,
				"row leaked the internal key %s: %s" % [key, label.text])


func test_node_rows_read_as_a_named_rank_not_a_raw_identifier():
	window.refresh(1000, {}, {})
	var texts := []
	for label in _row_labels():
		texts.append(label.text)
	var joined: String = "\n".join(texts)
	assert_string_contains(joined, "Vitality II")
	assert_string_contains(joined, "Maximum Health")
	assert_eq(joined.find("Vitality 2"), -1, "a rank is a numeral, not a table suffix")


func test_keystone_rows_show_their_written_display_name_not_a_capitalized_identifier():
	window.refresh(1000, {}, {})
	var texts := []
	for label in _row_labels():
		texts.append(label.text)
	var joined: String = "\n".join(texts)
	assert_string_contains(joined, "Berserker's Fury")
	assert_eq(joined.find("Berserkers Fury"), -1,
		"an apostrophe cannot be derived from an identifier -- it has to be written down")


# -- the window has to be wide enough for its own rows ----------------------
#
# The longest row needs roughly 400px and the window declared 320, with the
# ScrollContainer's horizontal scrolling DISABLED -- so the text was simply
# cut off ("left-aligned in half the panel"). Deliberately measured WITHOUT
# giving the title Label autowrap_mode: autowrap collapses a Label's
# horizontal minimum toward zero and would make this pass vacuously (the same
# trap inventory_window.gd:_build_inventory_column documents for its heading).

func test_the_widest_skill_row_fits_the_windows_own_declared_width():
	window.refresh(1000, {}, {})
	var widest := 0.0
	var widest_text := ""
	for row in window._list.get_children():
		if not (row is HBoxContainer):
			continue  # section headings, not rows
		var row_width: float = row.get_combined_minimum_size().x
		if row_width > widest:
			widest = row_width
			widest_text = (row.get_child(0) as Label).text
	var usable: float = window.custom_minimum_size.x - 2.0 * UiTheme.CONTENT_MARGIN
	assert_lte(widest, usable,
		"a skill row (%.0fpx: '%s') is wider than the window's %.0fpx of usable width, so its text is clipped"
			% [widest, widest_text, usable])


func test_the_window_still_fits_the_room_world_actually_gives_it():
	window.refresh(1000, {}, {})
	var min_size := window.get_combined_minimum_size()
	assert_lte(min_size.x, WORLD_AVAILABLE_BOX.x, "the window must not run off the right edge")
	assert_lte(min_size.y, WORLD_AVAILABLE_BOX.y, "the window must not run off the bottom edge")


## A window you read text off is a surface, not a HUD overlay -- the world
## behind it must not show through (reported live against this window).
func test_the_windows_panel_is_fully_opaque_so_the_world_cannot_show_through():
	var style := window.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style)
	assert_eq(style.bg_color.a, 1.0, "a gameplay window's panel must be fully opaque")
