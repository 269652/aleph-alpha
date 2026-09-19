extends PanelContainer

## docs/concept/village_growth.md mechanism 5: the readout a click on a
## building opens -- what it is, who lives there, their four needs, their
## happiness and their productivity.
##
## A PURE CONSUMER of EarthChunkManager.household_report_at's own
## Dictionary. It renders what it is handed and reaches for nothing else,
## which is what makes it drivable from a literal in a test and what keeps
## it from ever becoming a second source of truth about a village. Opening
## it changes nothing; never opening it changes nothing either.
##
## A COMMONS (a hall, a mill, a warehouse -- `is_home` false) is drawn as
## what it is: named, attributed to the settlement, showing the village's
## own productivity, with no needs rows. Inventing residents for a town
## hall so the panel has something to draw would be exactly the fabrication
## this project's rules forbid.

const HouseholdWellbeing = preload("res://src/emergence/household_wellbeing.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")
const EstateAscension = preload("res://src/emergence/estate_ascension.gd")
const SettlementCharter = preload("res://src/emergence/settlement_charter.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

## One catalog instance for the readout's own naming -- ItemCatalog is
## instance-based, and a panel listing a barn should not allocate a whole
## Item just to read a label off it.
var _items := ItemCatalog.new()

const PANEL_WIDTH := 236.0
const BAR_WIDTH := 150.0
const BAR_HEIGHT := 7.0
const BAR_BG_COLOR := Color(0.1, 0.1, 0.1, 0.85)

## A need at or below this reads as genuinely unmet, and is drawn as a
## warning so a village in trouble can be spotted at a glance rather than
## by reading four numbers. Half the scale: below it, more of the need is
## missing than met.
const NEED_WARN_AT_OR_BELOW := 0.5
const NEED_OK_COLOR := Color(0.45, 0.76, 0.5)
const NEED_WARN_COLOR := Color(0.95, 0.6, 0.3)

## Human labels for HouseholdWellbeing.NEED_IDS, in that module's own order
## (most fundamental first) -- the readout shows needs in the order they
## actually matter, which is also their weight order.
const NEED_LABELS := {
	"food": "Food", "shelter": "Shelter", "work": "Work", "income": "Income",
	"community": "Community",
}

signal closed

var _title: Label
var _subtitle: Label
var _standing: Label
var _charter: Label
var _needs_root: VBoxContainer
var _summary: Label
var _purse: Label
## need_id -> {"label": Label, "bar": ColorRect, "fill": float, "color": Color}
var _need_rows: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	visible = false

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	root.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 11)
	_subtitle.modulate = Color(1, 1, 1, 0.75)
	root.add_child(_subtitle)

	# Which way this household is going (docs/concept/village_estates.md
	# mechanism 3). Its own line rather than a third clause on the subtitle:
	# it is the one thing on this panel that CHANGES, and a player watching
	# a house to see whether it will rise should not have to re-read a name
	# and a trade to find out.
	_standing = Label.new()
	_standing.add_theme_font_size_override("font_size", 11)
	root.add_child(_standing)

	# The settlement's own charter, on the commons a village shares
	# (docs/concept/settlement_charter.md mechanism 5). Its own line under
	# the subtitle, because it is an ERRAND -- a player who wants a mage
	# guild stands in the village, clicks the hall, and reads what to go
	# and do.
	_charter = Label.new()
	_charter.add_theme_font_size_override("font_size", 11)
	_charter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_charter.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(_charter)

	_needs_root = VBoxContainer.new()
	_needs_root.add_theme_constant_override("separation", 2)
	root.add_child(_needs_root)

	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 11)
	root.add_child(_summary)

	_purse = Label.new()
	_purse.add_theme_font_size_override("font_size", 11)
	_purse.modulate = Color(1, 1, 1, 0.75)
	root.add_child(_purse)

	# The Inventory tab (docs/concept/building_storage.md). A TAB rather than
	# one more row, because what a building HOLDS is a different question
	# from who lives there and how they are doing -- and because a barn's
	# contents would otherwise push the needs rows off a 236px panel.
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_tabs)
	_household_tab = _build_tab_button("Household", TAB_HOUSEHOLD)
	_inventory_tab = _build_tab_button("Inventory", TAB_INVENTORY)
	# The Needs tab (docs/concept/village_estates.md mechanism 8): every
	# need this village's estates really ask for, what they got, and which
	# building would answer it. A third question again -- who lives here,
	# what this building holds, and what the VILLAGE is short of.
	_village_needs_tab = _build_tab_button("Needs", TAB_NEEDS)

	_village_needs_root = VBoxContainer.new()
	_village_needs_root.add_theme_constant_override("separation", 1)
	root.add_child(_village_needs_root)

	_inventory_root = VBoxContainer.new()
	_inventory_root.add_theme_constant_override("separation", 2)
	root.add_child(_inventory_root)

	_inventory_summary = Label.new()
	_inventory_summary.add_theme_font_size_override("font_size", 11)
	_inventory_root.add_child(_inventory_summary)

	_inventory_rows_root = VBoxContainer.new()
	_inventory_rows_root.add_theme_constant_override("separation", 1)
	_inventory_root.add_child(_inventory_rows_root)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(1, 1, 1, 0.45)
	hint.text = "Click elsewhere to close"
	root.add_child(hint)


