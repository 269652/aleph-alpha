extends GutTest

## Governance: a settlement's governance form and legitimacy, both derived
## from real flows (see docs/concept/governance.md, docs/emergence/01-
## society-and-institutions.md "Governance"/"Legitimacy").

const Governance = preload("res://src/emergence/governance.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")


# -- form_for: derived from real institution-type history, never assigned --

func test_no_institution_history_has_no_governance_form():
	assert_eq(Governance.form_for({}), Governance.NONE)


func test_a_militia_history_reads_as_military_rule():
	assert_eq(Governance.form_for({"militia": 1}), Governance.MILITARY_RULE)


func test_a_merchant_company_history_reads_as_merchant_oligarchy():
	assert_eq(Governance.form_for({"merchant_company": 1}), Governance.MERCHANT_OLIGARCHY)


func test_a_guild_history_also_reads_as_merchant_oligarchy():
	assert_eq(Governance.form_for({"guild": 1}), Governance.MERCHANT_OLIGARCHY)


func test_a_cooperative_history_reads_as_cooperative_administration():
	assert_eq(Governance.form_for({"cooperative": 1}), Governance.COOPERATIVE_ADMINISTRATION)


## A purely criminal presence has coercive power, not legitimate authority
## (docs/emergence/01's own invariant) -- no governance form yet.
func test_a_criminal_group_history_has_no_governance_form():
	assert_eq(Governance.form_for({"criminal_group": 1}), Governance.NONE)


## Whichever type has been formed MOST wins -- real historical dominance,
## not just "any institution ever."
func test_the_dominant_institution_type_determines_the_form():
	var counts := {"cooperative": 1, "militia": 5}
	assert_eq(Governance.form_for(counts), Governance.MILITARY_RULE)


func test_a_tie_breaks_toward_the_alphabetically_first_type():
	var counts := {"militia": 3, "cooperative": 3}
	assert_eq(Governance.form_for(counts), Governance.COOPERATIVE_ADMINISTRATION)


# -- legitimacy_for: derived from the one real grounded input (food) -------

func test_a_growing_settlement_has_high_legitimacy():
	assert_eq(Governance.legitimacy_for(SettlementState.GROWING), Governance.HIGH)


func test_a_declining_settlement_has_low_legitimacy():
	assert_eq(Governance.legitimacy_for(SettlementState.DECLINING), Governance.LOW)


func test_a_stable_settlement_has_stable_legitimacy():
	assert_eq(Governance.legitimacy_for(SettlementState.STABLE), Governance.STABLE_LEGITIMACY)


func test_every_documented_legitimacy_level_exists():
	var expected := ["high", "stable", "low"]
	for level in expected:
		assert_true(Governance.LEGITIMACY_LEVELS.has(level), "missing level: %s" % level)


# -- institution_type_for_new_formation: what governance actually changes --

## No governance history yet defaults to "cooperative" -- unchanged from
## before this phase, so an ungoverned settlement's automatic formation
## behaves exactly as it always has.
func test_no_governance_form_attempts_a_cooperative():
	assert_eq(Governance.institution_type_for_new_formation(Governance.NONE), "cooperative")


func test_military_rule_attempts_a_militia():
	assert_eq(Governance.institution_type_for_new_formation(Governance.MILITARY_RULE), "militia")


func test_merchant_oligarchy_attempts_a_merchant_company():
	assert_eq(Governance.institution_type_for_new_formation(Governance.MERCHANT_OLIGARCHY), "merchant_company")


func test_cooperative_administration_attempts_a_cooperative():
	assert_eq(Governance.institution_type_for_new_formation(Governance.COOPERATIVE_ADMINISTRATION), "cooperative")
