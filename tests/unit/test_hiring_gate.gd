extends GutTest

## Red-first spec for the NPC instruction DSL's hiring gate (docs/concept/
## npc_instructions.md, "Execution / wiring": "hiring_gate.gd is a new
## module answering only 'may this instruction even be assigned to this
## NPC'"). Two independent, pure checks against the SAME underlying trust
## scalar (npc_trust.gd) at two different named thresholds -- not one check
## reused for two purposes:
##
##   can_hire           -- an ongoing wage relationship even starting.
##   can_assign_script  -- how elaborate a script an already-hired NPC will
##                          tolerate.

const HiringGate = preload("res://src/world/hiring_gate.gd")
const NpcTrust = preload("res://src/world/npc_trust.gd")
const VillageWages = preload("res://src/world/village_wages.gd")


# --- can_hire: trust AND wage both required, independently -------------------

func test_hireable_trust_with_a_sufficient_wage_can_hire():
	assert_true(HiringGate.can_hire(NpcTrust.HIRE_THRESHOLD, 10.0, 5.0))


## npc.md: "a stranger won't work for you at any price" -- no wage, however
## large, buys around insufficient trust.
func test_below_threshold_trust_cannot_hire_regardless_of_wage_offered():
	assert_false(HiringGate.can_hire(NpcTrust.BASELINE_TRUST, 999999.0, 5.0))


func test_hireable_trust_with_too_low_a_wage_cannot_hire():
	assert_false(HiringGate.can_hire(NpcTrust.FULL_TRUST, 1.0, 5.0))


func test_wage_exactly_at_the_minimum_can_hire():
	assert_true(HiringGate.can_hire(NpcTrust.HIRE_THRESHOLD, 5.0, 5.0))


## npc.md: an ongoing hire wage is "a genuinely new, negotiated payment, not
## VillageWages's existing flat subsistence draw" -- must clear more than
## subsistence alone, or there is no incentive to accept negotiated
## employment over passive village welfare.
func test_default_minimum_wage_clears_mere_subsistence():
	assert_gt(HiringGate.default_minimum_wage(), float(VillageWages.subsistence_wage()))


# --- can_assign_script: cost checked against npc_trust's own ceiling --------

func test_a_script_at_exactly_the_barely_hireable_ceiling_is_allowed():
	assert_true(HiringGate.can_assign_script(NpcTrust.HIRE_THRESHOLD, NpcTrust.MIN_COMPLEXITY_CEILING))


## A script over budget is rejected even for a fully-trusted NPC -- the
## ceiling still caps it, full trust does not mean unlimited.
func test_a_script_over_budget_is_rejected_even_for_a_fully_trusted_npc():
	var over_budget: float = NpcTrust.MAX_COMPLEXITY_CEILING + 1.0
	assert_false(HiringGate.can_assign_script(NpcTrust.FULL_TRUST, over_budget))


func test_a_script_over_the_barely_hireable_ceiling_is_rejected():
	var over_budget: float = NpcTrust.MIN_COMPLEXITY_CEILING + 1.0
	assert_false(HiringGate.can_assign_script(NpcTrust.HIRE_THRESHOLD, over_budget))


func test_script_cost_at_exactly_the_full_trust_ceiling_is_allowed():
	assert_true(HiringGate.can_assign_script(NpcTrust.FULL_TRUST, NpcTrust.MAX_COMPLEXITY_CEILING))
