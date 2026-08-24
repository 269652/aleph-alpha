extends PanelContainer

## Shown while World's boot flow verifies a personal/GitHub-bound key's
## identity (see docs/licensing.md's "Personal / GitHub-bound keys",
## github_device_auth.gd for the actual HTTP flow this displays progress
## for). Purely glue -- no decision logic of its own, just status text and
## a device-flow code display World fills in as the async flow progresses.
## Distinct from LicenseGateOverlay: that one collects a pasted key; this
## one has nothing for the player to type, only a code to read and a
## browser tab to approve in.

signal cancel_requested()

var _status_label: Label
var _code_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(480, 0)
	_build()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "GitHub Verification"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "This key is tied to a specific GitHub account."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(hint)

	_code_label = Label.new()
	_code_label.visible = false
	_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_code_label.add_theme_font_size_override("font_size", 16)
	root.add_child(_code_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status_label)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): cancel_requested.emit())
	root.add_child(cancel)


func show_status(text: String) -> void:
	_status_label.text = text


## World calls this once GitHub returns a device/user code pair --
## `user_code` is short and meant to be read and typed by hand, so it's
## shown plainly rather than needing a copy button.
func show_device_code(user_code: String, verification_uri: String) -> void:
	_code_label.text = "Enter code %s at %s" % [user_code, verification_uri]
	_code_label.visible = true