## Opens the panel on `report` (EarthChunkManager.household_report_at's own
## shape). An EMPTY report closes it -- clicking bare ground is a real
## answer ("nothing here"), not an error.
func show_report(report: Dictionary) -> void:
	if report.is_empty():
		close()
		return
	# A report may name ITSELF -- a cart is not a building and has no catalog
	# entry to be looked up in (docs/concept/village_warehouse.md, Mechanism
	# 6). A building carries neither key and keeps the naming it always had,
	# so nothing that already opened this panel changes.
	var named := String(report.get("title", ""))
	_title.text = (
		named if named != "" else BuildingCatalog.display_name_of(String(report.get("building_id", "")))
	)
	_subtitle.text = _subtitle_for(report)
	_standing.text = _standing_for(report)
	_standing.visible = _standing.text != ""
	_standing.modulate = _STANDING_COLORS.get(String(report.get("estate_verdict", "")), _STANDING_OK_COLOR)
	_charter.text = _charter_for(report)
	_charter.visible = _charter.text != ""
	_charter.modulate = _STANDING_OK_COLOR
	_rebuild_need_rows(report.get("needs", {}))
	_summary.text = _summary_for(report)
	var wallet := int(report.get("wallet_balance", 0))
	_purse.visible = bool(report.get("is_home", false))
	_purse.text = "Purse: %d gold" % wallet
	# Needs first: _rebuild_inventory decides whether the tab ROW shows at
	# all, and it cannot know that without knowing whether a Needs tab is
	# offered too.
	_rebuild_village_needs(report)
	_rebuild_inventory(report)
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Whose building this is. A home names the person and their trade -- the
## readout is about people, not plots; a commons says so plainly instead of
## being handed a resident it does not have.
func _subtitle_for(report: Dictionary) -> String:
	var given := String(report.get("subtitle", ""))
	if given != "":
		return given
	if not bool(report.get("is_home", false)):
		return "Settlement commons"
	var resident := String(report.get("resident_name", ""))
	var occupation := String(report.get("resident_occupation", ""))
	if resident == "" and occupation == "":
		return "Nobody has moved in yet"
	if occupation == "":
		return resident
	var standing := VillageEstates.display_name_of(String(report.get("estate", "")))
	var who := (
		occupation.capitalize() if resident == ""
		else ("%s — %s" % [resident, occupation.capitalize()])
	)
	return who if standing == "" else ("%s · %s" % [who, standing])


## A home reports its own household's happiness and productivity; a commons
## reports the village's, which is the only one it has.
func _summary_for(report: Dictionary) -> String:
	if bool(report.get("is_home", false)):
		return "Happiness %d%%   Productivity %d%%" % [
			_percent(report.get("happiness", 0.0)), _percent(report.get("productivity", 0.0)),
		]
	return "Village productivity %d%%" % _percent(report.get("settlement_productivity", 0.0))


