extends PanelContainer

## One creature's own small HUD panel: name, level, and an HP bar. Lives in
## the HUD (World's UI CanvasLayer, see World._update_creature_panels), one
## per nearby creature -- not attached to the creature's world-space sprite
## (that's just the tiny always-on health sliver CreatureMarker itself draws).

const HealthBar = preload("res://src/gameplay/health_bar.gd")

const BAR_WIDTH := 96.0
const BAR_HEIGHT := 6.0
const BAR_BG_COLOR := Color(0.1, 0.1, 0.1, 0.85)
const BAR_FILL_COLOR := Color(0.8, 0.15, 0.15)

var _health_bar := HealthBar.new()
var _name_label: Label
var _bar_fill: ColorRect
var _hp_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(BAR_WIDTH + 16.0, 40.0)

	var root := VBoxContainer.new()
	add_child(root)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 11)
	root.add_child(_name_label)

	var bar_root := Control.new()
	bar_root.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	root.add_child(bar_root)

	var bar_bg := ColorRect.new()
	bar_bg.color = BAR_BG_COLOR
	bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_root.add_child(bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = BAR_FILL_COLOR
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_root.add_child(_bar_fill)

	# A bare bar can be too subtle to read at a glance -- a numeric "HP x/y"
	# readout (same convention as the player's own health bar) makes the
	# number unambiguous, not just the fill fraction.
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 10)
	root.add_child(_hp_label)


## `info` is a CreatureInfo (duck-typed here to avoid a hard preload cycle --
## CreatureInfo has no dependency back on this script either way, but every
## other HUD widget in this codebase follows the same untyped-param
## convention for its data payload).
func set_info(info) -> void:
	_name_label.text = "%s Lv.%d" % [info.display_name, info.level]
	_bar_fill.size.x = _health_bar.fill_width(info.health, info.max_health, BAR_WIDTH)
	_hp_label.text = "HP %d / %d" % [int(info.health), int(info.max_health)]
