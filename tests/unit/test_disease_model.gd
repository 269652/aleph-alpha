extends GutTest

## Pure SIRS wildlife disease model -- see docs/concept/disease.md and
## src/gameplay/disease_model.gd.

const DiseaseModel = preload("res://src/gameplay/disease_model.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")

var model


func before_each():
	model = DiseaseModel.new()


# -- region pressure ----------------------------------------------------------

func test_region_pressure_is_higher_further_from_spawn():
	var easy: float = model.region_pressure_multiplier(RegionDifficulty.Tier.EASY)
	var medium: float = model.region_pressure_multiplier(RegionDifficulty.Tier.MEDIUM)
	var hard: float = model.region_pressure_multiplier(RegionDifficulty.Tier.HARD)
	assert_lt(easy, medium, "MEDIUM should run hotter disease pressure than EASY")
	assert_lt(medium, hard, "HARD should run hotter disease pressure than MEDIUM")


func test_region_pressure_easy_is_baseline_1():
	assert_eq(model.region_pressure_multiplier(RegionDifficulty.Tier.EASY), 1.0)


# -- herd (foot-and-mouth-like) transmission -----------------------------------

func test_herd_transmission_chance_is_zero_at_zero_density():
	var chance: float = model.herd_transmission_chance(0.0, 20.0, RegionDifficulty.Tier.EASY)
	assert_eq(chance, 0.0)


func test_herd_transmission_chance_rises_with_density_ratio():
	var sparse: float = model.herd_transmission_chance(2.0, 20.0, RegionDifficulty.Tier.EASY)
	var crowded: float = model.herd_transmission_chance(18.0, 20.0, RegionDifficulty.Tier.EASY)
	assert_lt(sparse, crowded, "a crowded region should be a measurable tinderbox")


func test_herd_transmission_chance_is_scaled_by_region_pressure():
	var easy: float = model.herd_transmission_chance(15.0, 20.0, RegionDifficulty.Tier.EASY)
	var hard: float = model.herd_transmission_chance(15.0, 20.0, RegionDifficulty.Tier.HARD)
	assert_lt(easy, hard)


func test_herd_transmission_chance_handles_zero_carrying_capacity_without_crashing():
	var chance: float = model.herd_transmission_chance(5.0, 0.0, RegionDifficulty.Tier.EASY)
	assert_eq(chance, 0.0)


func test_herd_transmission_chance_stays_within_0_and_1():
	var chance: float = model.herd_transmission_chance(1000.0, 1.0, RegionDifficulty.Tier.HARD)
	assert_between(chance, 0.0, 1.0)


# -- predator (rabies-like) bite transmission ----------------------------------

func test_predator_bite_chance_rises_with_region_pressure():
	var easy: float = model.predator_bite_transmission_chance(RegionDifficulty.Tier.EASY)
	var hard: float = model.predator_bite_transmission_chance(RegionDifficulty.Tier.HARD)
	assert_lt(easy, hard)
	assert_between(hard, 0.0, 1.0)


# -- carrion (anthrax-like): contamination, carry, graze -----------------------

func test_carcass_contamination_chance_rises_with_region_pressure():
	var easy: float = model.carcass_contamination_chance(RegionDifficulty.Tier.EASY)
	var hard: float = model.carcass_contamination_chance(RegionDifficulty.Tier.HARD)
	assert_lt(easy, hard)
	assert_between(hard, 0.0, 1.0)


func test_decomposer_carry_chance_rises_with_region_pressure():
	var easy: float = model.decomposer_carry_chance(RegionDifficulty.Tier.EASY)
	var hard: float = model.decomposer_carry_chance(RegionDifficulty.Tier.HARD)
	assert_lt(easy, hard)
	assert_between(hard, 0.0, 1.0)


func test_carrion_graze_transmission_chance_rises_with_region_pressure():
	var easy: float = model.carrion_graze_transmission_chance(RegionDifficulty.Tier.EASY)
	var hard: float = model.carrion_graze_transmission_chance(RegionDifficulty.Tier.HARD)
	assert_lt(easy, hard)
	assert_between(hard, 0.0, 1.0)


# -- deterministic rolls --------------------------------------------------------

func test_attempt_transmit_is_deterministic_for_the_same_seed():
	var first: bool = model.attempt_transmit(0.5, 42)
	var second: bool = model.attempt_transmit(0.5, 42)
	assert_eq(first, second)


func test_attempt_transmit_never_succeeds_at_zero_chance():
	for seed_value in range(20):
		assert_false(model.attempt_transmit(0.0, seed_value))


func test_attempt_transmit_always_succeeds_at_full_chance():
	for seed_value in range(20):
		assert_true(model.attempt_transmit(1.0, seed_value))


func test_attempt_infect_delegates_to_the_same_roll_as_attempt_transmit():
	for seed_value in range(20):
		assert_eq(model.attempt_infect(0.5, seed_value), model.attempt_transmit(0.5, seed_value))


