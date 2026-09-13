extends GutTest

## Theory-of-mind consensus for which idle NPC takes on a demanding new
## communal role (see docs/concept/npc_role_consensus.md). Self-preference
## is grounded in three of NpcGenome's real traits; a believed-preference
## is a real, fallible model of another candidate's preference that
## degrades toward the population-average prior the less well the two
## actually know each other -- never a peek at their real internal state.

const NpcRoleConsensus = preload("res://src/emergence/npc_role_consensus.gd")


# -- self_preference: grounded in bold/greedy/cautious(inverted) ------------
# Weights (0.4/0.35/0.25) sum to 1.0, so a uniformly-random genome's
# EXPECTED self_preference is exactly 0.5 -- the population-average prior
# below is this same 0.5, not an arbitrary round number.

func test_self_preference_of_a_maximally_bold_greedy_uncautious_candidate_is_one():
	var traits := {"bold": 1.0, "greedy": 1.0, "cautious": 0.0}
	assert_almost_eq(NpcRoleConsensus.self_preference(traits), 1.0, 0.0001)


func test_self_preference_of_a_maximally_timid_ungreedy_cautious_candidate_is_zero():
	var traits := {"bold": 0.0, "greedy": 0.0, "cautious": 1.0}
	assert_almost_eq(NpcRoleConsensus.self_preference(traits), 0.0, 0.0001)


func test_self_preference_of_a_perfectly_average_genome_is_the_population_average():
	var traits := {"bold": 0.5, "greedy": 0.5, "cautious": 0.5}
	assert_almost_eq(
		NpcRoleConsensus.self_preference(traits), NpcRoleConsensus.POPULATION_AVERAGE_PREFERENCE, 0.0001
	)


func test_self_preference_weighs_bold_alone():
	var traits := {"bold": 1.0, "greedy": 0.0, "cautious": 0.0}
	assert_almost_eq(NpcRoleConsensus.self_preference(traits), 0.65, 0.0001)


## Isolating greedy's own weight means ZEROING the caution term too
## (cautious=1.0 -> (1-cautious)=0), not leaving it at its own max
## contribution -- cautious=0.0 would ALSO max out the caution term
## (0.25), which is exactly the mistake this test's first version made
## (asserted 0.35, actually got 0.6 -- caught red for the right reason:
## the test's own premise, not the implementation).
func test_self_preference_weighs_greedy_alone():
	var traits := {"bold": 0.0, "greedy": 1.0, "cautious": 1.0}
	assert_almost_eq(NpcRoleConsensus.self_preference(traits), 0.35, 0.0001)


## A missing trait defaults to 0.5 -- the same least-informative-prior
## reasoning as a missing familiarity entry -- rather than crashing on a
## partial trait dict.
func test_self_preference_defaults_a_missing_trait_to_the_population_average():
	assert_almost_eq(NpcRoleConsensus.self_preference({}), 0.5, 0.0001)


# -- believed_preference: the actual theory-of-mind step ---------------------

func test_a_total_stranger_is_modeled_as_exactly_the_population_average():
	var familiarity := {}  # no entry at all -- a total stranger
	var believed := NpcRoleConsensus.believed_preference("observer", "subject", 0.9, familiarity)
	assert_almost_eq(believed, NpcRoleConsensus.POPULATION_AVERAGE_PREFERENCE, 0.0001)


func test_a_perfectly_known_subject_is_modeled_with_their_real_preference():
	var familiarity := {"observer": {"subject": 1.0}}
	var believed := NpcRoleConsensus.believed_preference("observer", "subject", 0.9, familiarity)
	assert_almost_eq(believed, 0.9, 0.0001)


func test_partial_familiarity_blends_proportionally():
	var familiarity := {"observer": {"subject": 0.5}}
	# lerp(0.5, 0.9, 0.5) == 0.7
	var believed := NpcRoleConsensus.believed_preference("observer", "subject", 0.9, familiarity)
	assert_almost_eq(believed, 0.7, 0.0001)


