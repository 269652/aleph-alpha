extends GutTest

## World's wiring of the player's simulation-density knobs (docs/concept/
## ecosystem_dynamics.md "Simulation density: the player's own knobs") -- a
## source-contract test on the function bodies, the same shape
## test_world_simulation_scheduler_wiring.gd uses, plus one live round trip
## through a config file of the test's own (never the player's real
## user://keybindings.cfg, which every GUT run shares).
##
## The shape mirrors the audio volume exactly: loaded from the shared
## settings file next to it in _ready, applied to the chunk manager, saved
## on change, sliders in the overlay feeding one signal.

const World = preload("res://scenes/world.gd")
const SimulationSettings = preload("res://src/gameplay/simulation_settings.gd")

const TEST_PATH := "user://test_world_simulation_settings.cfg"


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_ready_loads_the_knobs_beside_the_audio_settings_and_applies_them_to_the_chunk_manager():
	var body := _body_of("_ready")
	var audio_at := body.find("_load_audio_settings()")
	var load_at := body.find("_load_simulation_settings()")
	var apply_at := body.find("_apply_simulation_settings()")
	var manager_at := body.find("_chunk_manager = EarthChunkManager.new(")
	assert_gt(load_at, -1)
	assert_gt(apply_at, load_at, "applied after loading")
	assert_gt(apply_at, manager_at, "and only once there is a chunk manager to apply them to")
	assert_gt(audio_at, -1, "the premise")


func test_a_changed_knob_is_sanitised_applied_and_saved():
	var body := _body_of("_on_simulation_density_changed")
	assert_true(body.contains("SimulationSettings.sanitize_density("), "sanitised the way the volume is")
	assert_true(body.contains("_apply_simulation_settings()"))
	assert_true(body.contains("_save_simulation_settings()"))


func test_the_overlay_gets_the_knobs_and_its_signal_is_connected():
	var body := _body_of("_build_settings_overlay")
	assert_true(body.contains("_simulation_densities"), "the overlay is built from the loaded knobs")
	assert_true(body.contains("simulation_density_changed.connect(_on_simulation_density_changed)"))


func test_applying_pushes_every_knob_into_the_chunk_manager():
	var body := _body_of("_apply_simulation_settings")
	assert_true(body.contains("_chunk_manager.set_population_density("))
	assert_true(body.contains("SimulationSettings.KNOBS"), "every knob, driven by the one list")


func test_the_knobs_round_trip_through_a_config_file_and_survive_a_garbage_value():
	var world := World.new()
	autofree(world)
	world._simulation_densities = {"ant_foragers": 0.4, "bee_foragers": 0.7, "pollinators": 0.1}
	world._save_simulation_settings(TEST_PATH)

	var config := ConfigFile.new()
	assert_eq(config.load(TEST_PATH), OK)
	config.set_value("simulation", "pollinators", "garbage")
	config.save(TEST_PATH)

	var reloaded := World.new()
	autofree(reloaded)
	reloaded._load_simulation_settings(TEST_PATH)
	assert_eq(reloaded._simulation_densities["ant_foragers"], 0.4)
	assert_eq(reloaded._simulation_densities["bee_foragers"], 0.7)
	assert_eq(reloaded._simulation_densities["pollinators"], SimulationSettings.DEFAULT_DENSITY, "a garbage value reads as the default, never crashes")


func test_a_missing_file_leaves_the_defaults_alone():
	var world := World.new()
	autofree(world)
	world._load_simulation_settings("user://definitely_not_there.cfg")
	for knob in SimulationSettings.KNOBS:
		assert_eq(world._simulation_densities[knob], 1.0, knob)
