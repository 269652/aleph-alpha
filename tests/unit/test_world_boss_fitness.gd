extends GutTest

const WorldBossFitness = preload("res://src/gameplay/world_boss_fitness.gd")

var fitness: WorldBossFitness


func before_each():
	fitness = WorldBossFitness.new()


func test_fitness_score_increases_with_level():
	var low := fitness.fitness_score(1, 5, 100.0)
	var high := fitness.fitness_score(10, 5, 100.0)
	assert_gt(high, low)


func test_fitness_score_increases_with_kills():
	var low := fitness.fitness_score(1, 1, 100.0)
	var high := fitness.fitness_score(1, 20, 100.0)
	assert_gt(high, low)


func test_fitness_score_increases_with_age():
	var low := fitness.fitness_score(1, 1, 10.0)
	var high := fitness.fitness_score(1, 1, 100000.0)
	assert_gt(high, low)


func test_fitness_score_is_deterministic():
	var first := fitness.fitness_score(7, 12, 500.0)
	var second := fitness.fitness_score(7, 12, 500.0)
	assert_eq(first, second)


func test_is_world_boss_eligible_true_at_boundary():
	assert_true(fitness.is_world_boss_eligible(100.0, 100.0))


func test_is_world_boss_eligible_false_just_below_threshold():
	assert_false(fitness.is_world_boss_eligible(99.9, 100.0))


func test_is_world_boss_eligible_true_above_threshold():
	assert_true(fitness.is_world_boss_eligible(150.0, 100.0))


func test_promotion_threshold_predator_differs_from_herbivore():
	var predator_threshold := fitness.promotion_threshold_for_species("predator")
	var herbivore_threshold := fitness.promotion_threshold_for_species("herbivore")
	assert_ne(predator_threshold, herbivore_threshold)


func test_predator_threshold_higher_than_herbivore():
	var predator_threshold := fitness.promotion_threshold_for_species("predator")
	var herbivore_threshold := fitness.promotion_threshold_for_species("herbivore")
	assert_gt(predator_threshold, herbivore_threshold)


func test_unknown_species_returns_fallback():
	var unknown_threshold := fitness.promotion_threshold_for_species("nonexistent_species")
	assert_eq(unknown_threshold, fitness.FALLBACK_THRESHOLD)


func test_low_fitness_creature_not_eligible_against_real_threshold():
	var score := fitness.fitness_score(1, 0, 5.0)
	var threshold := fitness.promotion_threshold_for_species("herbivore")
	assert_false(fitness.is_world_boss_eligible(score, threshold))


func test_high_fitness_creature_eligible_against_real_threshold():
	var score := fitness.fitness_score(50, 200, 500000.0)
	var threshold := fitness.promotion_threshold_for_species("predator")
	assert_true(fitness.is_world_boss_eligible(score, threshold))


## --- attempt_promotion (docs/concept/worldbosses.md "World bosses: emergent
## apex predators" + "Encounter design") -------------------------------

func test_attempt_promotion_returns_empty_dict_when_not_eligible():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var record: Dictionary = fitness.attempt_promotion(
		"boar_1", "herbivore", 1.0, "a small boar", generator
	)
	assert_true(record.is_empty())


func test_attempt_promotion_returns_boss_record_when_eligible():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var threshold := fitness.promotion_threshold_for_species("herbivore")
	var record: Dictionary = fitness.attempt_promotion(
		"boar_1", "herbivore", threshold, "an ancient, unnaturally large boar", generator
	)
	assert_false(record.is_empty())


func test_attempt_promotion_record_preserves_individual_id_and_species():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var threshold := fitness.promotion_threshold_for_species("predator")
	var record: Dictionary = fitness.attempt_promotion(
		"wolf_7", "predator", threshold, "an apex wolf", generator
	)
	assert_eq(record["individual_id"], "wolf_7")
	assert_eq(record["species"], "predator")
	assert_eq(record["score"], threshold)


func test_attempt_promotion_bakes_generated_phases_into_record():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var threshold := fitness.promotion_threshold_for_species("predator")
	var record: Dictionary = fitness.attempt_promotion(
		"wolf_7", "predator", threshold, "an apex wolf", generator
	)
	assert_eq(record["phases"], generator.generate_phases("an apex wolf"))


func test_attempt_promotion_never_invokes_phase_generator_when_not_eligible():
	var counting_generator := _CountingPhaseGenerator.new()
	fitness.attempt_promotion("boar_1", "herbivore", 1.0, "a small boar", counting_generator)
	assert_eq(counting_generator.call_count, 0)


## --- PhaseGenerator / FakePhaseGenerator (docs/concept/worldbosses.md
## "Encounter design: emergent stats + physics spectacle + prebaked authored
## phases", docs/roadmap.md "stubbed/fake LLM response" convention) -----

func test_phase_generator_base_returns_empty_array():
	var generator := WorldBossFitness.PhaseGenerator.new()
	assert_eq(generator.generate_phases("anything"), [])


func test_fake_phase_generator_is_deterministic():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var first := generator.generate_phases("an apex wolf")
	var second := generator.generate_phases("an apex wolf")
	assert_eq(first, second)


func test_fake_phase_generator_returns_pinned_phase_thresholds():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var phases := generator.generate_phases("an apex wolf")
	assert_eq(phases[0]["hp_threshold"], WorldBossFitness.FakePhaseGenerator.FAKE_PHASE_TWO_HP_THRESHOLD)
	assert_eq(phases[1]["hp_threshold"], WorldBossFitness.FakePhaseGenerator.FAKE_PHASE_THREE_HP_THRESHOLD)


## Test double that counts calls, to verify attempt_promotion never invokes
## the (potentially real, costly) phase generator for an ineligible individual.
class _CountingPhaseGenerator extends WorldBossFitness.PhaseGenerator:
	var call_count := 0

	func generate_phases(_trait_description: String) -> Array:
		call_count += 1
		return []
