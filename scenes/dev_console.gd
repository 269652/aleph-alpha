extends PanelContainer

## A minimal dev/debug console: press the toggle key (backtick, see
## the toggle_console action, default backtick) to open it, type a "/command arg1 arg2"
## line and press Enter to run it. This node only owns the UI (input line,
## scrollable output log) and parsing (via ConsoleCommandParser) -- it emits
## what was typed and leaves dispatching the actual command to World, which
## is the one that knows about the chunk manager, player, etc. Escape closes
## it without submitting.

signal command_submitted(command: String, args: Array)

const ConsoleCommandParser = preload("res://src/gameplay/console_command_parser.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Height of the output viewport (the ScrollContainer), and the height of one
## rendered row in it: the shared UI theme's font (UiTheme.BASE_FONT_SIZE = 14)
## measures 20px per line. Both are pinned against the real font metrics by
## test_visible_rows_is_derived_from_the_real_font_metrics, so a theme change
## breaks that test instead of silently making VISIBLE_ROWS a fiction.
const OUTPUT_HEIGHT := 130.0
const LINE_HEIGHT_PX := 20.0

## How many rows the viewport shows at once: 130 / 20.
const VISIBLE_ROWS := 6

## How far back the console can be scrolled, in screens of output -- the one
## product decision here; everything else is measured. Thirty-two screens is
## comfortably more than one whole multi-line report: /history logs ONE line
## per recorded event (World._handle_history_command splits Why.explain_entity
## and calls log_line per line), and the previous cap of a dozen LOGICAL lines
## truncated every such report to its own tail before it could be read.
const SCROLLBACK_SCREENS := 32

## Scrollback cap, so a long session's history doesn't grow the text buffer
## unbounded -- older lines are simply dropped, not persisted anywhere.
## Pinned by test_scrollback_holds_a_whole_multi_line_report (lower bound)
## and test_scrollback_is_still_bounded (upper bound).
const MAX_LOG_LINES := VISIBLE_ROWS * SCROLLBACK_SCREENS

var _parser := ConsoleCommandParser.new()
var _log_lines: Array[String] = []
var _output_label: RichTextLabel
var _input: LineEdit


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(420, 160)

	var root := VBoxContainer.new()
	add_child(root)

	# A RichTextLabel that owns its OWN scrollbar, rather than a plain Label
	# inside a ScrollContainer.
	#
	# The old pairing had a defect no amount of scroll-to-bottom could fix:
	# ScrollContainer refreshes its scrollbar range in _reposition_children
	# BEFORE fitting the child, so the range it publishes is the one from
	# before this pass's growth -- and it never queues another sort, so it
	# never catches up. Measured on the real class: after a burst of logging
	# the content stood 848 px tall while the range stopped at 779. Those
	# 69 px were the last three rows, unreachable by the scroll call AND by
	# the mouse wheel, because a scrollbar clamps to max - page. The answer to
	# whatever you had just typed sat permanently below the floor of the box.
	#
	# The previous fix aimed at the wrong thing -- it moved the scroll POSITION,
	# and the position was already as far down as it was allowed to go. Two
	# other repairs were measured and rejected: an awaited process frame does
	# nothing (this is not a too-early scroll), and queue_sort() inside
	# log_line collapsed the scroll area outright under a one-frame burst.
	#
	# RichTextLabel recomputes its own scrollbar from its own reshaped content,
	# which is the exact step ScrollContainer skips, and `scroll_following`
	# keeps the view pinned to the newest line for free.
	_output_label = RichTextLabel.new()
	_output_label.custom_minimum_size = Vector2(0, OUTPUT_HEIGHT)
	_output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_label.bbcode_enabled = false
	_output_label.scroll_active = true
	_output_label.scroll_following = true
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# UiTheme sets font_color for "Label"; RichTextLabel reads "default_color"
	# instead, so without this the console text falls back to plain white
	# rather than the shared text colour.
	_output_label.add_theme_color_override("default_color", UiTheme.TEXT)
	root.add_child(_output_label)

	_input = LineEdit.new()
	_input.placeholder_text = "/help"
	_input.text_submitted.connect(_on_text_submitted)
	_input.gui_input.connect(_on_input_gui_input)
	root.add_child(_input)

	log_line("Dev console ready. Type /help for commands.")


## Shows/hides the console and grabs/releases keyboard focus accordingly,
## keeping ConsoleFocus (see that autoload's doc comment) in sync so the
## player stops reading raw keyboard input while typing.
func toggle() -> void:
	visible = not visible
	ConsoleFocus.is_open = visible
	if visible:
		_input.clear()
		_input.grab_focus()
	else:
		_input.release_focus()


func log_line(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > MAX_LOG_LINES:
		_log_lines.pop_front()
	_output_label.text = "\n".join(_log_lines)
	_scroll_to_newest()


## Keeps the newest line visible.
##
## RichTextLabel's own `scroll_following` already does this whenever the view
## is at the bottom, and it does it against a scrollbar range the control
## recomputes from its own content -- which is the part the old
## ScrollContainer+Label stack got wrong. This stays as the explicit nudge for
## the one case following does not cover: a view the user has scrolled UP to
## read, where following is suspended until they return to the bottom.
func _scroll_to_newest() -> void:
	if _output_label == null:
		return
	var bar := _output_label.get_v_scroll_bar()
	if bar != null:
		bar.value = bar.max_value


func _on_text_submitted(text: String) -> void:
	_input.clear()
	if text.strip_edges().is_empty():
		return

	log_line("> " + text)
	var parsed := _parser.parse(text)
	if parsed.command.is_empty():
		return
	command_submitted.emit(parsed.command, parsed.args)


## Escape closes the console while its input field has focus. accept_event()
## stops the same press falling through to World._unhandled_input, which
## would otherwise ALSO see it as the settings-menu toggle and pop the paused
## settings menu open behind the just-closed console.
func _on_input_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		accept_event()
