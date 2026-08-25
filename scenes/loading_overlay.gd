extends Control

## Full-screen "the game is working, not hung" cover, shown while New Game /
## Host / Load Game / Join pay their real world-setup cost (see
## World._show_loading_overlay and the entry points that call it).
##
## A full-rect dim behind a centered status label and a spinner glyph (see
## LoadingSpinner). The status label now shows REAL, determinate progress
## ("N / M chunks") when a caller reports it via set_progress -- see
## EarthChunkManager.update_with_progress and docs/concept/persistence.md's
## "Loading screens" section. This used to be impossible: the heavy call this
## covers (EarthChunkManager.update()'s first call for a fresh chunk radius,
## ~39-90s+ measured in this dev sandbox, see docs/progress.md) had no
## `await` anywhere in its own call chain, so the engine could never present
## a frame during it and the spinner necessarily froze on whatever glyph it
## was on for the ENTIRE real duration -- reported back as "the loading
## screen ... still looks like it's hanging" even with an honest
## indeterminate spinner in place. update_with_progress fixes the actual
## cause (it awaits a frame between each chunk instead of loading the whole
## radius in one uninterrupted loop), which is what makes both the spinner's
## own animation AND this real percentage visible for the first time.
##
## PROCESS_MODE_ALWAYS (set by World, matching every other paused-but-live
## overlay in this file -- SettingsOverlay/MainMenu) so the spinner keeps
## advancing across every awaited frame, even though the world is paused
## underneath it the whole time.

const LoadingSpinner = preload("res://src/ui/loading_spinner.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _status_label: Label
var _spinner_label: Label
var _elapsed_seconds := 0.0
## The text show_with_text was called with, kept separate from
## _status_label.text so set_progress can append "(N / M chunks)" onto it
## repeatedly without accumulating a new suffix onto the previous call's.
var _base_status_text := ""


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
	_base_status_text = text
	_status_label.text = text
	_elapsed_seconds = 0.0
	_spinner_label.text = LoadingSpinner.frame_for_elapsed(0.0)
	move_to_front()
	visible = true


func hide_overlay() -> void:
	visible = false


## Updates the status line with REAL, determinate chunk-load progress -- the
## one piece show_with_text's original indeterminate-only design assumed was
## unknowable (see this script's own doc comment above). `total` of 0 is
## shown as-is (matching EarthChunkManager.pending_load_chunks' own
## "nothing left to load" contract) rather than attempting a divide -- this
## only ever formats already-computed counts, so there's no division here to
## guard.
func set_progress(loaded: int, total: int) -> void:
	_status_label.text = "%s (%d / %d chunks)" % [_base_status_text, loaded, total]


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed_seconds += delta
	_spinner_label.text = LoadingSpinner.frame_for_elapsed(_elapsed_seconds)
