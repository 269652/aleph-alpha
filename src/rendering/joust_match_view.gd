extends Control

## Node/rendering adapter for JoustMatch (docs/concept/easter_eggs.md's
## "hidden sea cave... dueling-birds cabinet" entry) -- the actual visible,
## playable arcade-cabinet screen the stone bench becomes once
## SeaCaveGuardian's challenge begins. Every game rule (physics, collision,
## scoring, best-of-three win condition) lives entirely in JoustMatch; this
## Control only reads JoustMatch's own state Dictionary each frame, draws
## it with plain Control/ColorRect children (no new art asset -- matching
## this stage's own "prefer no art asset" guidance), and reads the
## player's own flap input -- the same pure-module-plus-node-adapter split
## every other system in this project uses. Not held to JoustMatch's own
## unit-test rigor -- this project's established convention (see
## test_crafting_window.gd's own "layout glue, not game rules" framing)
## only demands that of the pure rules module; test_joust_match_view.gd
## covers this file's own thin glue (visibility, the transform beat timer,
## the finished signal) instead.
##
## A genuinely separate, self-contained mini-game loop, not just a modal
## window: scenes/world.gd pauses the whole tree while this is open
## (get_tree().paused = true, the exact same "acts like a real pause
## screen" pattern SettingsOverlay already uses -- see World.
## _toggle_settings_menu) and this Control runs via PROCESS_MODE_ALWAYS so
## it keeps advancing JoustMatch.advance() underneath that pause.
##
## Controls: tapping the existing "attack" action (Keybindings' own
## rebindable Attack/Use Tool key) flaps -- reusing an existing action
## rather than adding a new rebindable one, since ordinary attack has no
## meaning while this overlay owns the screen (the world beneath it is
## paused).
##
## Sequence: start_match() first shows the transform beat -- a short,
## timed "stone becoming cabinet" flourish matching SeaCaveGuardian.
## transform_line's own text, shown by scenes/world.gd's shared Easter-egg
## banner alongside this -- before real play begins (_active flips true),
## then runs JoustMatch to completion and emits match_finished(winner).

signal match_finished(winner: String)

const JoustMatch = preload("res://src/gameplay/joust_match.gd")

## How long the transform beat holds before real play begins -- long enough
## to read SeaCaveGuardian.TRANSFORM_LINE's own on-screen text, short
## enough that mashing "attack" the moment the encounter starts doesn't
## feel like it's doing nothing.
const TRANSFORM_DURATION := 1.2

const ARENA_SIZE := Vector2(420.0, 240.0)
const RIDER_SIZE := Vector2(22.0, 16.0)
const _BAR_THICKNESS := 6.0

var _match := JoustMatch.new()
var _state: Dictionary = {}
var _active := false
var _transform_time_remaining := 0.0

var _arena: Control
var _player_rider: ColorRect
var _ai_rider: ColorRect
var _score_label: Label
var _hint_label: Label
var _transform_panel: ColorRect


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.02, 0.05, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	add_child(backdrop)

	_arena = Control.new()
	_arena.custom_minimum_size = ARENA_SIZE
	_arena.set_anchors_preset(Control.PRESET_CENTER)
	_arena.offset_left = -ARENA_SIZE.x / 2.0
	_arena.offset_top = -ARENA_SIZE.y / 2.0
	_arena.offset_right = ARENA_SIZE.x / 2.0
	_arena.offset_bottom = ARENA_SIZE.y / 2.0
	add_child(_arena)

	var arena_bg := ColorRect.new()
	arena_bg.color = Color(0.05, 0.12, 0.22, 1.0)
	arena_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arena.add_child(arena_bg)

	var ceiling := ColorRect.new()
	ceiling.color = Color(0.3, 0.28, 0.22)
	ceiling.position = Vector2.ZERO
	ceiling.size = Vector2(ARENA_SIZE.x, _BAR_THICKNESS)
	_arena.add_child(ceiling)

	var floor_bar := ColorRect.new()
	floor_bar.color = Color(0.15, 0.35, 0.4)
	floor_bar.position = Vector2(0.0, ARENA_SIZE.y - _BAR_THICKNESS)
	floor_bar.size = Vector2(ARENA_SIZE.x, _BAR_THICKNESS)
	_arena.add_child(floor_bar)

	_player_rider = ColorRect.new()
	_player_rider.color = Color(0.95, 0.8, 0.2)
	_player_rider.size = RIDER_SIZE
	_arena.add_child(_player_rider)

	_ai_rider = ColorRect.new()
	_ai_rider.color = Color(0.75, 0.2, 0.3)
	_ai_rider.size = RIDER_SIZE
	_arena.add_child(_ai_rider)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 20)
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.offset_top = -ARENA_SIZE.y / 2.0 - 34.0
	_score_label.offset_left = -150.0
	_score_label.offset_right = 150.0
	add_child(_score_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.text = "Tap Attack to flap"
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_top = ARENA_SIZE.y / 2.0 + 10.0
	_hint_label.offset_left = -150.0
	_hint_label.offset_right = 150.0
	add_child(_hint_label)

	# The transform beat itself: a plain gray panel standing in for the
	# stone bench, covering the arena until it "becomes" the cabinet.
	_transform_panel = ColorRect.new()
	_transform_panel.color = Color(0.5, 0.5, 0.55)
	_transform_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arena.add_child(_transform_panel)
	_transform_panel.visible = false


## Begins a fresh best-of-three match: resets JoustMatch's own state,
## shows the timed transform beat, and makes the overlay visible.
func start_match() -> void:
	_state = _match.initial_state()
	_active = false
	_transform_time_remaining = TRANSFORM_DURATION
	_transform_panel.visible = true
	_score_label.text = "0 - 0"
	visible = true
	move_to_front()


func _process(delta: float) -> void:
	if not visible:
		return
	if _transform_time_remaining > 0.0:
		_transform_time_remaining -= delta
		if _transform_time_remaining <= 0.0:
			_transform_panel.visible = false
			_active = true
		return
	if not _active:
		return
	var flap := Input.is_action_just_pressed("attack")
	_state = _match.advance(_state, delta, flap)
	_update_visuals()
	if bool(_state["over"]):
		_active = false
		visible = false
		match_finished.emit(String(_state["winner"]))


func _update_visuals() -> void:
	var player_height: float = _state["player_height"]
	var ai_height: float = _state["ai_height"]
	var gap: float = _state["gap"]
	var closing: float = 1.0 - clampf(gap / JoustMatch.PASS_GAP, 0.0, 1.0)

	_player_rider.position = Vector2(
		lerpf(0.0, ARENA_SIZE.x / 2.0 - RIDER_SIZE.x, closing), _height_to_y(player_height)
	)
	_ai_rider.position = Vector2(
		lerpf(ARENA_SIZE.x - RIDER_SIZE.x, ARENA_SIZE.x / 2.0, closing), _height_to_y(ai_height)
	)
	_score_label.text = "%d - %d" % [int(_state["player_wins"]), int(_state["ai_wins"])]


## Maps a JoustMatch height (0..MAX_HEIGHT) to a pixel Y within the arena's
## own play band, between the ceiling/floor bars.
func _height_to_y(height: float) -> float:
	var usable := ARENA_SIZE.y - _BAR_THICKNESS * 2.0 - RIDER_SIZE.y
	var t := 1.0 - clampf(height / JoustMatch.MAX_HEIGHT, 0.0, 1.0)
	return _BAR_THICKNESS + t * usable
