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

## Capped so a long session's console history doesn't grow its text buffer
## unbounded -- older lines are simply dropped, not persisted anywhere.
const MAX_LOG_LINES := 12

var _parser := ConsoleCommandParser.new()
var _log_lines: Array[String] = []
var _output_label: Label
var _input: LineEdit


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(420, 160)

	var root := VBoxContainer.new()
	add_child(root)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 130)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(scroll)

	_output_label = Label.new()
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	scroll.add_child(_output_label)

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
