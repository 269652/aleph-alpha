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
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")

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
	"food": "Food", "shelter": "Shelter", "income": "Income", "community": "Community",
}

signal closed

var _report: Dictionary = {}
var _title: Label
var _subtitle: Label
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
	_report = report
	_title.text = BuildingCatalog.display_name_of(String(report.get("building_id", "")))
	_subtitle.text = _subtitle_for(report)
	_rebuild_need_rows(report.get("needs", {}))
	_summary.text = _summary_for(report)
	var wallet := int(report.get("wallet_balance", 0))
	_purse.visible = bool(report.get("is_home", false))
	_purse.text = "Purse: %d gold" % wallet
	visible = true


func close() -> void:
	if not visible:
		return
	_report = {}
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Whose building this is. A home names the person and their trade -- the
## readout is about people, not plots; a commons says so plainly instead of
## being handed a resident it does not have.
func _subtitle_for(report: Dictionary) -> String:
	if not bool(report.get("is_home", false)):
		return "Settlement commons"
	var resident := String(report.get("resident_name", ""))
	var occupation := String(report.get("resident_occupation", ""))
	if resident == "" and occupation == "":
		return "Nobody has moved in yet"
	if occupation == "":
		return resident
	if resident == "":
		return occupation.capitalize()
	return "%s — %s" % [resident, occupation.capitalize()]


## A home reports its own household's happiness and productivity; a commons
## reports the village's, which is the only one it has.
func _summary_for(report: Dictionary) -> String:
	if bool(report.get("is_home", false)):
		return "Happiness %d%%   Productivity %d%%" % [
			_percent(report.get("happiness", 0.0)), _percent(report.get("productivity", 0.0)),
		]
	return "Village productivity %d%%" % _percent(report.get("settlement_productivity", 0.0))


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


func purse_text() -> String:
	return _purse.text


## need_id -> {"fill": bar width in pixels, "color": the colour it was
## drawn in, "value": the satisfaction itself}. Empty for a commons.
func need_rows() -> Dictionary:
	return _need_rows.duplicate(true)
