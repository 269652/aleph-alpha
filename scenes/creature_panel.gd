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

## Colour for a condition reading that has gone bad enough to act on.
const CONDITION_WARN_COLOR := Color(0.95, 0.72, 0.3)
const CONDITION_OK_COLOR := Color(0.72, 0.76, 0.84)

var _health_bar := HealthBar.new()
var _name_label: Label
var _bar_fill: ColorRect
var _hp_label: Label
var _condition_label: Label


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

	# Condition, for animals the player has a stake in (see set_state). Hidden
	# by default so a meadow's worth of wild sheep stays a column of small
	# cards rather than a wall of bars.
	_condition_label = Label.new()
	_condition_label.add_theme_font_size_override("font_size", 10)
	_condition_label.visible = false
	root.add_child(_condition_label)


## Shows one animal's card from CreatureMarker.animal_state().
##
## Condition (trust / food / water / warmth) is shown only for an animal the
## player has a STAKE in -- tamed, part-tamed, or on the end of a rope. Five
## wild animals wander into range at once (observed live: a column of
## near-identical cards), and four extra rows on each of them would bury the
## one card that matters. `invested` is CreatureMarker.is_player_invested, the
## same line that already decides what the aggregate model may cull.
##
## Every fraction here reads 1.0 = fine, 0.0 = in trouble (see
## CreatureMarker.animal_state) -- including food and water, which the
## simulation stores the other way round as deficits.
func set_state(state: Dictionary) -> void:
	_name_label.text = "%s Lv.%d" % [state.get("name", "?"), int(state.get("level", 0))]
	var fraction := float(state.get("health_fraction", 0.0))
	_bar_fill.size.x = _health_bar.fill_width(fraction, 1.0, BAR_WIDTH)
	_hp_label.text = "HP %d%%" % int(round(fraction * 100.0))

	_condition_label.visible = bool(state.get("invested", false))
	if not _condition_label.visible:
		return
	_condition_label.text = _condition_text_for(state)
	# One colour for "something here wants doing", so the card can be read
	# without reading it.
	var needs_attention: bool = (
		bool(state.get("hungry", false))
		or bool(state.get("thirsty", false))
		or bool(state.get("cold", false))
		or bool(state.get("sick", false))
	)
	_condition_label.add_theme_color_override(
		"font_color", CONDITION_WARN_COLOR if needs_attention else CONDITION_OK_COLOR
	)


## The headline row, for tests and for anything that wants the same string.
func headline() -> String:
	return _name_label.text


func shows_condition() -> bool:
	return _condition_label.visible


func condition_text() -> String:
	return _condition_label.text


## Percentages AND words. A bar at 45% and a bar at 55% look identical and mean
## opposite things -- only a HUNGRY animal can be fed toward trust at all (see
## Taming.trust_after_feeding) -- so the verdicts that change what the player
## should do next are spelled out rather than left to be read off a fill.
func _condition_text_for(state: Dictionary) -> String:
	var rows := [
		"Trust %d%%" % int(round(float(state.get("trust", 0.0)) * 100.0)),
		"Food %d%%" % int(round(float(state.get("fullness", 0.0)) * 100.0)),
		"Water %d%%" % int(round(float(state.get("hydration", 0.0)) * 100.0)),
		"Warmth %d%%" % int(round(float(state.get("warmth", 0.0)) * 100.0)),
	]
	var flags := []
	if bool(state.get("hungry", false)):
		flags.append("hungry")
	if bool(state.get("thirsty", false)):
		flags.append("thirsty")
	if bool(state.get("cold", false)):
		flags.append("cold")
	if bool(state.get("sick", false)):
		flags.append("sick")
	var text := "  ".join(rows)
	if not flags.is_empty():
		text += "
" + ", ".join(flags)
	return text
