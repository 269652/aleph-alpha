extends PanelContainer

## Shown INSTEAD OF the game world when LicenseGate reports no valid
## license (see World._ready(), docs/licensing.md's "In-game license
## entry") -- lets a player paste/type a key and try again without
## hand-editing a license.txt file and restarting from scratch. Purely
## glue: World owns actually calling LicenseGate.check_licensed() and
## LicenseStore.write_code(), and deciding what happens next (reload the
## scene on success). Never shows the specific failure `reason` a check
## returns -- docs/licensing.md's own "generic failure message" rule (a
## would-be keygen author shouldn't get a free debugging oracle from
## what's shown here).

signal verify_requested(code: String)
signal quit_requested()

var _code_edit: TextEdit
var _status_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "License Required"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var hint := Label.new()
	hint.text = (
		"No valid license key was found. Paste your key below -- line " +
		"breaks are fine -- and press Verify & Save."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(hint)

	_code_edit = TextEdit.new()
	_code_edit.custom_minimum_size = Vector2(0, 160)
	_code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(_code_edit)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status_label)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)

	var verify := Button.new()
	verify.text = "Verify & Save"
	verify.pressed.connect(func(): verify_requested.emit(_code_edit.text))
	buttons.add_child(verify)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): quit_requested.emit())
	buttons.add_child(quit)


## World calls this after checking the pasted code -- generic wording
## only, never the real `reason` (see this file's own doc comment).
func show_status(text: String) -> void:
	_status_label.text = text