## Which way this household is going, in one line -- the thing a player
## actually watches (docs/concept/village_estates.md mechanism 3).
##
## A falling household at the bottom rung is LEAVING, and is told so rather
## than named an estate below the lowest one, which does not exist. A
## commons has no household and gets no line at all.
func _standing_for(report: Dictionary) -> String:
	if not bool(report.get("is_home", false)):
		return ""
	var estate := String(report.get("estate", ""))
	if VillageEstates.display_name_of(estate) == "":
		return ""
	match String(report.get("estate_verdict", EstateAscension.HOLD)):
		EstateAscension.ASCEND:
			var above := VillageEstates.display_name_of(VillageEstates.next_estate(estate))
			return "Rising to %s" % above if above != "" else _SETTLED_TEXT
		EstateAscension.DESCEND:
			if EstateAscension.is_exodus(estate):
				return "Leaving the village"
			var below := VillageEstates.display_name_of(VillageEstates.previous_estate(estate))
			return "Falling to %s" % below if below != "" else "Leaving the village"
		_:
			return _SETTLED_TEXT


## What a household holding its own standing is shown as. Never blank: a
## blank line reads as "the panel does not know", and a settled household
## is a real, and usually good, answer.
const _SETTLED_TEXT := "Settled"

const _STANDING_OK_COLOR := Color(1, 1, 1, 0.75)
const _STANDING_COLORS := {
	EstateAscension.ASCEND: Color(0.45, 0.76, 0.5),
	EstateAscension.DESCEND: Color(0.95, 0.6, 0.3),
}


## What a settlement IS, and what it would take to be the next thing up
## (docs/concept/settlement_charter.md mechanism 5).
##
## On the COMMONS only: a home's readout is about its household, and the
## charter is a fact about the place everyone shares. A dimension already
## cleared is left out -- "0 more trades" is noise, and noise is what stops
## a player reading the line at all.
func _charter_for(report: Dictionary) -> String:
	if bool(report.get("is_home", false)):
		return ""
	var charter: Dictionary = report.get("charter", {})
	var tier := String(charter.get("tier", ""))
	if tier == "":
		return ""

	var next_tier := String(charter.get("next_tier", ""))
	if next_tier == "":
		return "%s — the greatest a settlement becomes" % tier.capitalize()

	var wants: Array = []
	for dimension in _CHARTER_DIMENSIONS:
		var short := int(Dictionary(charter.get("short", {})).get(dimension, 0))
		if short > 0:
			wants.append("%d %s" % [short, _CHARTER_DIMENSIONS[dimension][short == 1]])
	if wants.is_empty():
		return "%s — a %s already, any day now" % [tier.capitalize(), next_tier]
	return "%s — a %s needs %s" % [tier.capitalize(), next_tier, ", ".join(wants)]


## What each of SettlementTier's three dimensions is CALLED to a player,
## singular and plural. Institutions are "trade bodies" and production
## diversity is "trades" because that is what they are on the ground: a
## guild that formed itself, and a thing somebody actually makes.
const _CHARTER_DIMENSIONS := {
	"households": {true: "more household", false: "more households"},
	"institutions": {true: "more trade body", false: "more trade bodies"},
	"production_diversity": {true: "more trade", false: "more trades"},
}


## Rounded toward zero, so a reading never flatters itself up to the next
## percent -- 0.729 shows as 72, not 73.
static func _percent(value) -> int:
	return int(clampf(float(value), 0.0, 1.0) * 100.0)


func _rebuild_need_rows(needs: Dictionary) -> void:
	for child in _needs_root.get_children():
		_needs_root.remove_child(child)
		child.queue_free()
	_need_rows.clear()
	# NEED_IDS' own order, not the Dictionary's: the readout shows needs in
	# the order they actually matter (which is also their weight order).
	for need_id in HouseholdWellbeing.NEED_IDS:
		if not needs.has(need_id):
			continue
		_need_rows[need_id] = _add_need_row(String(need_id), clampf(float(needs[need_id]), 0.0, 1.0))


