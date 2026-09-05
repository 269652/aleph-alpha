extends PanelContainer

## The in-game companion-browser overlay (toggle Tab, see
## docs/concept/companion_server.md's "In-game overlay" section): a real
## HTTP client of the already-running local `CompanionServer`, rendering its
## HTML through `CompanionBrowser.html_to_bbcode` into a `RichTextLabel` --
## the same page a real browser tab on `127.0.0.1:8731` would show, without
## ever having to alt-tab out for it.
##
## Deliberately NOT unit-tested -- real `HTTPRequest`/`RichTextLabel`/`Node`
## I/O, the same "real socket I/O isn't something a headless test suite
## should exercise" boundary `companion_server.gd`'s own doc comment already
## draws for the server side of this exact transport. Everything that CAN be
## pure already is: see `CompanionBrowser`
## (`src/companion_server/companion_browser.gd`) and its GUT tests.

const CompanionBrowser = preload("res://src/companion_server/companion_browser.gd")
const CompanionRouter = preload("res://src/companion_server/companion_router.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const _BASE_URL := "http://127.0.0.1:%d" % CompanionRouter.PORT
const _HOME_PATH := "/"

var _http: HTTPRequest
var _path_label: Label
var _content: RichTextLabel
## The path currently shown (or being loaded) -- re-requested on toggle-open
## and by the reload button, so re-opening the overlay always shows fresh
## state rather than a stale response from earlier in the session.
var _current_path := _HOME_PATH


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(560, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)

	var title := Label.new()
	title.text = "🌿 Companion Browser"
	header.add_child(title)

	_path_label = Label.new()
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_path_label.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	header.add_child(_path_label)

	var home_button := Button.new()
	home_button.text = "Home"
	# Never keyboard-focusable: Tab is this overlay's own open/close key, and
	# a focused Button would make Godot's built-in focus-cycling (also on
	# Tab) eat the next press instead of it ever reaching _unhandled_input.
	home_button.focus_mode = Control.FOCUS_NONE
	home_button.pressed.connect(_navigate_to.bind(_HOME_PATH))
	header.add_child(home_button)

	var reload_button := Button.new()
	reload_button.text = "⟳"
	reload_button.tooltip_text = "Reload"
	reload_button.focus_mode = Control.FOCUS_NONE
	reload_button.pressed.connect(func(): _navigate_to(_current_path))
	header.add_child(reload_button)

	_content = RichTextLabel.new()
	_content.bbcode_enabled = true
	_content.scroll_active = true
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.meta_clicked.connect(_on_meta_clicked)
	layout.add_child(_content)

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Shows/hides the overlay. Always re-fetches the current page on open --
## the same "closing the tab loses nothing, reopening shows current state"
## contract the concept doc's Tier 1 section already establishes for a real
## browser tab on this server.
func toggle() -> void:
	visible = not visible
	if visible:
		_navigate_to(_current_path)


func is_open() -> bool:
	return visible


func _navigate_to(path: String) -> void:
	_current_path = path
	_path_label.text = path
	_content.text = "Loading %s ..." % path
	var error := _http.request(CompanionBrowser.resolve_href(_BASE_URL, path))
	if error != OK:
		_content.text = _unreachable_message()


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_content.text = _unreachable_message()
		return
	_content.text = CompanionBrowser.html_to_bbcode(body.get_string_from_utf8())


## A clicked `[url=...]` link's meta IS the href the page carried (see
## CompanionBrowser.html_to_bbcode's `<a href>` conversion) -- navigating is
## just treating it as the next path to load.
func _on_meta_clicked(meta) -> void:
	_navigate_to(str(meta))


func _unreachable_message() -> String:
	return (
		"[i]Companion server not reachable at %s.[/i]\n\n" % _BASE_URL
		+ "It starts automatically with the game (see docs/concept/companion_server.md) -- "
		+ "if this persists, something else may already be using its port."
	)
