extends Control

## The boot-time logo intro (see docs/concept/intro_splash.md). Thin engine
## glue only -- all real logic lives in the pure IntroSplashSequencer
## (frame timing) and IntroSplashSheet (the sliced art itself), mirroring
## this codebase's usual "pure model, thin Node" split. Plays the 32-frame
## illustrated sheet once at the sequencer's own pacing, then emits
## `finished`; World connects to that and shows the main menu once it
## fires. Any keyboard/mouse/gamepad press skips straight to `finished`
## early -- the same "don't trap the player behind unskippable ceremony"
## courtesy every other one-shot moment in this game already gets, and the
## only way to iterate on this scene's own timing without sitting through
## the full 3.2s every single relaunch.

signal finished

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")
const IntroSplashSequencer = preload("res://src/rendering/intro_splash_sequencer.gd")

var _frames: Array[ImageTexture] = []
var _display: TextureRect
var _elapsed := 0.0
var _finished := false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS: mirrors every other top-level UI overlay World
	# builds (see _show_main_menu's own _menu_background/_menu_backdrop/
	# _main_menu) -- this plays before the tree is ever paused, but stays
	# consistent with that convention rather than being the one overlay
	# that would stop if something upstream paused the tree earlier.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(backdrop)

	_display = TextureRect.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_display.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_display)

	_frames = IntroSplashSheet.new().generate_textures()
	if _frames.is_empty():
		# Missing/broken art shouldn't be able to hang boot forever --
		# mirrors MENU_BACKGROUND_PATH's own "missing just means the plain
		# backdrop shows, no code change needed" tolerance.
		_finish()
		return
	_display.texture = _frames[0]


func _process(delta: float) -> void:
	if _finished or _frames.is_empty():
		return
	_elapsed += delta
	_display.texture = _frames[IntroSplashSequencer.frame_index_at(_elapsed)]
	if IntroSplashSequencer.is_finished(_elapsed):
		_finish()


## Plain _input, not _unhandled_input/_gui_input: this Control covers the
## full screen, so a Control-level mouse_filter would otherwise let a click
## get consumed as GUI input before ever reaching an _unhandled_input
## handler -- _input sees every event first, keyboard/mouse/gamepad alike,
## with no routing subtlety to fight.
func _input(event: InputEvent) -> void:
	if _finished:
		return
	if not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	finished.emit()
