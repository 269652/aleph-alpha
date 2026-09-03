extends Control

## The conversation on screen (docs/concept/dialogue.md).
##
## Glue, and deliberately thin: every decision -- what this villager says, what
## the player may say back, when the conversation ends -- is made by
## `Conversation` and the pure pipeline under it. This renders what they decide
## and reports the player's choice back. Nothing here reads the world.
##
## Until this existed the dialogue engine was unreachable: `DialogueContext`,
## `DialogueTopic`, `DialogueMove` and `NpcVoice` were built and tested and had
## no production caller at all, and the talk key showed a one-line greeting
## from an eight-entry lookup table.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Conversation = preload("res://src/dialogue/conversation.gd")

## Emitted when the player closes the conversation, so World can hand keyboard
## control back to the game.
signal closed

const PANEL_WIDTH := 520.0
const PANEL_HEIGHT := 190.0
const PANEL_MARGIN := 16.0
## Clear of the hotbar along the bottom edge.
const BOTTOM_MARGIN := 96.0

var _talk = null
var _speaker_label: Label
var _line_label: RichTextLabel
var _choices: VBoxContainer


func _ready() -> void:
	visible = false
	# Anchored with real OFFSETS rather than a bare preset.
	#
	# A Control does not lay out its children, and PRESET_CENTER_BOTTOM anchors
	# both edges to the same point -- so the panel came out zero-sized at the
	# very bottom of the screen and drew off it entirely. The window opened,
	# every test passed, and nothing was visible. Positioned the way every
	# other HUD card here is (see World._build_survival_bar): anchored to an
	# edge, then offset in from it.
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 0.0
	offset_top = -PANEL_HEIGHT - BOTTOM_MARGIN
	offset_right = 0.0
	offset_bottom = -BOTTOM_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	# Centred in the strip this window occupies, at a fixed readable width.
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = 0.0
	panel.offset_bottom = PANEL_HEIGHT
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	_speaker_label = Label.new()
	_speaker_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	root.add_child(_speaker_label)

	# RichTextLabel rather than Label so a long sentence wraps rather than
	# widening the panel -- the same reason the console uses one.
	_line_label = RichTextLabel.new()
	_line_label.bbcode_enabled = false
	_line_label.fit_content = true
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line_label.add_theme_color_override("default_color", UiTheme.TEXT)
	_line_label.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_MARGIN * 2.0, 48)
	root.add_child(_line_label)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	root.add_child(_choices)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.WINDOW_BG
	style.border_color = UiTheme.PANEL_BORDER
	style.set_border_width_all(UiTheme.BORDER_WIDTH)
	style.set_corner_radius_all(UiTheme.CORNER_RADIUS)
	style.set_content_margin_all(PANEL_MARGIN)
	return style


## Opens on a conversation the caller already built. Takes the Conversation
## rather than the sources so the window never touches the world -- the same
## split every other pure/glue pair in this project uses.
func open_with(talk) -> void:
	_talk = talk
	visible = true
	_refresh()


func is_open() -> bool:
	return visible


func close() -> void:
	_talk = null
	visible = false
	closed.emit()


func _refresh() -> void:
	if _talk == null:
		close()
		return
	_speaker_label.text = _talk.speaker_name()
	_line_label.text = _talk.line()
	for child in _choices.get_children():
		child.queue_free()
	# A conversation that is over still shows its last line -- the player reads
	# what was said and then dismisses it -- so the only button is the way out.
	if _talk.is_over():
		_add_choice("", "Leave.")
		return
	for choice in _talk.choices():
		_add_choice(String(choice["id"]), String(choice["label"]))


func _add_choice(choice_id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(_on_choice.bind(choice_id))
	_choices.add_child(button)


func _on_choice(choice_id: String) -> void:
	if _talk == null or choice_id.is_empty():
		close()
		return
	_talk.choose(choice_id)
	if _talk.is_over() and choice_id == Conversation.CHOICE_LEAVE:
		close()
		return
	_refresh()
