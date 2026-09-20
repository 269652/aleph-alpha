extends GutTest

## The Settings overlay's "Interface" section (docs/concept/hud.md "UI scale"):
## one slider for the UI scale, the exact shape of the audio section's
## master-volume slider. Built directly through _build_interface_section, the
## way the section itself is assembled, so no key bindings or graphics state is
## needed to prove it.

const SettingsOverlay = preload("res://scenes/settings_overlay.gd")
const UiScale = preload("res://src/ui/ui_scale.gd")

var overlay: SettingsOverlay


func before_each():
	overlay = SettingsOverlay.new()
	add_child_autofree(overlay)


func _sliders_in(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is HSlider:
			out.append(child)
		out.append_array(_sliders_in(child))
	return out


func test_the_section_holds_one_slider_set_to_the_loaded_scale():
	var section: Control = overlay._build_interface_section(1.25)
	var sliders := _sliders_in(section)
	assert_eq(sliders.size(), 1)
	assert_eq(sliders[0].value, 1.25)


## The slider is range-limited to exactly what UiScale allows, so a value that
## came from this slider never needs sanitizing again -- the same contract the
## master-volume slider already has.
func test_the_slider_cannot_leave_the_range_the_model_allows():
	var slider: HSlider = _sliders_in(overlay._build_interface_section(1.0))[0]
	assert_eq(slider.min_value, UiScale.MIN_SCALE)
	assert_eq(slider.max_value, UiScale.MAX_SCALE)


## A settings file from before this setting existed reads as the default, which
## is exactly today's look.
func test_an_out_of_range_stored_scale_shows_sanitized():
	var slider: HSlider = _sliders_in(overlay._build_interface_section(99.0))[0]
	assert_eq(slider.value, UiScale.MAX_SCALE)


func test_moving_the_slider_emits_the_new_scale():
	var section: Control = overlay._build_interface_section(UiScale.DEFAULT_SCALE)
	var received: Array = []
	overlay.ui_scale_changed.connect(func(value: float): received.append(value))
	# Range.value_changed does not fire from a script-side `.value = x` in this
	# Godot build -- only real interaction does (the same gotcha the audio
	# slider's own investigation recorded). Emitting the slider's own signal
	# exercises exactly the wiring a drag would.
	_sliders_in(section)[0].value_changed.emit(1.5)
	assert_eq(received, [1.5])
