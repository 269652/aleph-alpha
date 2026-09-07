extends PanelContainer

## The compass's own in-world HUD -- docs/concept/wayfinding.md's Compass
## item, "in-world UI" gap (see that doc's own Status section: the /compass
## dev-console command was always a real, honest INTERIM call site, never
## the design's final interaction). Auto-shown/hidden by World every frame
## based on the equipped item, mirroring TorchGlow's own "equip IS the gate"
## shape exactly (see World._update_compass_window) -- a compass put away
## tells you nothing, same as an unlit torch.
##
## A small always-on corner widget, not a toggled modal like DevConsole/
## InventoryWindow: a compass is read at a glance while walking, not opened
## and dismissed.

## A plain rotating glyph, not a new illustrated sprite -- this pass is
## about the mechanism reading correctly (docs/concept/illustrated_art_
## addressing.md's whole "drawn, not generated" pillar is about the game's
## actual subjects, not a functional HUD arrow; inventing a chroma-keyed
## sprite for a single rotating triangle would be generating a look nobody
## asked for). Godot's Label rotates its glyph like any other Control.
const NEEDLE_GLYPH := "▲"

var _needle: Label
var _reading_label: Label


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(96, 108)

	var root := VBoxContainer.new()
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var heading := Label.new()
	heading.text = "Compass"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(heading)

	var needle_box := CenterContainer.new()
	needle_box.custom_minimum_size = Vector2(0, 48)
	root.add_child(needle_box)

	_needle = Label.new()
	_needle.text = NEEDLE_GLYPH
	_needle.add_theme_font_size_override("font_size", 28)
	# The needle rotates around its own visual center, not its top-left
	# corner -- Control.pivot_offset is in the control's own local pixel
	# space, so this must be set after the label has a real size (its font
	# size above is fixed, so its minimum size is already known here).
	_needle.pivot_offset = _needle.get_minimum_size() / 2.0
	needle_box.add_child(_needle)

	_reading_label = Label.new()
	_reading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_reading_label)


## The needle's on-screen rotation, in radians, for a given reading in
## degrees. Godot's Control.rotation is clockwise-positive in screen space,
## exactly matching Compass.bearing_degrees' own clockwise-positive
## convention (see that file's own doc comment) -- a straight conversion,
## no sign flip, so a 0-degree reading (dead ahead) leaves the needle
## pointing straight up rather than sideways.
static func needle_rotation_radians(reading_degrees: float) -> float:
	return deg_to_rad(reading_degrees)


## "134° to home" -- the readout label's own text, pure formatting over an
## already-computed (and, for a rough compass, already-snapped) reading.
## Rounds to the nearest whole degree: a fine compass's raw float bearing
## would otherwise print distracting sub-degree noise no player asked for.
static func reading_text(reading_degrees: float) -> String:
	return "%d° to home" % int(round(reading_degrees))


## Pushes one real reading into the widget -- called every frame World has
## the local player's compass equipped (see World._update_compass_window).
func update_reading(reading_degrees: float) -> void:
	_needle.rotation = needle_rotation_radians(reading_degrees)
	_reading_label.text = reading_text(reading_degrees)