# -- lethality per archetype ----------------------------------------------------

func test_herd_disease_is_never_lethal_by_itself():
	assert_false(model.is_lethal_capable(DiseaseModel.HERD))
	assert_eq(model.death_chance_per_second(DiseaseModel.HERD), 0.0)


func test_predator_and_carrion_diseases_are_lethal_capable():
	assert_true(model.is_lethal_capable(DiseaseModel.PREDATOR))
	assert_true(model.is_lethal_capable(DiseaseModel.CARRION))
	assert_gt(model.death_chance_per_second(DiseaseModel.PREDATOR), 0.0)
	assert_gt(model.death_chance_per_second(DiseaseModel.CARRION), 0.0)


# -- secondary effect: herd disease weakens rather than damages -----------------

func test_movement_speed_multiplier_is_full_speed_at_zero_severity():
	assert_eq(model.movement_speed_multiplier(0.0), 1.0)


func test_movement_speed_multiplier_drops_as_severity_rises():
	assert_lt(model.movement_speed_multiplier(1.0), model.movement_speed_multiplier(0.3))
	assert_gt(model.movement_speed_multiplier(1.0), 0.0)


# -- SIRS state machine (advance_state) -----------------------------------------

func test_susceptible_stays_susceptible_and_severity_free():
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.SUSCEPTIBLE, DiseaseModel.HERD, 0.0, 0.0, 5.0, 1
	)
	assert_eq(result["state"], DiseaseModel.State.SUSCEPTIBLE)
	assert_eq(result["severity"], 0.0)
	assert_false(result["died"])


func test_infected_herd_severity_rises_over_time_and_never_dies():
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.INFECTED, DiseaseModel.HERD, 0.0, 0.0, 5.0, 1
	)
	assert_gt(result["severity"], 0.0)
	assert_false(result["died"])
	assert_eq(result["state"], DiseaseModel.State.INFECTED)


func test_infected_herd_recovers_after_its_full_infectious_duration():
	var duration: float = model.infectious_duration(DiseaseModel.HERD)
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.INFECTED, DiseaseModel.HERD, 0.9, duration - 0.5, 1.0, 1
	)
	assert_eq(result["state"], DiseaseModel.State.RECOVERED)
	assert_eq(result["severity"], 0.0)


func test_infected_lethal_disease_can_die_when_the_death_roll_hits():
	# A huge delta drives death_chance_per_second * delta past 1.0, which
	# attempt_transmit's roll (always < 1) always beats -- deterministic
	# regardless of seed, so this doesn't depend on tuned constants lining
	# up with a lucky seed.
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.INFECTED, DiseaseModel.PREDATOR, 0.5, 1.0, 1000.0, 7
	)
	assert_true(result["died"])


func test_infected_herd_can_never_die_no_matter_the_delta():
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.INFECTED, DiseaseModel.HERD, 0.5, 1.0, 1000.0, 7
	)
	assert_false(result["died"])


func test_recovered_wanes_back_to_susceptible_after_immunity_duration():
	var duration: float = model.immunity_duration(DiseaseModel.HERD)
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.RECOVERED, DiseaseModel.HERD, 0.0, duration - 0.5, 1.0, 1
	)
	assert_eq(result["state"], DiseaseModel.State.SUSCEPTIBLE)


func test_recovered_stays_recovered_before_immunity_wanes():
	var result: Dictionary = model.advance_state(
		DiseaseModel.State.RECOVERED, DiseaseModel.HERD, 0.0, 0.0, 1.0, 1
	)
	assert_eq(result["state"], DiseaseModel.State.RECOVERED)


func test_full_sirs_cycle_returns_to_susceptible():
	# susceptible -> infected -> recovered -> susceptible again, driven purely
	# by advance_state -- the "S...S again" shape disease.md's design pillar
	# names directly.
	var state: int = DiseaseModel.State.SUSCEPTIBLE
	var severity := 0.0
	var state_seconds := 0.0
	# Force infection first (susceptible->infected isn't advance_state's job,
	# it's attempt_infect's -- simulate it landing here).
	state = DiseaseModel.State.INFECTED
	var infectious_steps := int(model.infectious_duration(DiseaseModel.HERD)) + 2
	for i in infectious_steps:
		var result: Dictionary = model.advance_state(state, DiseaseModel.HERD, severity, state_seconds, 1.0, i)
		state = result["state"]
		severity = result["severity"]
		state_seconds = result["state_seconds"]
	assert_eq(state, DiseaseModel.State.RECOVERED)

	var immunity_steps := int(model.immunity_duration(DiseaseModel.HERD)) + 2
	for i in immunity_steps:
		var result: Dictionary = model.advance_state(state, DiseaseModel.HERD, severity, state_seconds, 1.0, i)
		state = result["state"]
		state_seconds = result["state_seconds"]
	assert_eq(state, DiseaseModel.State.SUSCEPTIBLE)
