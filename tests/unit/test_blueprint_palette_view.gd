extends GutTest

## The build palette itself (see docs/concept/planner_mode.md, "The build
## palette") -- the real widget, driven for real, not a source-contract
## reading of World.
##
## It is its own Control rather than forty lines inside scenes/world.gd
## for the reason every other panel in this game already is one
## (CreaturePanel, HousePanel): a menu with tabs, a selection and a footer
## is a thing with BEHAVIOUR, and behaviour buried in World can only be
## tested by reading its source.

const BlueprintPaletteView = preload("res://src/ui/blueprint_palette_view.gd")
const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BuildPlan = preload("res://src/world/build_plan.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const HOURS := 12.0

var _view
var _hours_asked_for: Array = []
var _announced: Array = []


func before_each() -> void:
	_hours_asked_for = []
	_announced = []
	_view = BlueprintPaletteView.new()
	add_child_autofree(_view)
	_view.configure(
		UiTheme.new().build_theme(),
		func(blueprint_id: String) -> float:
			_hours_asked_for.append(blueprint_id)
			return HOURS,
		func(item_id: String) -> String:
			return String(item_id).capitalize()
	)
	_view.blueprint_selected.connect(func(blueprint_id: String): _announced.append(blueprint_id))


func _ids_of(category_id: String) -> Array:
	for category in BlueprintPaletteModel.categories():
		if String(category["id"]) == category_id:
			var out: Array = []
			for blueprint_id in category["blueprint_ids"]:
				out.append(blueprint_id)
			return out
	return []


func _shown_ids() -> Array:
	var out: Array = []
	for slot in _view.slots():
		out.append(slot.get_meta("blueprint_id"))
	return out


func test_it_opens_on_the_first_tab_with_nothing_armed():
	assert_eq(_view.shown_category(), String(BlueprintPaletteModel.categories()[0]["id"]))


func test_a_tab_shows_exactly_its_own_categorys_blueprints():
	for category in BlueprintPaletteModel.categories():
		var category_id := String(category["id"])
		_view.show_category(category_id)
		assert_eq(_shown_ids(), _ids_of(category_id), "tab %s" % category_id)


## A row that only ever grows would stack four categories of buttons on
## top of each other by the fourth tab press.
func test_switching_tabs_replaces_the_slots_rather_than_stacking_them():
	_view.show_category(BlueprintPaletteModel.CATEGORY_PRODUCTION)
	var production := _shown_ids().size()
	assert_gt(production, 0, "the premise: production has slots")
	_view.show_category(BlueprintPaletteModel.CATEGORY_CIVIC)
	assert_eq(_shown_ids(), _ids_of(BlueprintPaletteModel.CATEGORY_CIVIC))
	_view.show_category(BlueprintPaletteModel.CATEGORY_PRODUCTION)
	assert_eq(_shown_ids().size(), production, "and back again, still one category's worth")


## "Add Icons not only text" -- both, on every slot. A picture alone trades
## one unreadable menu for another, since a sawmill and a blacksmith are
## both a brown roof at 48 pixels.
func test_every_slot_carries_a_picture_and_a_name():
	for category in BlueprintPaletteModel.categories():
		_view.show_category(String(category["id"]))
		for slot in _view.slots():
			var blueprint_id := String(slot.get_meta("blueprint_id"))
			assert_not_null(slot.icon, "%s has no picture" % blueprint_id)
			assert_eq(
				slot.text, BlueprintPaletteModel.slot_title(blueprint_id),
				"%s has no name" % blueprint_id
			)


func test_a_slots_hover_carries_the_whole_reckoning():
	_view.show_category(BlueprintPaletteModel.CATEGORY_HOMES)
	var slot = _view.slot_for("house_medium")
	assert_not_null(slot, "the premise: a cottage tab holds a house")
	assert_true(slot.tooltip_text.contains(BlueprintPaletteModel.slot_title("house_medium")))
	assert_true(slot.tooltip_text.contains(BlueprintPaletteModel.slot_subtitle("house_medium")))
	assert_true(slot.tooltip_text.contains(BlueprintPaletteModel.cost_text("house_medium")))
	assert_true(slot.tooltip_text.contains(BlueprintPaletteModel.labour_text(HOURS)))


## The hours quoted are asked for THAT blueprint, so the view cannot quote
## one building's job size on another's card.
func test_the_hours_on_a_card_are_asked_for_that_very_blueprint():
	_view.show_category(BlueprintPaletteModel.CATEGORY_PRODUCTION)
	for blueprint_id in _ids_of(BlueprintPaletteModel.CATEGORY_PRODUCTION):
		assert_true(
			_hours_asked_for.has(blueprint_id),
			"%s's card was written without asking how big its job is" % blueprint_id
		)


func test_clicking_a_slot_announces_which_blueprint_it_was():
	_view.show_category(BlueprintPaletteModel.CATEGORY_PRODUCTION)
	_view.slot_for("brewery").pressed.emit()
	assert_eq(_announced, ["brewery"])


func test_exactly_one_slot_reads_as_armed():
	_view.show_category(BlueprintPaletteModel.CATEGORY_HOMES)
	_view.set_selected("house_large")
	var pressed: Array = []
	for slot in _view.slots():
		if slot.button_pressed:
			pressed.append(slot.get_meta("blueprint_id"))
	assert_eq(pressed, ["house_large"])


## Nothing armed is a real state -- planner mode clears the selection every
## time it is left -- so it must read as nothing armed rather than leave a
## slot looking stuck down.
func test_nothing_armed_presses_no_slot_and_says_so():
	_view.show_category(BlueprintPaletteModel.CATEGORY_HOMES)
	_view.set_selected("house_large")
	_view.set_selected("")
	for slot in _view.slots():
		assert_false(slot.button_pressed, "%s is still down" % slot.get_meta("blueprint_id"))
	assert_eq(_view.footer_text(), BlueprintPaletteView.IDLE_TEXT)


## The menu must never sit showing one category while the armed slot is in
## another.
func test_arming_a_blueprint_in_another_category_opens_that_category():
	_view.show_category(BlueprintPaletteModel.CATEGORY_ROADS)
	_view.set_selected("warehouse")
	assert_eq(_view.shown_category(), BlueprintPaletteModel.CATEGORY_CIVIC)
	assert_not_null(_view.slot_for("warehouse"), "and the slot is really there to press")
	assert_true(_view.slot_for("warehouse").button_pressed)


func test_the_footer_names_what_is_armed_and_what_it_will_cost():
	_view.set_selected("house_small")
	var footer: String = _view.footer_text()
	assert_true(footer.contains(BlueprintPaletteModel.slot_title("house_small")), footer)
	assert_true(footer.contains(BlueprintPaletteModel.cost_text("house_small")), footer)
	assert_true(footer.contains(BlueprintPaletteModel.slot_subtitle("house_small")), footer)


## A tab press is a user action, and it must reach whoever is listening the
## same way a slot press does -- but it arms nothing on its own: opening a
## drawer is not choosing what is in it.
func test_opening_a_tab_arms_nothing_by_itself():
	_view.set_selected("house_small")
	_view.show_category(BlueprintPaletteModel.CATEGORY_PRODUCTION)
	assert_eq(_announced, [], "browsing announced a selection")
	for slot in _view.slots():
		assert_false(slot.button_pressed, "%s armed itself" % slot.get_meta("blueprint_id"))


## Measured from the first real render (tools/probe_build_palette.gd):
## drawn in the theme's ordinary pressed shade, the armed slot and the open
## tab were indistinguishable from their neighbours over the card's dark
## background -- a menu whose selection cannot be seen is a menu with no
## selection. Both now wear the theme's own selected stylebox, which
## carries the gold ACCENT that means "this one" everywhere else in this
## UI.
func test_the_armed_slot_and_the_open_tab_are_visibly_marked():
	_view.show_category(BlueprintPaletteModel.CATEGORY_HOMES)
	var slot = _view.slot_for("house_small")
	assert_not_null(slot, "the premise: the homes tab holds a cottage")
	assert_eq(
		slot.get_theme_stylebox("pressed").border_color, UiTheme.ACCENT,
		"an armed slot is marked in the accent"
	)
	var tab = _view.tab_for(BlueprintPaletteModel.CATEGORY_HOMES)
	assert_not_null(tab, "the premise: homes has a tab")
	assert_eq(
		tab.get_theme_stylebox("pressed").border_color, UiTheme.ACCENT,
		"and so is the open tab"
	)


## The mark has to be a mark: same-as-normal would be the invisible
## difference again under a new name.
func test_the_mark_really_differs_from_an_unarmed_slot():
	_view.show_category(BlueprintPaletteModel.CATEGORY_HOMES)
	var slot = _view.slot_for("house_small")
	var armed: StyleBoxFlat = slot.get_theme_stylebox("pressed")
	var unarmed: StyleBoxFlat = slot.get_theme_stylebox("normal")
	assert_ne(armed.border_color, unarmed.border_color)
	assert_gt(armed.bg_color.v, unarmed.bg_color.v)


## Exactly one tab reads as open, however the tab was opened.
##
## Measured on the render (tools/probe_build_palette.gd): three tabs were
## gold at once. A tab CLICKED goes through the ButtonGroup, which
## unpresses its siblings -- but a tab opened programmatically (arming a
## blueprint that lives in another category, or the palette's own first
## build) is marked with set_pressed_no_signal, which deliberately does not
## tell the group. So the siblings have to be put down by hand.
func test_only_the_open_tab_reads_as_open():
	var ids: Array = []
	for category in BlueprintPaletteModel.categories():
		ids.append(String(category["id"]))
	assert_gt(ids.size(), 1, "the premise: there is more than one tab to get wrong")
	for category_id in ids:
		_view.show_category(category_id)
		var open: Array = []
		for other in ids:
			if _view.tab_for(other).button_pressed:
				open.append(other)
		assert_eq(open, [category_id], "after opening %s" % category_id)
