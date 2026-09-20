extends Control

## An iOS-style two-state switch -- see docs/concept/hud.md "The planner
## toggle is a switch, because it has two states".
##
## Asked for directly: "make the planner switch a ios like switch button with
## two states". What it replaces was a Button whose caption was the mode you
## would switch TO, which is the right model for a button and the wrong one
## for a switch: a button says what pressing does, a switch shows what IS.
##
## The geometry and colours are pure statics, so the parts that can be
## silently wrong -- a knob that overhangs the track at one end, two states
## that look alike -- are tested rather than eyeballed
## (tests/unit/test_toggle_switch.gd). The slide itself is deliberately not
## tested: what is pinned is where the knob comes to REST.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## A track wider than it is tall, by enough that the knob's travel reads as
## travel. 44x24 at scale 1.0, the proportions the iOS control uses.
const TRACK_SIZE := Vector2(44.0, 24.0)

## The knob, and the gap it keeps from the track's edge at both ends. The
## knob is deliberately SHORTER than the track's height: a knob that filled
## it would have no visible track above and below and would read as a sliding
## block rather than a switch.
const KNOB_DIAMETER := 18.0
const KNOB_PADDING := 3.0

## How long the knob takes to slide. Short enough to feel instant, long
## enough that the eye follows it from one end to the other -- which is the
## whole reason this reads as ONE control with two states rather than as two
## different pictures.
const SLIDE_SECONDS := 0.12

signal toggled_to(on: bool)

var _on := false
var _track: Panel
var _knob: Panel
var _slide: Tween


## Where the knob's left edge rests. Pure, and taking its own measurements
## rather than reading the constants, so the symmetry it guarantees is a
## property of the FUNCTION and holds at any size the caller passes.
static func knob_x_for(
	on: bool, track_width: float, knob_diameter: float, padding: float
) -> float:
	if not on:
		return padding
	return track_width - knob_diameter - padding


## A pill: the radius is half the height, which is the shape that makes this
## read as a switch rather than as a small rounded button.
static func track_corner_radius() -> float:
	return TRACK_SIZE.y / 2.0


## The theme's own existing on/off pair (the same gold Karma uses for
## positive), never a third palette invented here.
static func track_color_for(on: bool) -> Color:
	return UiTheme.ACCENT if on else UiTheme.BUTTON_NORMAL


## One colour in both states: the knob has to read against both track
## colours, so it is the part that does NOT change.
static func knob_color_for(_on: bool) -> Color:
	return UiTheme.TEXT


func _init() -> void:
	custom_minimum_size = TRACK_SIZE
	# A focused Control answers ui_accept, which is Space, which is the attack
	# key -- the exact bug the Button this replaces already carried a comment
	# about ("space now toggles between plann mode and rpg", reported live).
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Keeps its own 24px height inside a row. A container stretches its
	# children to the row by default, and a stretched track stops being a
	# pill: the corner radius is half of TRACK_SIZE.y, so a taller track turns
	# the semicircular ends into merely-rounded corners. Seen in a render;
	# invisible to a test that measures the constants rather than the node.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	_track = Panel.new()
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_track)

	_knob = Panel.new()
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_knob.size = Vector2(KNOB_DIAMETER, KNOB_DIAMETER)
	add_child(_knob)

	_repaint()
	_knob.position = Vector2(_rest_x(), (TRACK_SIZE.y - KNOB_DIAMETER) / 2.0)


## Sets the state WITHOUT animating -- for the first paint, and for any time
## the mode changed somewhere else (a keypress, a loaded save) rather than by
## a click on this switch.
func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if _knob == null:
		return
	_repaint()
	_slide_knob()


func is_on() -> bool:
	return _on


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		toggled_to.emit(not _on)


func _rest_x() -> float:
	return knob_x_for(_on, TRACK_SIZE.x, KNOB_DIAMETER, KNOB_PADDING)


func _slide_knob() -> void:
	var target := Vector2(_rest_x(), (TRACK_SIZE.y - KNOB_DIAMETER) / 2.0)
	if _slide != null and _slide.is_valid():
		_slide.kill()
	if not is_inside_tree():
		_knob.position = target
		return
	_slide = create_tween()
	_slide.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_slide.tween_property(_knob, "position", target, SLIDE_SECONDS)


func _repaint() -> void:
	# The track carries the shared border in BOTH states. Off is
	# UiTheme.BUTTON_NORMAL, which sits within 0.06 luminance of the PANEL_BG
	# card behind it -- rendered, the off track all but vanished into the
	# card, so the outline is what makes an off switch read as a switch at
	# all. The knob has no border: it reads against both track colours on its
	# own.
	_track.add_theme_stylebox_override(
		"panel", _pill(track_color_for(_on), track_corner_radius(), UiTheme.PANEL_BORDER)
	)
	_knob.add_theme_stylebox_override(
		"panel", _pill(knob_color_for(_on), KNOB_DIAMETER / 2.0)
	)


func _pill(color: Color, radius: float, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius))
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(UiTheme.BORDER_WIDTH)
	return box
