extends PanelContainer

## The pause / settings menu (opened with toggle_settings, default Escape).
## Three sections selectable by tab buttons: KEY BINDINGS (one rebindable row
## per action from the tested Keybindings model -- click a key, press a new
## one), GRAPHICS (fullscreen, vsync), and LICENSE (paste a new key to
## replace the current one -- see docs/licensing.md's "In-game license
## entry"). A Resume button closes it. Purely glue -- the rebinding
## registry/rules live in Keybindings; World owns applying the InputMap,
## pausing the game, persisting keybinding/graphics settings, and actually
## verifying/saving a submitted license code.

const Keybindings = preload("res://src/gameplay/keybindings.gd")
const RenderResolution = preload("res://src/rendering/render_resolution.gd")

signal binding_changed(action_name: String, keycode: int)
signal reset_requested()
signal graphics_changed(setting: String, enabled: bool)
## Settings that are a CHOICE rather than on/off (render resolution).
signal graphics_option_changed(setting: String, value: String)
signal resume_requested()
signal license_code_submitted(code: String)

var _bindings: Keybindings
var _key_section: VBoxContainer
var _graphics_section: VBoxContainer
var _license_section: VBoxContainer
var _license_edit: TextEdit
var _license_status_label: Label
var _rows: Dictionary = {}  # action -> Button showing the key
var _listening_action := ""
var _listening_button: Button


## World hands in its live Keybindings + the current graphics state so the
## menu renders from the same source of truth World applies.
func setup(bindings: Keybindings, fullscreen: bool, vsync: bool, resolution: String = "") -> void:
	_bindings = bindings
	_build(fullscreen, vsync, resolution)


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(400, 0)


func toggle() -> void:
	visible = not visible
	if not visible:
		_stop_listening()


func is_open() -> bool:
	return visible


func _build(fullscreen: bool, vsync: bool, resolution: String = "") -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	# Tab bar.
	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	var key_tab := Button.new()
	key_tab.text = "Key Bindings"
	key_tab.pressed.connect(func(): _show_section("keys"))
	tabs.add_child(key_tab)
	var gfx_tab := Button.new()
	gfx_tab.text = "Graphics"
	gfx_tab.pressed.connect(func(): _show_section("graphics"))
	tabs.add_child(gfx_tab)
	var license_tab := Button.new()
	license_tab.text = "License"
	license_tab.pressed.connect(func(): _show_section("license"))
	tabs.add_child(license_tab)

	_key_section = _build_key_section()
	root.add_child(_key_section)
	_graphics_section = _build_graphics_section(fullscreen, vsync, resolution)
	root.add_child(_graphics_section)
	_license_section = _build_license_section()
	root.add_child(_license_section)

	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func(): resume_requested.emit())
	root.add_child(resume)

	_show_section("keys")


func _build_key_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 3)

	var hint := Label.new()
	hint.text = "Click a key, then press a new key to rebind."
	hint.modulate = Color(1, 1, 1, 0.6)
	section.add_child(hint)

	# The binding list is longer than the panel, so it scrolls (fixes the
	# earlier no-scrollbar overflow off the bottom of the screen).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for action in _bindings.action_names():
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = _bindings.label_for(action)
		name_label.custom_minimum_size = Vector2(220, 0)
		row.add_child(name_label)

		var key_button := Button.new()
		key_button.custom_minimum_size = Vector2(130, 0)
		key_button.text = _key_name(_bindings.keycode_for(action))
		key_button.pressed.connect(_on_key_button_pressed.bind(action, key_button))
		row.add_child(key_button)

		rows.add_child(row)
		_rows[action] = key_button

	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(_on_reset_pressed)
	section.add_child(reset)
	return section