func _add_need_row(need_id: String, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_needs_root.add_child(row)

	var label := Label.new()
	label.text = String(NEED_LABELS.get(need_id, need_id.capitalize()))
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size = Vector2(PANEL_WIDTH - BAR_WIDTH - 12.0, 0)
	row.add_child(label)

	var bar_root := Control.new()
	bar_root.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	row.add_child(bar_root)

	var background := ColorRect.new()
	background.color = BAR_BG_COLOR
	background.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_root.add_child(background)

	var fill_width := BAR_WIDTH * value
	var color := NEED_WARN_COLOR if value <= NEED_WARN_AT_OR_BELOW else NEED_OK_COLOR
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(fill_width, BAR_HEIGHT)
	bar_root.add_child(fill)

	return {"label": label, "bar": fill, "fill": fill_width, "color": color, "value": value}


# -- what a test (or a caller) reads back ---------------------------------

func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


func summary_text() -> String:
	return _summary.text


## Which way this household is going, as drawn; "" for a commons.
func standing_text() -> String:
	return _standing.text if _standing.visible else ""


## The settlement's charter, as drawn; "" for a home and for a commons
## whose settlement nobody reported a charter for.
func charter_text() -> String:
	return _charter.text if _charter.visible else ""


func purse_text() -> String:
	return _purse.text


## need_id -> {"fill": bar width in pixels, "color": the colour it was
## drawn in, "value": the satisfaction itself}. Empty for a commons.
func need_rows() -> Dictionary:
	return _need_rows.duplicate(true)


# -- the Inventory tab -------------------------------------------------------


var _tabs: HBoxContainer
var _household_tab: Button
var _inventory_tab: Button
var _inventory_root: VBoxContainer
var _inventory_summary: Label
var _inventory_rows_root: VBoxContainer
var _inventory: Dictionary = {}
var _storage_capacity := 0


## Which tab is showing, by id rather than by a boolean: there are three of
## them now, and "inventory or not" cannot say which of the other two.
const TAB_HOUSEHOLD := "household"
const TAB_INVENTORY := "inventory"
const TAB_NEEDS := "needs"

var _selected_tab := TAB_HOUSEHOLD


func _build_tab_button(text: String, tab_id: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_pressed = tab_id == TAB_HOUSEHOLD
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(func() -> void: _select_tab(tab_id))
	_tabs.add_child(button)
	return button


## Which third of the panel is showing. Only ever one, and the buttons stay
## in step with it rather than each tracking its own state.
func _select_tab(tab_id: String) -> void:
	_selected_tab = tab_id
	_household_tab.button_pressed = tab_id == TAB_HOUSEHOLD
	_inventory_tab.button_pressed = tab_id == TAB_INVENTORY
	_village_needs_tab.button_pressed = tab_id == TAB_NEEDS
	_inventory_root.visible = tab_id == TAB_INVENTORY
	_village_needs_root.visible = tab_id == TAB_NEEDS
	var household := tab_id == TAB_HOUSEHOLD
	_needs_root.visible = household
	_summary.visible = household
	_purse.visible = household and bool(_is_home)


## Which tab is open right now.
func selected_tab() -> String:
	return _selected_tab


var _is_home := false


## A building that keeps NO goods has no tab at all, rather than an empty
## one: a town hall is not a barn with nothing in it. An empty barn does
## still show, because "nothing in it right now" is a fact worth reading.
func _rebuild_inventory(report: Dictionary) -> void:
	_is_home = bool(report.get("is_home", false))
	_storage_capacity = int(report.get("storage_capacity", 0))
	_inventory = (report.get("stock", {}) as Dictionary).duplicate()
	var offered := _storage_capacity > 0
	_inventory_tab.visible = offered
	_tabs.visible = offered or has_needs_tab()
	if not offered:
		_select_tab(TAB_HOUSEHOLD)
		_inventory_root.visible = false
		return
	var held := 0
	for count in _inventory.values():
		held += int(count)
	_inventory_summary.text = "Stored: %d / %d" % [held, _storage_capacity]
	for child in _inventory_rows_root.get_children():
		child.queue_free()
		_inventory_rows_root.remove_child(child)
	for item_id in _sorted_item_ids():
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 11)
		row.text = "%s  x%d" % [_items.display_name_of(item_id), int(_inventory[item_id])]
		_inventory_rows_root.add_child(row)
	# Opening on Household keeps the readout's own answer to "who lives
	# here" first; the tabs are there for whoever wants the barn or the
	# village's own ledger of needs.
	_select_tab(TAB_HOUSEHOLD)


## Stable and readable: by item id, so the same barn lists the same way
## every time it is opened rather than in whatever order a Dictionary hands
## its keys back.
func _sorted_item_ids() -> Array:
	var ids: Array = _inventory.keys()
	ids.sort()
	return ids


## Whether this building offers an Inventory tab at all.
func has_inventory_tab() -> bool:
	return _storage_capacity > 0


# -- the Needs tab (docs/concept/village_estates.md mechanism 8) ------------


var _village_needs_tab: Button
var _village_needs_root: VBoxContainer
var _village_needs: Array = []

## What an unbuildable need says instead of naming a building. Plain rather
## than blank: "nothing here makes this" is a real answer, and pointing at
## the nearest-sounding building would be a lie.
const NO_REMEDY_TEXT := "nothing here makes this"

## The mark on the need the village is actually about to answer, so a player
## sees the argument being settled rather than inferring it.
const NEXT_MARK := "> "

const _NEXT_COLOR := Color(0.62, 0.86, 0.55)
const _SHORT_COLOR := Color(0.93, 0.66, 0.46)


## Draws VillageNeedsReport's own rows, in the order it handed them over --
## worst first. The panel never re-sorts and never re-derives: it renders
## what it is handed, the same contract the other two tabs keep.
func _rebuild_village_needs(report: Dictionary) -> void:
	_village_needs = (report.get("village_needs", []) as Array).duplicate()
	_village_needs_tab.visible = has_needs_tab()
	for child in _village_needs_root.get_children():
		child.queue_free()
		_village_needs_root.remove_child(child)
	for row in _village_needs:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 11)
		label.text = _needs_row_text(row)
		if bool(row.get("next", false)):
			label.modulate = _NEXT_COLOR
		elif float(row.get("satisfaction", 1.0)) < 1.0:
			label.modulate = _SHORT_COLOR
		_village_needs_root.add_child(label)


