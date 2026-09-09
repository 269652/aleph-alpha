extends Control

## Full-screen "the game is working, not hung" cover, shown while New Game /
## Host / Load Game / Join pay their real world-setup cost (see
## World._show_loading_overlay and the entry points that call it), and by
## MainMenu's own character-creator build (docs/concept/intro_splash.md).
##
## Requested live: "make the loading screens use SIMS 4 style loading
## descriptions (funny witty progress lines) and put the real progress in
## the bottom right corner." Two real, separate readouts now, not one: a
## big, centered, rotating witty tip (LoadingTips -- the primary thing a
## player actually reads while waiting) and a small technical corner
## readout, bottom-right, pairing the spinner glyph with the caller's own
## status text and any REAL determinate progress a caller reports via
## set_progress ("N / M chunks"/"N / M portraits", see
## EarthChunkManager.update_with_progress and docs/concept/persistence.md's
## "Loading screens" section). This used to be impossible: the heavy call
## this covers (EarthChunkManager.update()'s first call for a fresh chunk
## radius, ~39-90s+ measured in this dev sandbox, see docs/progress.md) had
## no `await` anywhere in its own call chain, so the engine could never
## present a frame during it and the spinner necessarily froze on whatever
## glyph it was on for the ENTIRE real duration -- reported back as "the
## loading screen ... still looks like it's hanging" even with an honest
## indeterminate spinner in place. update_with_progress fixes the actual
## cause (it awaits a frame between each chunk instead of loading the whole
## radius in one uninterrupted loop), which is what makes both the
## spinner's own animation AND the real percentage visible for the first
## time.
##
## Getting a real frame to present is NOT enough on its own, though --
## reported live a second time, specifically about the tip: "the new witty
## loading screen texts should change every few seconds not stay the same
## for 1 min loading." Even across genuinely-presented frames, Godot's
## delta smoothing (ON by default in this project) can replace a real,
## large single-frame `delta` -- exactly what a heavy synchronous stretch
## like MushroomMarker.warm_art_cache() produces between its own internal
## yields -- with a much smaller smoothed estimate, so accumulating
## `_process`'s own `delta` badly undercounts real elapsed time. Both the
## tip AND the spinner now derive _elapsed_seconds from real wall-clock
## time instead (Time.get_ticks_msec(), see _advance_to's own doc comment
## for the full measured story), immune to whatever `delta` claims.
##
## PROCESS_MODE_ALWAYS (set by World, matching every other paused-but-live
## overlay in this file -- SettingsOverlay/MainMenu) so both the spinner
## and the tip rotation keep advancing across every awaited frame, even
## though the world is paused underneath it the whole time.

const LoadingSpinner = preload("res://src/ui/loading_spinner.gd")
const LoadingTips = preload("res://src/ui/loading_tips.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## The witty tip's own on-screen footprint -- wide enough that most real
## lines in LoadingTips.TIPS (see that file's own length-tested contract,
## under 120 characters) fit on one or two wrapped lines at a comfortably
## readable size, not the old, much narrower single-status-line box this
## replaces.
const _TIP_BOX_HALF_SIZE := Vector2(340.0, 60.0)

## How far (px) the corner readout sits from the viewport's own bottom-
## right corner -- comfortably clear of the edge, matching the kind of
## margin every other corner-anchored HUD element in this project already
## uses (e.g. the minimap), not flush against the pixels.
const _CORNER_MARGIN_PX := 24.0

var _tip_label: Label
var _corner_spinner_label: Label
var _corner_status_label: Label
var _elapsed_seconds := 0.0
## Real wall-clock start time (Time.get_ticks_msec(), set by show_with_text)
## that _elapsed_seconds is derived FROM every _process call -- see
## _advance_to's own doc comment for why this reads the real clock instead
## of accumulating _process's own `delta` argument.
var _start_ticks_msec := 0
## Rolled fresh each show_with_text call (see that function) so different
## loading screens open on a different witty tip rather than always the
## same one -- LoadingTips.tip_for_elapsed's own "caller rolls the start,
## the module only decides" contract.
var _tip_start_offset := 0
## The text show_with_text was called with, kept separate from
## _corner_status_label.text so set_progress can append "(N / M <unit>)"
## onto it repeatedly without accumulating a new suffix onto the previous
## call's.
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

	# The witty tip: the big, centered, primary readout -- what a player
	# actually reads while waiting, replacing the old plain status line in
	# this prominent spot (the caller's own status text moves to the
	# corner readout below instead, alongside real progress).
	var tip_box := CenterContainer.new()
	tip_box.set_anchors_preset(Control.PRESET_CENTER)
	tip_box.offset_left = -_TIP_BOX_HALF_SIZE.x
	tip_box.offset_top = -_TIP_BOX_HALF_SIZE.y
	tip_box.offset_right = _TIP_BOX_HALF_SIZE.x
	tip_box.offset_bottom = _TIP_BOX_HALF_SIZE.y
	add_child(tip_box)

	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 20)
	_tip_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(_TIP_BOX_HALF_SIZE.x * 2.0, 0.0)
	tip_box.add_child(_tip_label)

	# The technical corner readout: spinner glyph + caller's own status
	# text + any real determinate progress (see set_progress) -- small,
	# bottom-right, for a player who actually wants the number rather than
	# the joke.
	var corner_box := HBoxContainer.new()
	corner_box.alignment = BoxContainer.ALIGNMENT_END
	corner_box.add_theme_constant_override("separation", 8)
	corner_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner_box.offset_left = -320.0
	corner_box.offset_top = -28.0
	corner_box.offset_right = -_CORNER_MARGIN_PX
	corner_box.offset_bottom = -_CORNER_MARGIN_PX
	add_child(corner_box)

	_corner_spinner_label = Label.new()
	_corner_spinner_label.add_theme_font_size_override("font_size", 16)
	_corner_spinner_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	corner_box.add_child(_corner_spinner_label)

	_corner_status_label = Label.new()
	_corner_status_label.add_theme_font_size_override("font_size", 13)
	_corner_status_label.modulate = Color(1, 1, 1, 0.7)
	_corner_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	corner_box.add_child(_corner_status_label)