func _build_graphics_section(fullscreen: bool, vsync: bool, resolution: String = "") -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = fullscreen
	fs.toggled.connect(func(on): graphics_changed.emit("fullscreen", on))
	section.add_child(fs)

	var vs := CheckBox.new()
	vs.text = "VSync"
	vs.button_pressed = vsync
	vs.toggled.connect(func(on): graphics_changed.emit("vsync", on))
	section.add_child(vs)

	# Render resolution: the one lever that scales the whole frame at once
	# (see RenderResolution). A choice rather than a toggle, so it gets an
	# OptionButton and its own signal.
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = "Render resolution"
	row.add_child(caption)

	var picker := OptionButton.new()
	var chosen := RenderResolution.sanitize(resolution)
	for i in RenderResolution.OPTIONS.size():
		var option: String = RenderResolution.OPTIONS[i]
		picker.add_item(RenderResolution.label_for(option), i)
		if option == chosen:
			picker.select(i)
	picker.item_selected.connect(
		func(index): graphics_option_changed.emit(
			"render_resolution", RenderResolution.OPTIONS[index]
		)
	)
	row.add_child(picker)
	section.add_child(row)

	var hint := Label.new()
	hint.text = "Lower renders fewer pixels and scales up -- softer, but much faster."
	hint.add_theme_font_size_override("font_size", 12)
	section.add_child(hint)
	return section


## Lets a player replace their current key without leaving the game or
## hand-editing license.txt (see docs/licensing.md's "In-game license
## entry"). Distinct from LicenseGateOverlay: that one blocks play
## entirely with no valid key yet; this one is reachable only once
## already playing, for "I want to swap in a different key" (e.g.
## upgrading a trial to a full key).
func _build_license_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	var hint := Label.new()
	hint.text = (
		"Paste a new license key below to replace your current one -- " +
		"line breaks are fine."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	section.add_child(hint)

	_license_edit = TextEdit.new()
	_license_edit.custom_minimum_size = Vector2(0, 140)
	_license_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	section.add_child(_license_edit)

	var submit := Button.new()
	submit.text = "Verify & Save"
	submit.pressed.connect(func(): license_code_submitted.emit(_license_edit.text))
	section.add_child(submit)

	_license_status_label = Label.new()
	_license_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	section.add_child(_license_status_label)
	return section


## World calls this after checking a submitted code -- generic wording
## only, never the real failure `reason` (see LicenseGateOverlay's own
## doc comment for the same rule, restated here since this is a separate
## Control with its own status label).
func show_license_status(text: String) -> void:
	_license_status_label.text = text


func _show_section(which: String) -> void:
	_stop_listening()
	_key_section.visible = which == "keys"
	_graphics_section.visible = which == "graphics"
	_license_section.visible = which == "license"


func _on_key_button_pressed(action: String, button: Button) -> void:
	_stop_listening()
	_listening_action = action
	_listening_button = button
	button.text = "Press a key…"


func _on_reset_pressed() -> void:
	_stop_listening()
	reset_requested.emit()
	_refresh_labels()


## While listening, captures the next key press as the new binding. Otherwise,
## closes the menu on the settings/pause key -- needed because World is paused
## while the menu is open and so stops receiving input itself (this node runs
## via PROCESS_MODE_ALWAYS). Consumes handled events so the key doesn't also
## trigger game behavior that frame.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _listening_action != "":
		if event is InputEventKey and event.pressed:
			var keycode: int = event.physical_keycode
			if keycode == 0:
				keycode = event.keycode
			var action := _listening_action
			_stop_listening()
			binding_changed.emit(action, keycode)
			_refresh_labels()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_settings"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


func _stop_listening() -> void:
	if _listening_button != null and _listening_action != "":
		_listening_button.text = _key_name(_bindings.keycode_for(_listening_action))
	_listening_action = ""
	_listening_button = null


func _refresh_labels() -> void:
	for action in _rows:
		_rows[action].text = _key_name(_bindings.keycode_for(action))


func _key_name(keycode: int) -> String:
	if keycode == 0:
		return "—"
	return OS.get_keycode_string(keycode)
