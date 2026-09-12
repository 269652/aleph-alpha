extends GutTest

## SimulationSettings (src/gameplay/simulation_settings.gd) -- the player's
## own simulation-density knobs (docs/concept/ecosystem_dynamics.md
## "Simulation density: the player's own knobs"): pure sanitising and cap
## scaling, the same shape AudioSettings gives the master volume. The three
## knobs each scale one design ceiling (ant foragers per mound, bee foragers
## per hive, pollinators per chunk); defaults are exactly today's behaviour.

const SimulationSettings = preload("res://src/gameplay/simulation_settings.gd")


func test_the_three_knobs_are_named_and_default_to_full_density():
	assert_eq(SimulationSettings.KNOBS, ["ant_foragers", "bee_foragers", "pollinators"])
	assert_eq(SimulationSettings.DEFAULT_DENSITY, 1.0)
	var defaults: Dictionary = SimulationSettings.default_densities()
	for knob in SimulationSettings.KNOBS:
		assert_eq(defaults[knob], 1.0, knob)


func test_sanitize_passes_a_valid_density_through_unchanged():
	assert_eq(SimulationSettings.sanitize_density(0.35), 0.35)
	assert_eq(SimulationSettings.sanitize_density(1.0), 1.0)
	assert_eq(SimulationSettings.sanitize_density(0.0), 0.0)


func test_sanitize_clamps_out_of_range_values_and_falls_back_for_nan():
	assert_eq(SimulationSettings.sanitize_density(1.7), 1.0, "a knob only ever lowers a ceiling")
	assert_eq(SimulationSettings.sanitize_density(-0.2), 0.0)
	assert_eq(SimulationSettings.sanitize_density(NAN), SimulationSettings.DEFAULT_DENSITY)


func test_a_scaled_cap_rounds_and_never_drops_below_its_floor():
	assert_eq(SimulationSettings.scaled_cap(15, 1.0, 1), 15, "full density: the design ceiling itself")
	assert_eq(SimulationSettings.scaled_cap(15, 0.2, 1), 3)
	assert_eq(SimulationSettings.scaled_cap(15, 0.0, 1), 1, "a colony always keeps its one scout")
	assert_eq(SimulationSettings.scaled_cap(4, 0.0, 0), 0, "a pollinator budget may go all the way down")
	assert_eq(SimulationSettings.scaled_cap(4, 0.5, 0), 2)


func test_a_scaled_cap_sanitises_its_density_too():
	assert_eq(SimulationSettings.scaled_cap(10, 3.0, 1), 10)
	assert_eq(SimulationSettings.scaled_cap(10, NAN, 1), 10)


func test_a_densities_dictionary_is_sanitised_knob_by_knob_with_unknown_keys_dropped():
	var cleaned: Dictionary = SimulationSettings.sanitize_densities({
		"ant_foragers": 0.5, "pollinators": 2.0, "bogus": 0.1,
	})
	assert_eq(cleaned["ant_foragers"], 0.5)
	assert_eq(cleaned["bee_foragers"], 1.0, "a missing knob reads as the default")
	assert_eq(cleaned["pollinators"], 1.0, "clamped")
	assert_false(cleaned.has("bogus"))
