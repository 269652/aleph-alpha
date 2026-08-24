extends Control

## Full-screen "the game is working, not hung" cover, shown while New Game /
## Host / Load Game / Join pay their real, synchronous world-setup cost (see
## World._show_loading_overlay and the entry points that call it).
##
## Deliberately plain: a full-rect dim behind a centered status label and an
## indeterminate spinner glyph (see LoadingSpinner). No fabricated percentage
## -- the heavy call this covers (EarthChunkManager.update()'s first call for
## a fresh chunk radius, ~39s measured in this dev sandbox, see
## docs/progress.md) has no `await` anywhere in its own call chain, so nothing
## outside it can observe real interim progress without restructuring
## EarthChunkManager/TerrainRenderer internals -- out of scope for a loading
## SCREEN. An honest indeterminate spinner + a clear status line is the
## accurate representation of what's actually knowable here.
##
## PROCESS_MODE_ALWAYS (set by World, matching every other paused-but-live
## overlay in this file -- SettingsOverlay/MainMenu) so the spinner keeps
## advancing across the brief awaited frames before/after the freeze, even
## though the world is paused underneath it the whole time.
##
## IMPORTANT, verified by real timing instrumentation (see docs/progress.md):
## the spinner glyph can only ever actually be SEEN to change across the
## couple of frames World awaits before starting the heavy call, or between
## two separate real stages -- once the heavy synchronous call itself starts,
## the engine cannot present another frame until it returns, so the glyph
## necessarily freezes on whatever frame it was on for the full real
## duration. That's still correct and honest (a real indeterminate spinner,
## just one that can't animate through a period nothing can render during),
## and is the reason this shows a spinner + text rather than a fake percentage
## that would silently stop tracking anything real the moment the freeze began.

const LoadingSpinner = preload("res://src/ui/loading_spinner.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _status_label: Label
var _spinner_label: Label
var _elapsed_seconds := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# set_anchors_preset alone is NOT enough here -- by the time _ready() runs
	# this control is already parented with a (0,0)-sized rect, and Godot's
	# anchor recompute PRESERVES the control's current on-screen rect under
	# the new anchor fractions rather than deriving it from size (the exact
	# pin-to-corner gotcha MainMenu._ready() already hit and documents in
	# detail). Explicit zero offsets force a genuine full-viewport fill
	# instead of a degenerate zero-size rect sitting at the origin --
	# confirmed against a real rendered screenshot (see docs/progress.md).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.04, 0.9)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	add_child(backdrop)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -200.0
	box.offset_top = -40.0
	box.offset_right = 200.0
	box.offset_bottom = 40.0
	add_child(box)

	_spinner_label = Label.new()
	_spinner_label.add_theme_font_size_override("font_size", 28)
	_spinner_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_spinner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_spinner_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.modulate = Color(1, 1, 1, 0.7)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status_label)


## Shows the overlay with `text` as the status line, on top of every other
## child of its parent (see World._show_loading_overlay, which awaits two
## process frames right after calling this so it genuinely paints before the
## synchronous work it's covering starts).
func show_with_text(text: String) -> void:
	_status_label.text = text
	_elapsed_seconds = 0.0
	_spinner_label.text = LoadingSpinner.frame_for_elapsed(0.0)
	move_to_front()
	visible = true


func hide_overlay() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed_seconds += delta
	_spinner_label.text = LoadingSpinner.frame_for_elapsed(_elapsed_seconds)
