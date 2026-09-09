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

## The sheet's own per-frame pixel footprint -- measured directly
## (tools/probe_intro_sheet.gd), not assumed from the 1983/8 x 793/4
## arithmetic (see IntroSplashSheet's own doc comment for why that's not
## exact for this sheet). Real per-frame rects vary by a pixel or two from
## this across the 32 real sliced frames (232-234 wide, 181-183 tall) --
## 233x182 is simply the single most common exact size among them. This is
## the ONE reference size DISPLAY_SIZE scales from, not a per-frame live
## measurement, so the on-screen box itself never resizes as playback
## moves between frames of very slightly different native size -- only
## STRETCH_KEEP_ASPECT_CENTERED's own letterboxing absorbs that tiny
## variance (see _ready's own comment).
const _NATIVE_FRAME_SIZE := Vector2(233, 182)

## Reported live: "make it smaller, about the size of the new character
## panel... otherwise it looks pixelated and wobbly" (see docs/concept/
## intro_splash.md's "A seventh pass"). That pass shrank the display box to
## an arbitrary literal (880x620, matching MainMenu.PANEL_SIZE) while
## keeping STRETCH_KEEP_ASPECT_COVERED -- smaller than full-screen, but
## still an arbitrary non-integer upscale of the sheet's own modest native
## resolution, which is exactly what "pixelated and wobbly" describes:
## Godot's default (effectively linear) filter softens/shimmers hard
## pixel-art edges at any scale that doesn't land on whole pixels.
## Reported again, live, on top of that already-shipped fix: "it should be
## much smaller." This pass ("An eighth pass") replaces the arbitrary
## literal with a genuine pixel-perfect integer scale instead, mirroring
## MainMenu.STANDARD_PORTRAIT_SCALE's own established "roundi a target
## against the real native size" pattern -- see that constant's own doc
## comment. 3x keeps the box comfortably smaller than the seventh pass's
## own 880x620 in both dimensions (699x546) while staying a legible,
## deliberate multiple -- a tested, named constant, not an eyeballed one
## (see test_display_size_is_a_clean_integer_multiple_of_the_native_frame_
## size and test_display_is_pixel_perfect in test_intro_splash.gd).
const DISPLAY_SCALE := 3
const DISPLAY_SIZE := _NATIVE_FRAME_SIZE * DISPLAY_SCALE

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
	# KEEP_ASPECT_CENTERED, not COVERED: COVERED crops overflow to fill the
	# box exactly, which would crop away a sliver of real content on
	# whichever frames run a pixel or two larger than _NATIVE_FRAME_SIZE
	# (see that constant's own doc comment). CENTERED letterboxes instead --
	# since DISPLAY_SIZE is an exact integer multiple of the reference frame
	# size, the common case lands on an exact 1:1 fit with zero letterbox at
	# all, and the rare ±1-2px outlier frame just gets an imperceptible
	# sliver of backdrop at one edge rather than a crop.
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# NEAREST, not Godot's default filter: the other half of "pixelated and
	# wobbly", not fixed by shrinking the box alone -- a smooth filter
	# blurs/shimmers hard pixel-art edges at any non-1:1 scale, independent
	# of how big or small the box is. Matches this game's established
	# "16-bit house style" nearest-neighbor convention for every other
	# generated/sliced texture scaled up to a deliberate integer multiple
	# (e.g. MainMenu._standard_portrait at STANDARD_PORTRAIT_SCALE).
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


## A lone modifier keycode -- pressed on its own, with nothing else --
## does not count as a "skip this" gesture. Reported live: the intro kept
## getting skipped by an incidental Alt press, very plausibly from
## alt-tabbing away during the long boot wait, not a deliberate press.
## Godot reports the modifier itself as an ordinary InputEventKey the
## instant it's pressed (keycode == KEY_ALT), indistinguishable at that
## point from a real skip key -- the window-manager combo it's actually
## part of (Alt+Tab) is consumed by Windows before any second key event
## would reach this game at all, so there is no "wait and see" signal
## available here to tell the two apart after the fact. Applied
## symmetrically to Ctrl/Shift/Meta for the same reason: a lone modifier
## press is how every OS-level combo a long unattended wait might provoke
## BEGINS, not how a player expresses "skip the intro" on its own. A real
## key pressed WHILE a modifier is held (e.g. Alt+Space) still skips --
## only a modifier with nothing else is excluded.
const _MODIFIER_ONLY_KEYCODES := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


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
	if event is InputEventKey and event.keycode in _MODIFIER_ONLY_KEYCODES:
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


## Whether the animation is rendering with crisp, unfiltered integer-scale
## pixel art rather than Godot's default smooth filter -- see DISPLAY_
## SCALE's own doc comment for why that distinction is the actual fix for
## "pixelated and wobbly", not just the box shrinking alone. Same "let a
## test verify without reaching past this class" rationale as display_rect.
func display_is_pixel_perfect() -> bool:
	return (
		_display.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and _display.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
