extends GutTest

## Red-first spec for the smallest real player-NPC trust scalar (docs/concept/
## npc_instructions.md, Design pillar 5; docs/concept/npc.md "Hiring &
## instruction": "a stranger won't work for you at any price, but an NPC
## whose quest you completed... will"). Mirrors src/gameplay/pet_loyalty.gd's
## shape but NOT its numbers -- see src/world/npc_trust.gd's own doc comment
## for why BASELINE_TRUST must sit below HIRE_THRESHOLD where pet_loyalty's
## BASELINE_LOYALTY sits above its FOLLOW_THRESHOLD.
##
## Every tuned constant here is pinned by a test, per CLAUDE.md's "tuned
## values/thresholds must be tested functions or test-pinned constants,
## never eyeballed comments."

const NpcTrust = preload("res://src/world/npc_trust.gd")

var trust_model: NpcTrust


func before_each():
	trust_model = NpcTrust.new()


# --- baseline trust is deliberately NOT hireable ----------------------------

func test_baseline_trust_is_below_the_hire_threshold():
	assert_lt(NpcTrust.BASELINE_TRUST, NpcTrust.HIRE_THRESHOLD)


func test_a_freshly_met_npc_is_not_hireable():
	assert_false(trust_model.is_hireable(NpcTrust.BASELINE_TRUST))


func test_trust_at_the_hire_threshold_is_hireable():
	assert_true(trust_model.is_hireable(NpcTrust.HIRE_THRESHOLD))


func test_trust_above_the_hire_threshold_is_hireable():
	assert_true(trust_model.is_hireable(NpcTrust.HIRE_THRESHOLD + 0.1))


# --- complexity ceiling: a CONTINUOUS function of trust, not a second gate --
# docs/concept/npc_instructions.md: "a stranger... tolerates only a trivial
# one-or-two-rule script; an NPC whose quest you completed... tolerates
# something closer to the worked example" -- a smooth scale, pinned here at
# 3 points: right at the hire threshold, at full trust, and in between.

func test_ceiling_at_the_hire_threshold_is_the_minimum():
	assert_almost_eq(
		trust_model.complexity_ceiling_for(NpcTrust.HIRE_THRESHOLD),
		NpcTrust.MIN_COMPLEXITY_CEILING,
		0.0001
	)


func test_ceiling_at_full_trust_is_the_maximum():
	assert_almost_eq(
		trust_model.complexity_ceiling_for(NpcTrust.FULL_TRUST),
		NpcTrust.MAX_COMPLEXITY_CEILING,
		0.0001
	)


func test_ceiling_at_the_midpoint_is_strictly_between_min_and_max():
	var midpoint_trust: float = (NpcTrust.HIRE_THRESHOLD + NpcTrust.FULL_TRUST) / 2.0
	var ceiling: float = trust_model.complexity_ceiling_for(midpoint_trust)
	assert_gt(ceiling, NpcTrust.MIN_COMPLEXITY_CEILING)
	assert_lt(ceiling, NpcTrust.MAX_COMPLEXITY_CEILING)


func test_ceiling_strictly_increases_with_trust():
	var lower: float = trust_model.complexity_ceiling_for(0.6)
	var higher: float = trust_model.complexity_ceiling_for(0.8)
	assert_gt(higher, lower)


## Below the hire threshold an NPC can't be hired at all (hiring_gate.gd's
## own concern) -- this function must still fail closed to a well-defined,
## never-negative number instead of extrapolating past the minimum.
func test_ceiling_below_hire_threshold_clamps_at_the_minimum():
	assert_almost_eq(
		trust_model.complexity_ceiling_for(NpcTrust.BASELINE_TRUST),
		NpcTrust.MIN_COMPLEXITY_CEILING,
		0.0001
	)