## Shows the overlay with `text` as the corner status line (see
## set_progress for appending real progress to it), on top of every other
## child of its parent (see World._show_loading_overlay, which awaits two
## process frames right after calling this so it genuinely paints before
## the synchronous work it's covering starts). Rolls a fresh random witty-
## tip start offset each time, so repeated loads don't always open on the
## same line.
func show_with_text(text: String) -> void:
	_base_status_text = text
	_corner_status_label.text = text
	_elapsed_seconds = 0.0
	_start_ticks_msec = Time.get_ticks_msec()
	_tip_start_offset = randi() % LoadingTips.TIPS.size()
	_tip_label.text = LoadingTips.tip_for_elapsed(0.0, _tip_start_offset)
	_corner_spinner_label.text = LoadingSpinner.frame_for_elapsed(0.0)
	move_to_front()
	visible = true


func hide_overlay() -> void:
	visible = false


## Updates the corner status line with REAL, determinate progress -- the
## one piece show_with_text's original indeterminate-only design assumed
## was unknowable (see this script's own doc comment above). `total` of 0
## is shown as-is (matching EarthChunkManager.pending_load_chunks' own
## "nothing left to load" contract) rather than attempting a divide --
## this only ever formats already-computed counts, so there's no division
## here to guard.
##
## `unit` defaults to "chunks" -- World's own chunk-loading callers (New
## World/Load Game/Join, via _on_chunk_load_progress) pass none at all, so
## their existing "N / M chunks" wording is unchanged. Added when MainMenu's
## own character-creator build (a different real cost -- class-icon
## portraits, not chunks) needed this same real-progress treatment: "N / M
## chunks" would have been a real, honest-sounding lie about what was
## actually being counted.
func set_progress(loaded: int, total: int, unit: String = "chunks") -> void:
	_corner_status_label.text = "%s (%d / %d %s)" % [_base_status_text, loaded, total, unit]


## Lets a test verify what's actually shown without reaching past this class
## into `_corner_status_label` itself -- same rationale as IntroSplash.
## display_rect/display_is_pixel_perfect.
func status_text() -> String:
	return _corner_status_label.text


## The witty tip currently on screen -- lets a test verify the rotation
## without reaching past this class into `_tip_label` itself, same
## rationale as status_text() above.
func tip_text() -> String:
	return _tip_label.text


## Recomputes _elapsed_seconds from REAL elapsed wall-clock time
## (`now_ms - _start_ticks_msec`) and refreshes both readouts that depend
## on it, rather than accumulating `_process`'s own `delta` argument the
## way this used to work.
##
## Reported live: "the new witty loading screen texts should change every
## few seconds not stay the same for 1 min loading." Real, measured cause:
## Godot's delta smoothing (`application/run/delta_smoothing`, ON by
## default in this project -- confirmed via `OS.is_delta_smoothing_enabled()`
## returning true with no project.godot override) silently replaces the
## real, large `delta` a genuine multi-second synchronous stall produces
## with a much smaller smoothed estimate, since it's designed to iron out
## ordinary frame-to-frame V-sync jitter, not survive a multi-second
## outlier. Measured live against the real boot-time
## `MushroomMarker.warm_art_cache()` call (the dominant, ~52-144s+
## real-machine-dependent boot cost this overlay covers, see
## docs/progress.md): ~144 real seconds elapsed (Time.get_ticks_msec) while
## the old `_elapsed_seconds += delta` accumulation only reached ~4.9
## "seconds" -- a ~29x gap. Since both the tip AND the spinner glyph
## (LoadingSpinner.frame_for_elapsed also reads _elapsed_seconds) advanced
## only by that accumulated delta, both froze on their opening frame for
## nearly the entire real load -- not a coincidence limited to the tip.
##
## Takes `now_ms` explicitly instead of calling Time.get_ticks_msec()
## itself so a test can simulate real elapsed time passing without
## literally waiting for it -- the same "caller supplies the real input,
## this just computes" split LoadingTips.tip_for_elapsed/LoadingSpinner.
## frame_for_elapsed already use one level up (see test_loading_overlay.gd).
func _advance_to(now_ms: int) -> void:
	_elapsed_seconds = float(now_ms - _start_ticks_msec) / 1000.0
	_corner_spinner_label.text = LoadingSpinner.frame_for_elapsed(_elapsed_seconds)
	_tip_label.text = LoadingTips.tip_for_elapsed(_elapsed_seconds, _tip_start_offset)


func _process(_delta: float) -> void:
	if not visible:
		return
	_advance_to(Time.get_ticks_msec())
