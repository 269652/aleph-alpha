extends PanelContainer

## The build palette: planner mode's own controls, where the hotbar sits in
## rpg mode (docs/concept/planner_mode.md, "The build palette").
##
## Asked directly, with a screenshot of the ten identical text buttons this
## replaced: *"Make the Planner / Building HUD more professional and more
## like Anno 1806. Add Icons not only text"*.
##
## A titled card holding a row of category tabs, the slots of whichever
## category is open, and a footer naming what is armed and what it will
## cost. Every one of those reads BlueprintPaletteModel -- the tabs ARE
## BuildingCatalog's own id lists (planner_mode.md's "one vocabulary"), so
## a building added to the game shows up here for free, in the right tab,
## with no list kept anywhere to forget to update.
##
## Its own Control rather than forty lines inside scenes/world.gd, for the
## reason every other panel in this game already is one (CreaturePanel,
## HousePanel): a menu with tabs, a selection and a footer is a thing with
## BEHAVIOUR, and behaviour buried in a 19k-line World can only be tested
## by reading its source. Tested for real in
## test_blueprint_palette_view.gd.

const BlueprintPaletteModel = preload("res://src/ui/blueprint_palette_model.gd")
const BlueprintIcon = preload("res://src/ui/blueprint_icon.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Which blueprint the player just armed. World listens and does the rest
## (the cursor, the planner message); this widget never plans anything
## itself -- pillar 1's "planning is not building" starts here.
signal blueprint_selected(blueprint_id: String)

## How big a slot's picture is, in HUD pixels.
##
## Deliberately larger than the hotbar's own HUD_SLOT_SIZE (32): a hotbar
## slot holds ONE item drawn to read at a glance, and a building's picture
## has a roof, a door, a yard and a chimney in it. At 32 the three house
## tiers are three brown smudges of the same size -- the "ten identical
## buttons" problem again, with pictures instead of words.
const ICON_SIZE := 48

## A slot is the icon with the name under it, and its size is MEASURED from
## the names it actually has to hold rather than written down.
##
## It was a constant (100x82), and tools/probe_build_palette.gd showed what
## that costs: at UiScale.MAX_SCALE six of the ten names ran past it --
## "Warehouse" wanted 137px of a slot offering 84 -- and even at 1.00 the
## tightest had 7px to spare, so one longer building name would have
## clipped today. UiScale deliberately scales FONT SIZES and not card widths
## (its own documented limit), so a written-down slot width is a slot that
## clips the moment that slider moves.
static func slot_size_for(
	widest_name_px: float, line_height_px: float, padding_px: float
) -> Vector2:
	return Vector2(
		maxf(float(ICON_SIZE), widest_name_px) + padding_px * 2.0,
		float(ICON_SIZE) + line_height_px + padding_px * 2.0
	)

const TITLE_TEXT := "BUILD"

## What the footer says with nothing armed. A blank footer would read as a
## readout that has not loaded; this reads as the state it really is.
const IDLE_TEXT := "Pick a blueprint, then click the map to plan it."

const DETAIL_SEPARATOR := "  ·  "

var _labour_hours_for := Callable()
var _name_for_item := Callable()
## One per view rather than one per slot: the sheet slicing underneath is
## cached per sheet, and every slot sharing a sheet should share that work.
var _icons := BlueprintIcon.new()
## The shared look, for the one stylebox a Theme resource cannot carry on
## its own: "toggled ON" is not a Button state Godot themes separately from
## "held down", so it is applied per-control (see _mark_as_toggle).
var _look := UiTheme.new()

var _column: VBoxContainer
var _header: HBoxContainer
var _slot_row: HBoxContainer
var _footer: Label
## blueprint_id -> its slot button, for whichever category is showing.
var _slots: Dictionary = {}
## category id -> its tab button.
var _tabs: Dictionary = {}
var _slot_group: ButtonGroup
var _tab_group: ButtonGroup
var _shown_category := ""
var _selected := ""


## Builds the card. `labour_hours_for` and `name_for_item` are the two
## seams that keep this widget from inventing numbers: the first is the
## ledger's own labour requirement (EarthChunkManager.build_labor_hours_
## for -- the very number PlanRaising.is_laid_by_hand is asked about), the
## second the real ItemCatalog. Callables rather than the objects
## themselves, the shape BuildPlanLedger's own buildability check already
## established, so the widget stays testable without either.
func configure(
	theme_resource: Theme, labour_hours_for: Callable, name_for_item: Callable
) -> void:
	_labour_hours_for = labour_hours_for
	_name_for_item = name_for_item
	if theme_resource != null:
		theme = theme_resource
	if _column == null:
		_build()
	show_category(BlueprintPaletteModel.category_to_show(_selected))


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 8)
	add_child(_column)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 4)
	_column.add_child(_header)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(title)

	_tab_group = ButtonGroup.new()
	for category in BlueprintPaletteModel.categories():
		var category_id := String(category["id"])
		var tab := Button.new()
		tab.text = String(category["label"])
		tab.toggle_mode = true
		tab.button_group = _tab_group
		# Never takes keyboard focus. A focused Button answers `ui_accept`,
		# and ui_accept is Space -- which is the ATTACK key, the same trap
		# the view-mode toggle already documents.
		tab.focus_mode = Control.FOCUS_NONE
		_mark_as_toggle(tab)
		tab.pressed.connect(show_category.bind(category_id))
		_header.add_child(tab)
		_tabs[category_id] = tab

	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 6)
	_column.add_child(_slot_row)

	_footer = Label.new()
	_footer.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	# Wraps rather than clips. Measured at UiScale.MAX_SCALE
	# (tools/probe_build_palette.gd): clipped, the brewery's footer read
	# "22 Wood, 12 Stone, 4 Plant Fi" -- and the footer is the one line that
	# says what an armed blueprint will really cost.
	#
	# An autowrapping Label reports a near-zero minimum width, which is
	# exactly what is wanted here: the SLOT row decides how wide the card
	# is, and a long cost line is not allowed to stretch the whole menu to
	# fit one string.
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_footer)

	_slot_group = ButtonGroup.new()


