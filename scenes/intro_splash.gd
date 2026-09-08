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

## The animation's own on-screen footprint -- deliberately NOT the full
## viewport (see docs/concept/intro_splash.md's "A sixth pass"). Reported
## live: "make it smaller, about the size of the new character panel...
## otherwise it looks pixelated and wobbly" -- intro.png's frames are a
## modest native resolution (see IntroSplashSheet), so stretching them
## across the whole screen meant a much bigger upscale than shrinking the
## display box alone does, with the same STRETCH_KEEP_ASPECT_COVERED.
##
## The value matches MainMenu.PANEL_SIZE (the character creator panel the
## reporter pointed at) as of this writing -- a plain literal, NOT a live
## preload() reference to it: MainMenu's own preload chain pulls in
## CharacterPreviewDiorama and the rest of the create-screen's build
## machinery, exactly the kind of front-loaded cost this file's own
## multi-pass boot-freeze history (see the concept doc) has repeatedly
## found expensive on this exact load path -- not worth risking just to
## read one constant. Re-sync by hand if MainMenu.PANEL_SIZE ever changes.
const DISPLAY_SIZE := Vector2(880, 620)

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
	# set_deferred, NOT a direct assignment: reported live, repeatedly, as
	# "no intro plays" even after the third and fourth passes fixed every
	# timing/gating issue upstream of this node ever being added to the
	# tree -- a real, timestamped, non-headless launch showed this Control
	# (and its children below) stuck at size=(0,0) for the entire 3.2s
	# playback, visible/is_visible_in_tree() both true throughout, so
	# nothing was ever actually drawn. A freshly created top-level Control
	# with non-equal opposite anchors (PRESET_FULL_RECT sets all four to
	# different values) has its size silently overridden back to whatever
	# the anchors alone resolve to -- here (0,0), since nothing establishes
	# a parent-relative sizing context for a bare top-level Control under a
	# CanvasLayer -- in an internal layout pass that runs AFTER _ready()
	# returns, stomping any direct same-frame `size = ...` assignment.
	# Godot's own engine warning names this fix verbatim: "Nodes with non-
	# equal opposite anchors will have their size overridden after
	# _ready()... consider using set_deferred()". See
	# test_size_fills_the_viewport_once_ready_settles for real coverage
	# (confirmed red against a direct assignment first).
	set_deferred("size", get_viewport_rect().size)

	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(backdrop)
	backdrop.set_deferred("size", get_viewport_rect().size)

	_display = TextureRect.new()
	# Plain default anchors (0,0,0,0), NOT PRESET_FULL_RECT -- a direct
	# size/position write under equal opposite anchors is never overridden
	# by the layout pass that stomps a top-level full-rect Control's size
	# back to (0,0) (see `self`'s own set_deferred above and
	# test_size_fills_the_viewport_once_ready_settles), so this can be
	# assigned immediately, no set_deferred needed.
	_display.size = DISPLAY_SIZE
	_display.position = (get_viewport_rect().size - DISPLAY_SIZE) / 2.0
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


## The animation's own on-screen rect -- lets a caller (or a test) verify
## what's actually displayed without reaching past this class into the
## TextureRect node itself (same rationale as CharacterView.slot_texture).
func display_rect() -> Rect2:
	return Rect2(_display.position, _display.size)
