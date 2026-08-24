extends GutTest

## BossPhase (docs/concept/worldbosses.md's Krampus encounter-design
## section): reads a WorldBossFitness.PhaseGenerator-shaped phases array
## ({"hp_threshold", "ability"}, the SAME shape whether it came from a
## one-shot LLM call or a hand-authored kit -- see BossPhaseKits) and
## answers "which of these should be active right now" from a live
## health_fraction. Pure lookup, no execution -- this does not perform an
## ability, just selects which one(s) a live fight should be drawing from.

const BossPhase = preload("res://src/gameplay/boss_phase.gd")

var phase: BossPhase

const TWO_PHASE := [
	{"hp_threshold": 0.5, "ability": "enrage"},
	{"hp_threshold": 0.2, "ability": "desperation_nova"},
]

## Krampus's real kit shape: two abilities share the SAME threshold.
const SHARED_THRESHOLD := [
	{"hp_threshold": 0.5, "ability": "chain_lash"},
	{"hp_threshold": 0.5, "ability": "terrifying_roar"},
	{"hp_threshold": 0.2, "ability": "chain_shackle"},
]


func before_each():
	phase = BossPhase.new()


func test_active_phases_empty_above_every_threshold():
	assert_eq(phase.active_phases(TWO_PHASE, 1.0), [])
	assert_eq(phase.active_phases(TWO_PHASE, 0.51), [])


func test_active_phases_includes_a_threshold_just_crossed():
	var active := phase.active_phases(TWO_PHASE, 0.5)
	assert_eq(active.size(), 1)
	assert_eq(active[0]["ability"], "enrage")


func test_active_phases_accumulates_every_threshold_crossed():
	var active := phase.active_phases(TWO_PHASE, 0.2)
	assert_eq(active.size(), 2)


func test_current_phase_returns_empty_dict_when_nothing_is_active():
	assert_eq(phase.current_phase(TWO_PHASE, 1.0), {})


func test_current_phase_is_the_most_escalated_one_reached():
	# At 0.2 HP both thresholds have been crossed -- the LOWER threshold
	# (further escalated) should win, not the first one crossed.
	var current := phase.current_phase(TWO_PHASE, 0.2)
	assert_eq(current["ability"], "desperation_nova")


func test_current_phase_at_the_higher_threshold_alone():
	var current := phase.current_phase(TWO_PHASE, 0.35)
	assert_eq(current["ability"], "enrage")


## Krampus-shaped: two abilities unlock at the SAME threshold (phase 2 is
## "chain_lash" AND "terrifying_roar" together, not a single ability).
func test_active_ability_names_returns_every_ability_at_a_shared_threshold():
	var names := phase.active_ability_names(SHARED_THRESHOLD, 0.5)
	assert_eq(names.size(), 2)
	assert_true(names.has("chain_lash"))
	assert_true(names.has("terrifying_roar"))


func test_active_ability_names_accumulates_across_phases():
	var names := phase.active_ability_names(SHARED_THRESHOLD, 0.2)
	assert_eq(names.size(), 3)
	assert_true(names.has("chain_shackle"))


func test_empty_phases_array_is_always_inactive():
	assert_eq(phase.active_phases([], 0.0), [])
	assert_eq(phase.current_phase([], 0.0), {})
	assert_eq(phase.active_ability_names([], 0.0), [])