## Fills the slot row with one category's blueprints, replacing whatever
## the last tab put there. Browsing arms nothing: opening a drawer is not
## choosing what is in it, so whatever was selected stays selected even
## while its own tab is not the one showing.
func show_category(category_id: String) -> void:
	if _slot_row == null:
		return
	_shown_category = category_id
	_clear_slots()
	for category in BlueprintPaletteModel.categories():
		if String(category["id"]) != category_id:
			continue
		for blueprint_id in category["blueprint_ids"]:
			var slot := _make_slot(String(blueprint_id))
			_slot_row.add_child(slot)
			_slots[String(blueprint_id)] = slot
	# Every tab put down, then this one up. A tab CLICKED would have had
	# its siblings unpressed by the ButtonGroup, but one opened
	# programmatically is marked with set_pressed_no_signal -- which
	# deliberately does not tell the group -- so opening a category from
	# code used to leave the previous tab looking open too (measured on the
	# render: three tabs gold at once).
	#
	# no_signal throughout: a tab press already ran this function, and
	# letting it re-emit would run it again mid-rebuild.
	for known_id in _tabs:
		_tabs[known_id].set_pressed_no_signal(known_id == category_id)
	_size_slots()
	_apply_selection()


## One width for every slot in the row -- the widest name in this category,
## measured with the font the slots are really drawn in rather than the one
## they were built with, so a UI-scale change lands correctly on a refresh.
## One width and not each slot's own, or a short name leaves a narrow button
## beside a wide one and the row reads as ragged.
func _size_slots() -> void:
	var slots := _slot_row.get_children()
	if slots.is_empty():
		return
	var widest := 0.0
	var line_height := 0.0
	var padding := 0.0
	for slot: Button in slots:
		var font: Font = slot.get_theme_font("font")
		var font_size: int = slot.get_theme_font_size("font_size")
		var box: StyleBox = slot.get_theme_stylebox("normal")
		widest = maxf(
			widest,
			font.get_string_size(slot.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
		line_height = maxf(line_height, font.get_height(font_size))
		padding = maxf(padding, box.content_margin_left)
	var size := slot_size_for(widest, line_height, padding)
	for slot: Button in slots:
		slot.custom_minimum_size = size


## Re-measures everything against the font the theme carries NOW -- what
## World calls when the player moves the UI-scale slider, since that scales
## font sizes under a layout that has already been measured.
func refresh() -> void:
	show_category(_shown_category)


## Freed outright rather than queue_free'd: the row's contents must be the
## new category's the moment this returns, so a caller (and a test) can
## read them without waiting a frame. Safe here because nothing being freed
## is the node currently emitting -- a tab lives in the header, not the
## row.
func _clear_slots() -> void:
	for slot in _slot_row.get_children():
		if slot is Button:
			# Out of the group before it dies, so the group is never left
			# holding a freed button as its pressed one.
			slot.set_pressed_no_signal(false)
			slot.button_group = null
		_slot_row.remove_child(slot)
		slot.free()
	_slots.clear()


## One slot: the building's own picture, its name under it, and the whole
## reckoning on hover.
##
## Icons AND text, which is what was asked for -- a picture alone would
## trade one unreadable menu for another, since a sawmill and a blacksmith
## are both a brown roof at 48 pixels.
func _make_slot(blueprint_id: String) -> Button:
	var button := Button.new()
	button.set_meta("blueprint_id", blueprint_id)
	button.toggle_mode = true
	button.button_group = _slot_group
	button.focus_mode = Control.FOCUS_NONE
	button.text = BlueprintPaletteModel.slot_title(blueprint_id)
	button.icon = _icons.icon_texture(blueprint_id, ICON_SIZE)
	# The icon is already cut to exactly ICON_SIZE (BlueprintIcon boxes it),
	# so letting the Button expand it again would re-scale an
	# already-scaled image. Stacked OVER the name rather than beside it:
	# beside it, the name gets half a slot and every one of them ellipsises.
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	_mark_as_toggle(button)
	button.tooltip_text = "\n".join(_detail_lines(blueprint_id))
	button.pressed.connect(_on_slot_pressed.bind(blueprint_id))
	return button


## Makes "toggled ON" visible.
##
## Godot draws a toggled Button in its `pressed` stylebox, which in this
## theme is a shade DARKER than normal -- measured on the palette's first
## real render (tools/probe_build_palette.gd), the armed slot and the open
## tab were indistinguishable from their neighbours over the card's dark
## background. A menu whose selection cannot be seen is a menu with no
## selection, so both wear UiTheme.selected_button_stylebox instead: the
## gold ACCENT that already means "this one" everywhere else in this UI,
## over a background that lifts out of the card.
##
## Per-control rather than in the shared Theme on purpose: `pressed` there
## also means a momentary click on every ordinary button in the game, and
## marking those gold would make every button in every window flash as
## selected while it is held.
func _mark_as_toggle(button: Button) -> void:
	button.add_theme_stylebox_override("pressed", _look.selected_button_stylebox())
	button.add_theme_color_override("font_pressed_color", UiTheme.ACCENT)


func _on_slot_pressed(blueprint_id: String) -> void:
	_selected = blueprint_id
	_apply_selection()
	blueprint_selected.emit(blueprint_id)


## Arms a blueprint from outside -- World's own `_selected_blueprint` is
## the state the rest of planner mode acts on, and this is how the palette
## is told about it (including the empty one leaving the mode clears to).
##
## Opens the tab that holds it, so the menu can never sit showing one
## category while the armed slot is in another.
func set_selected(blueprint_id: String) -> void:
	_selected = blueprint_id
	var category := BlueprintPaletteModel.category_of(blueprint_id)
	if category != "" and category != _shown_category:
		show_category(category)
		return
	_apply_selection()


func _apply_selection() -> void:
	for blueprint_id in _slots:
		var slot: Button = _slots[blueprint_id]
		slot.set_pressed_no_signal(blueprint_id == _selected)
	if _footer == null:
		return
	if _selected == "":
		_footer.text = IDLE_TEXT
		return
	_footer.text = DETAIL_SEPARATOR.join(_detail_lines(_selected))


## The card: name, ground, materials, work -- the model's reckoning, with
## this view's two seams filled in.
func _detail_lines(blueprint_id: String) -> Array:
	var hours := 0.0
	if _labour_hours_for.is_valid():
		hours = float(_labour_hours_for.call(blueprint_id))
	return BlueprintPaletteModel.detail_lines(blueprint_id, hours, _name_for_item)


func shown_category() -> String:
	return _shown_category


func selected_blueprint() -> String:
	return _selected


func slots() -> Array:
	var out: Array = []
	if _slot_row == null:
		return out
	for slot in _slot_row.get_children():
		out.append(slot)
	return out


func slot_for(blueprint_id: String) -> Button:
	return _slots.get(blueprint_id)


func tab_for(category_id: String) -> Button:
	return _tabs.get(category_id)


func footer_text() -> String:
	return "" if _footer == null else _footer.text


func footer_label() -> Label:
	return _footer
