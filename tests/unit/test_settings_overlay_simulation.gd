extends GutTest

## The Settings overlay's "Simulation" section (docs/concept/
## ecosystem_dynamics.md "Simulation density: the player's own knobs"): one
## slider per SimulationSettings knob, built from the loaded densities and
## feeding one signal, the exact shape of the audio section's master-volume
## slider. Built directly through _build_simulation_section, the way the
## section itself is assembled, so no key bindings or graphics state is
## needed to prove it.

const SettingsOverlay = preload("res://scenes/settings_overlay.gd")
const SimulationSettings = preload("res://src/gameplay/simulation_settings.gd")

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


func test_the_section_holds_one_slider_per_knob_set_to_the_loaded_density():
	var section: Control = overlay._build_simulation_section({
		"ant_foragers": 0.5, "bee_foragers": 0.25, "pollinators": 1.0,
	})
	var sliders := _sliders_in(section)
	assert_eq(sliders.size(), SimulationSettings.KNOBS.size(), "one per knob, in knob order")
	assert_eq(sliders[0].value, 0.5)
	assert_eq(sliders[1].value, 0.25)
	assert_eq(sliders[2].value, 1.0)
	for slider in sliders:
		assert_eq(slider.min_value, 0.0)
		assert_eq(slider.max_value, 1.0, "a knob only ever lowers a ceiling")


func test_a_missing_knob_shows_the_default_density():
	var section: Control = overlay._build_simulation_section({})
	for slider in _sliders_in(section):
		assert_eq(slider.value, SimulationSettings.DEFAULT_DENSITY)


func test_moving_a_slider_emits_the_knob_and_its_new_density():
	var section: Control = overlay._build_simulation_section(SimulationSettings.default_densities())
	var received: Array = []
	overlay.simulation_density_changed.connect(func(knob: String, value: float): received.append([knob, value]))
	# Range.value_changed does not fire from a script-side `.value = x` in
	# this Godot build -- only real interaction does (the same gotcha the
	# audio slider's own investigation recorded). Emitting the slider's own
	# signal exercises exactly the wiring a drag would.
	_sliders_in(section)[1].value_changed.emit(0.3)
	assert_eq(received, [["bee_foragers", 0.3]])