## One row: the need, how full it is, and what would answer it.
func _needs_row_text(row: Dictionary) -> String:
	var remedy := String(row.get("remedy", ""))
	var answer := (
		BuildingCatalog.display_name_of(remedy) if bool(row.get("resolvable", false))
		else NO_REMEDY_TEXT
	)
	return "%s%s  %d%%  -  %s" % [
		NEXT_MARK if bool(row.get("next", false)) else "",
		String(row.get("label", row.get("good", ""))),
		int(round(clampf(float(row.get("satisfaction", 1.0)), 0.0, 1.0) * 100.0)),
		answer,
	]


## Whether this readout offers a Needs tab at all -- a village nobody has
## assessed has no graph to show, and an empty tab is worse than none.
func has_needs_tab() -> bool:
	return not _village_needs.is_empty()


## What the tab lists, as the report's own rows plus the rendered `text` --
## the same "what is really on screen" shape the Inventory tab exposes.
func needs_rows() -> Array:
	var rows: Array = []
	for row in _village_needs:
		var listed: Dictionary = (row as Dictionary).duplicate()
		listed["text"] = _needs_row_text(row)
		rows.append(listed)
	return rows


## What the tab lists, as {item_id, label, count} -- the rendered rows, in
## the order they are drawn.
func inventory_rows() -> Array:
	var rows: Array = []
	for item_id in _sorted_item_ids():
		rows.append({
			"item_id": item_id,
			"label": _items.display_name_of(item_id),
			"count": int(_inventory[item_id]),
		})
	return rows


func inventory_summary_text() -> String:
	return _inventory_summary.text


## A full barn is the whole reason hauling exists, so the panel says so.
func inventory_is_full() -> bool:
	if _storage_capacity <= 0:
		return false
	var held := 0
	for count in _inventory.values():
		held += int(count)
	return held >= _storage_capacity
