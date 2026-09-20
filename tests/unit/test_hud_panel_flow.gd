extends GutTest

## Panels occupy space and push their neighbours down, rather than being
## placed at coordinates chosen against whatever happened to be there
## (docs/concept/hud.md).
##
## Reported with both open: *"The Town Panel and Warehouse / Building panel
## overlap.. a panel should occupy space and make other panels render below
## it.. don't use fixed coords"*. The HUD column system already says exactly
## that in its own doc comment -- "each builder simply adds to the column it
## belongs in and never positions itself against its neighbour's height" --
## and the building readout was the one card that never joined, sitting at
## PRESET_CENTER_RIGHT with hand-picked offsets while the right column grew
## down into it.

const HousePanel = preload("res://scenes/house_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const COLUMN_WIDTH := 320.0


func _source() -> String:
	return FileAccess.get_file_as_string("res://scenes/world.gd")


func _body(function_name: String) -> String:
	var source := _source()
	var start := source.find("func %s" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


# -- the layout property itself, driven for real ---------------------------

func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.theme = UiTheme.new().build_theme()
	column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	column.add_theme_constant_override("separation", 4)
	add_child_autofree(column)
	return column


## Opened, because HousePanel._ready() hides itself: it is the readout a
## click on a building opens, and a hidden card takes no room at all (which
## is exactly what test_a_hidden_panel_leaves_no_hole_behind_it pins).
func _opened_panel(column: VBoxContainer) -> HousePanel:
	var panel := HousePanel.new()
	column.add_child(panel)
	panel.visible = true
	return panel


func _filler(height: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160.0, height)
	return card


## The whole of the report, as a property: a card above takes its own room
## and the one below starts under it.
func test_a_card_below_another_starts_under_it_rather_than_over_it():
	var column := _column()
	var above := _filler(120.0)
	column.add_child(above)
	var panel := _opened_panel(column)
	await get_tree().process_frame
	assert_gt(panel.get_global_rect().size.y, 0.0, "the premise: the panel has a real height")
	assert_false(
		above.get_global_rect().intersects(panel.get_global_rect()),
		"the two cards overlap: %s vs %s" % [
			str(above.get_global_rect()), str(panel.get_global_rect())
		]
	)
	assert_gte(
		panel.get_global_rect().position.y, above.get_global_rect().end.y,
		"the building readout starts below the card above it"
	)


## A taller neighbour pushes it further down -- which is what "occupies
## space" means, and what a hand-picked offset cannot do.
func test_a_taller_card_above_pushes_it_further_down():
	var near := _column()
	var short_card := _filler(60.0)
	near.add_child(short_card)
	var near_panel := _opened_panel(near)

	var far := _column()
	var tall_card := _filler(240.0)
	far.add_child(tall_card)
	var far_panel := _opened_panel(far)

	await get_tree().process_frame
	assert_gt(
		far_panel.position.y, near_panel.position.y,
		"the panel under the taller card sits lower"
	)


## A hidden card takes no room at all, so closing the building readout does
## not leave a hole where it was -- the same property the message stack
## already relies on (hud.md, "The message stack").
func test_a_hidden_panel_leaves_no_hole_behind_it():
	var column := _column()
	var panel := _opened_panel(column)
	var below := _filler(80.0)
	column.add_child(below)
	await get_tree().process_frame
	var with_panel := below.position.y
	assert_gt(with_panel, 0.0, "the premise: the open panel really pushed it down")
	panel.visible = false
	await get_tree().process_frame
	assert_lt(below.position.y, with_panel, "the card below moves up when the panel closes")


# -- and that World really builds it that way ------------------------------

func test_the_building_readout_is_a_card_in_a_column_not_a_hand_placed_panel():
	var body := _body("_build_house_panel")
	assert_true(body.contains("_add_hud_card("), "it joins a column: %s" % body)
	assert_false(body.contains("offset_"), "and sets no coordinates of its own: %s" % body)
	assert_false(body.contains("set_anchors_preset("), "nor anchors: %s" % body)


## The rule, generalised so the next card cannot reintroduce the defect:
## anything that joins a column is positioned BY that column.
func test_no_card_that_joins_a_column_also_places_itself():
	var source := _source()
	var checked := 0
	for chunk in source.split("\nfunc "):
		if not chunk.contains("_add_hud_card("):
			continue
		if chunk.begins_with("_add_hud_card"):
			continue  # the helper itself
		checked += 1
		var name_end := chunk.find("(")
		var function_name := chunk.substr(0, maxi(name_end, 0))
		assert_false(
			chunk.contains("offset_top =") or chunk.contains("offset_bottom ="),
			"%s adds a card to a column AND positions it by hand" % function_name
		)
	assert_gt(checked, 1, "the premise: several builders add cards to columns")


## A card cannot join a column that does not exist yet.
func test_the_columns_are_built_before_any_card_joins_one():
	var ready_body := _body("_ready")
	var columns_at := ready_body.find("_build_hud_columns()")
	var panel_at := ready_body.find("_build_house_panel()")
	assert_gt(columns_at, -1, "the premise: _ready builds the columns")
	assert_gt(panel_at, -1, "the premise: _ready builds the building readout")
	assert_lt(columns_at, panel_at, "the columns come first, or the card has nowhere to go")
