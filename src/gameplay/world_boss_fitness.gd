extends RefCounted

## World Boss Fitness Threshold (docs/concept/worldbosses.md "Fitness-Threshold
## Promotion Math") -- the emergent-promotion sim never places a boss by hand;
## instead an individual's accumulated level/kills/age is scored and compared
## against a per-species threshold to decide if it crosses into boss tier.

## fitness_score formula: level contributes 10 per level, each kill contributes
## 5, and age contributes 0.01 per second -- level and kills dominate at
## everyday scale, while age lets a creature that merely survives a very long
## time still climb toward boss tier.
const LEVEL_WEIGHT := 10.0
const KILL_WEIGHT := 5.0
const AGE_WEIGHT := 0.01

## promotion_threshold_for_species fallback for a species not in the table --
## an unrecognized species should never crash the promotion check.
const FALLBACK_THRESHOLD := 500.0

## species -> minimum fitness_score to be promoted to world-boss tier.
## Predators sit higher than herbivores: per worldbosses.md, becoming a boss
## should be rarer for predators.
const _SPECIES_THRESHOLDS := {
	"predator": 800.0,
	"herbivore": 400.0,
}


func fitness_score(level: int, kills: int, age_seconds: float) -> float:
	return level * LEVEL_WEIGHT + kills * KILL_WEIGHT + age_seconds * AGE_WEIGHT


func is_world_boss_eligible(score: float, threshold: float) -> bool:
	return score >= threshold


func promotion_threshold_for_species(species: String) -> float:
	return _SPECIES_THRESHOLDS.get(species, FALLBACK_THRESHOLD)


## World-Boss Phase Generator (docs/concept/worldbosses.md "Encounter design:
## emergent stats + physics spectacle + prebaked authored phases") -- the
## contract for the one-time, offline "phase authoring" call made exactly
## once at promotion time and never again during the fight. A real
## implementation would call an LLM with a natural-language description of
## the promoted individual's emergent traits and parse its response into
## phases; this base class documents that contract with a harmless default
## so tests/offline dev can swap in a fake instead of a real LLM client.
class PhaseGenerator:
	func generate_phases(_trait_description: String) -> Array:
		return []


## Deterministic fake PhaseGenerator (docs/roadmap.md "stubbed/fake LLM
## response" testing convention) -- never calls a real LLM; always returns
## the same fixed, named phase set regardless of input, so tests can assert
## on it directly instead of on real model output.
class FakePhaseGenerator extends PhaseGenerator:
	## Placeholder telegraphed-phase HP thresholds for the fake's canned
	## response -- not tuned game balance, just a deterministic stand-in for
	## a real LLM response, pinned by
	## test_fake_phase_generator_returns_pinned_phase_thresholds.
	const FAKE_PHASE_TWO_HP_THRESHOLD := 0.5
	const FAKE_PHASE_THREE_HP_THRESHOLD := 0.2

	func generate_phases(_trait_description: String) -> Array:
		return [
			{"hp_threshold": FAKE_PHASE_TWO_HP_THRESHOLD, "ability": "enrage"},
			{"hp_threshold": FAKE_PHASE_THREE_HP_THRESHOLD, "ability": "desperation_nova"},
		]


## Turns a passing eligibility check into an actual promotion (docs/concept/
## worldbosses.md "World bosses: emergent apex predators"): an eligible
## individual becomes a named world-boss record, with a set of telegraphed
## encounter phases baked in from exactly one call to phase_generator. An
## ineligible individual is never promoted -- an empty Dictionary is
## returned and phase_generator (which may wrap a real, costly LLM call) is
## never invoked at all.
func attempt_promotion(
	individual_id: String,
	species: String,
	score: float,
	trait_description: String,
	phase_generator: PhaseGenerator
) -> Dictionary:
	var threshold := promotion_threshold_for_species(species)
	if not is_world_boss_eligible(score, threshold):
		return {}
	return {
		"individual_id": individual_id,
		"species": species,
		"score": score,
		"threshold": threshold,
		"phases": phase_generator.generate_phases(trait_description),
	}