# -- consensus_score: self-preference blended with others' beliefs ----------

func test_consensus_score_with_no_other_candidates_is_just_self_preference():
	var candidates := [{"id": "astrid", "traits": {"bold": 1.0, "greedy": 1.0, "cautious": 0.0}}]
	var score := NpcRoleConsensus.consensus_score("astrid", candidates, {})
	assert_almost_eq(score, 1.0, 0.0001)


## Bram knows Astrid perfectly (familiarity 1.0), so his belief about her
## equals her real self_preference exactly -- the consensus score should
## equal her own self_preference too (0.5*own + 0.5*own == own).
func test_a_well_known_candidates_score_matches_their_own_self_preference():
	var candidates := [
		{"id": "astrid", "traits": {"bold": 1.0, "greedy": 1.0, "cautious": 0.0}},
		{"id": "bram", "traits": {"bold": 0.0, "greedy": 0.0, "cautious": 1.0}},
	]
	var familiarity := {"bram": {"astrid": 1.0}}
	var score := NpcRoleConsensus.consensus_score("astrid", candidates, familiarity)
	assert_almost_eq(score, 1.0, 0.0001)


## Corvin (a total stranger to Astrid) models her at the population
## average instead of her real 1.0 -- her score should sit BETWEEN her own
## self_preference and the population average, not equal either extreme.
func test_a_stranger_pulls_the_score_toward_the_population_average():
	var candidates := [
		{"id": "astrid", "traits": {"bold": 1.0, "greedy": 1.0, "cautious": 0.0}},
		{"id": "corvin", "traits": {"bold": 0.5, "greedy": 0.5, "cautious": 0.5}},
	]
	var score := NpcRoleConsensus.consensus_score("astrid", candidates, {})
	# own=1.0, corvin's belief (stranger) = 0.5 -> 0.5*1.0 + 0.5*0.5 = 0.75
	assert_almost_eq(score, 0.75, 0.0001)


# -- decide: the actual consensus pick ---------------------------------------

func test_decide_picks_the_highest_scoring_candidate():
	var candidates := [
		{"id": "astrid", "traits": {"bold": 1.0, "greedy": 1.0, "cautious": 0.0}},
		{"id": "bram", "traits": {"bold": 0.0, "greedy": 0.0, "cautious": 1.0}},
	]
	assert_eq(NpcRoleConsensus.decide(candidates, {}), "astrid")


func test_decide_breaks_an_exact_tie_by_id_ascending():
	var candidates := [
		{"id": "zed", "traits": {"bold": 0.5, "greedy": 0.5, "cautious": 0.5}},
		{"id": "amy", "traits": {"bold": 0.5, "greedy": 0.5, "cautious": 0.5}},
	]
	assert_eq(NpcRoleConsensus.decide(candidates, {}), "amy")


func test_decide_on_an_empty_candidate_pool_returns_empty_string():
	assert_eq(NpcRoleConsensus.decide([], {}), "")


## The full worked example from docs/concept/npc_role_consensus.md: Astrid
## (bold/greedy/uncautious) beats Bram (timid/ungreedy/cautious) and
## Corvin (an exactly-average newcomer), regardless of who knows whom.
func test_the_worked_example_astrid_wins_the_wood_role():
	var candidates := [
		{"id": "astrid", "traits": {"bold": 0.9, "greedy": 0.7, "cautious": 0.1}},
		{"id": "bram", "traits": {"bold": 0.2, "greedy": 0.3, "cautious": 0.8}},
		{"id": "corvin", "traits": {"bold": 0.5, "greedy": 0.5, "cautious": 0.5}},
	]
	var familiarity := {
		"astrid": {"bram": 0.9, "corvin": 0.1},
		"bram": {"astrid": 0.9, "corvin": 0.1},
		"corvin": {"astrid": 0.1, "bram": 0.1},
	}
	assert_eq(NpcRoleConsensus.decide(candidates, familiarity), "astrid")
