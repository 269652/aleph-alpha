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
var _output_scroll: ScrollContainer
var _output_label: Label
var _input: LineEdit


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(420, 160)

	var root := VBoxContainer.new()
	add_child(root)

	_output_scroll = ScrollContainer.new()
	_output_scroll.custom_minimum_size = Vector2(0, OUTPUT_HEIGHT)
	_output_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# The same pairing every other scrolling surface in this project uses
	# (crafting_window.gd, settings_overlay.gd, skill_tree_window.gd,
	# main_menu.gd): a ScrollContainer only stretches a child to its own width
	# if that child is SIZE_EXPAND -- otherwise the child gets its own MINIMUM
	# width, which for an autowrapping Label is ~1px, so every logged line
	# wrapped to one word per row. Disabling horizontal scrolling keeps it that
	# way and drops the horizontal scrollbar that was also eating log height.
	_output_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_output_scroll)

	_output_label = Label.new()
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fires from inside ScrollContainer's own child-fitting pass, i.e. after it
	# has already refreshed the scrollbar's max_value -- the one moment the new
	# bottom is actually known. Deliberately NOT an awaited process frame: a
	# coroutine that resumes after the console is freed errors out.
	_output_label.resized.connect(_scroll_to_newest)
	_output_scroll.add_child(_output_label)

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
	# Covers the case where the label did NOT change height (buffer already at
	# MAX_LOG_LINES), so `resized` never fires.
	_scroll_to_newest()


## Keeps the newest line visible. Without this the ScrollContainer stayed at
## position 0 forever and every command's answer landed below the fold -- the
## console could not show its own output. scroll_vertical is clamped by Godot
## to (max_value - page), so assigning max_value means "bottom".
func _scroll_to_newest() -> void:
	if _output_scroll == null:
		return
	_output_scroll.scroll_vertical = int(_output_scroll.get_v_scroll_bar().max_value)


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
