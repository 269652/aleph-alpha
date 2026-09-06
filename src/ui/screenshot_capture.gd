extends Node

## Global "press a key, get a screenshot" service (see docs/concept/
## screenshots.md). Registered as an autoload (see project.godot) so it
## exists -- and its InputMap action already works -- from the moment the
## engine boots, before the main menu's own _ready() and well before any
## World/Player exists.
##
## That is the whole reason this is its own autoload rather than routed
## through World's existing Keybindings/InputMap wiring: World._apply_
## keybindings only ever runs once a game session actually starts (see
## Keybindings.display_key_for's own doc comment on that exact gap), so a
## key that must already work from the character-creation diorama cannot be
## one of Keybindings.ACTIONS. Deliberately NOT rebindable in the settings
## menu for the same reason -- fixed to F12 (a keyboard's own long-standing
## screenshot convention, and unused by every action in Keybindings.ACTIONS).
##
## Split the same way every other autoload in this codebase is:
## ScreenshotNaming carries the pure, fully-tested filename/path logic; this
## class is the thin glue that actually reads a real viewport and writes a
## real file -- exactly the part that cannot run under --headless (see
## test_screenshot_capture.gd's own guard), so it is deliberately kept as
## small as possible and every branch of it is reachable through the two
## injected Callables below without ever touching a real window in a test.

const ScreenshotNaming = preload("res://src/ui/screenshot_naming.gd")

signal screenshot_saved(path: String)
signal screenshot_failed(reason: String)

const ACTION := "screenshot"
const DEFAULT_KEYCODE := KEY_F12

## Injected so tests can force a capture failure (or hand back a fake image)
## without ever touching a real viewport -- calling the real one under
## --headless raises its own engine-level error regardless of how
## gracefully the resulting Nil is handled afterward.
var _image_source: Callable = _capture_image
## Injected so a save can be pinned to an exact, deterministic filename in a
## test instead of racing the real wall clock.
var _now: Callable = Time.get_datetime_dict_from_system


func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
	InputMap.action_erase_events(ACTION)
	var event := InputEventKey.new()
	event.physical_keycode = DEFAULT_KEYCODE
	InputMap.action_add_event(ACTION, event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		take_screenshot()


## The real entry point -- also directly callable without a key event (a dev
## console `/screenshot` command, say).
func take_screenshot() -> void:
	var image: Image = _image_source.call()
	if image == null:
		screenshot_failed.emit("no real viewport image to capture (headless, or not yet rendered)")
		return
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive(ScreenshotNaming.DIRECTORY)
	var path := ScreenshotNaming.unique_path_for(_now.call(), func(p): return FileAccess.file_exists(p))
	var err := image.save_webp(path)
	if err != OK:
		screenshot_failed.emit("save_webp failed: %s" % error_string(err))
		return
	screenshot_saved.emit(path)


func _capture_image() -> Image:
	var viewport := get_viewport()
	if viewport == null:
		return null
	var texture := viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()
