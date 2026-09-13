extends RefCounted

## Theory-of-mind consensus for which idle NPC takes on a demanding new
## communal role (see docs/concept/npc_role_consensus.md). Self-preference
## is grounded in three of NpcGenome's existing eight real traits; every
## OTHER candidate's belief about a given candidate's preference is a real,
## fallible model that degrades toward the population-average prior the
## less well the believer actually knows them -- never a peek at their real
## internal state. Pure logic, no engine dependency, mirrors Governance's
## own static-pure-function shape exactly.
##
## Not yet wired to anything live: `familiarity` is injected directly (the
## same duck-typed-dependency shape NpcProduction.yield_per_second's own
## `world` parameter already uses) rather than read from the real
## MemoryStore/NpcEncounter system -- see this doc's own Open Questions.

## Real-world grounding (docs/concept/npc_role_consensus.md): someone
## volunteers for a new, visible communal role when they're bold enough to
## put themselves forward, motivated by what the role visibly earns
## (greedy), and not so change-averse that leaving their routine feels
## threatening (cautious, inverted). Weights sum to 1.0 so a uniformly-
## random genome's EXPECTED self_preference is exactly 0.5 -- this is what
## makes POPULATION_AVERAGE_PREFERENCE below the mathematically correct
## "average stranger" guess, not an arbitrary round number. Pinned by
## test_self_preference_of_a_perfectly_average_genome_is_the_population_
## average and the two single-trait calibration tests.
const SELF_PREFERENCE_BOLD_WEIGHT := 0.4
const SELF_PREFERENCE_GREEDY_WEIGHT := 0.35
const SELF_PREFERENCE_CAUTIOUS_WEIGHT := 0.25

## The least-informative prior: what a total stranger is modeled as
## wanting, and (by construction, see the weights above) also the expected
## self_preference of a uniformly-random genome.
const POPULATION_AVERAGE_PREFERENCE := 0.5


## A candidate's own real preference for taking on a demanding new
## communal role, grounded in three of NpcGenome's eight real traits (see
## this file's own header for why these three). `traits` is the same
## String -> float[0,1] shape NpcGenome.traits already is; a missing trait
## defaults to POPULATION_AVERAGE_PREFERENCE (the same least-informative-
## prior reasoning a missing familiarity entry uses below), never crashing
## on a partial trait dict.
static func self_preference(traits: Dictionary) -> float:
	var bold: float = traits.get("bold", POPULATION_AVERAGE_PREFERENCE)
	var greedy: float = traits.get("greedy", POPULATION_AVERAGE_PREFERENCE)
	var cautious: float = traits.get("cautious", POPULATION_AVERAGE_PREFERENCE)
	return clampf(
		(
			SELF_PREFERENCE_BOLD_WEIGHT * bold
			+ SELF_PREFERENCE_GREEDY_WEIGHT * greedy
			+ SELF_PREFERENCE_CAUTIOUS_WEIGHT * (1.0 - cautious)
		),
		0.0, 1.0
	)


## The theory-of-mind step itself: `observer_id`'s real, fallible model of
## `subject_true_preference` -- never a peek at the subject's real internal
## state, always a lerp from the population-average prior toward the real
## value by how well the observer actually knows the subject (0 = total
## stranger, modeled as exactly average; 1 = perfectly known, modeled
## exactly). `familiarity` is `observer_id -> {subject_id -> float[0,1]}`;
## a missing observer or subject entry defaults to 0.0 (a total stranger),
## never erroring.
static func believed_preference(
	observer_id: String, subject_id: String, subject_true_preference: float, familiarity: Dictionary
) -> float:
	var known_by_observer: Dictionary = familiarity.get(observer_id, {})
	var known: float = known_by_observer.get(subject_id, 0.0)
	return lerpf(POPULATION_AVERAGE_PREFERENCE, subject_true_preference, known)


## `candidate_id`'s real consensus score: its own self-preference, averaged
## evenly with what every OTHER candidate's own theory-of-mind model
## believes about it (see believed_preference). With zero other
## candidates, this IS the candidate's own self-preference -- no one else
## exists to hold a belief about them. `candidates` is `[{"id": String,
## "traits": Dictionary}, ...]`.
static func consensus_score(candidate_id: String, candidates: Array, familiarity: Dictionary) -> float:
	var own_traits := {}
	var others: Array = []
	for candidate in candidates:
		if candidate["id"] == candidate_id:
			own_traits = candidate["traits"]
		else:
			others.append(candidate)
	var own := self_preference(own_traits)
	if others.is_empty():
		return own
	var believed_sum := 0.0
	for other in others:
		believed_sum += believed_preference(other["id"], candidate_id, own, familiarity)
	return 0.5 * own + 0.5 * (believed_sum / float(others.size()))


## The real theory-of-mind consensus decision: the candidate id with the
## highest consensus_score, ties broken by id ascending (deterministic --
## no RandomNumberGenerator anywhere in this module). "" for an empty
## candidate pool.
static func decide(candidates: Array, familiarity: Dictionary) -> String:
	var best_id := ""
	var best_score := -1.0
	for candidate in candidates:
		var id: String = candidate["id"]
		var score := consensus_score(id, candidates, familiarity)
		if score > best_score or (score == best_score and id < best_id):
			best_score = score
			best_id = id
	return best_id
