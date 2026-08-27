extends GutTest

## InstitutionFormation: whether a cluster has coordinated enough to form (or
## keep) an institution (see docs/emergence/01-society-and-institutions.md
## "Emergence": "Institution candidates arise when clusters repeatedly
## coordinate around a common problem or opportunity... Use hysteresis:
## formation, stabilization, and dissolution thresholds prevent flicker").
##
## Grounded in something that actually exists rather than a synthetic
## trigger: FULFILLED contracts between the same two parties are real,
## already-tracked "repeated success" (one of docs/emergence/01's own
## candidate-scoring factors) -- no new coordination-tracking system needed,
## ContractStore already IS the record of who has coordinated with whom.
##
## Classic hysteresis: forms at a HIGH bar, only dissolves once coordination
## regresses well past it, not merely back to the same edge -- otherwise a
## count sitting exactly at one threshold would flicker every time a
## contract completes or expires nearby it.

const ContractStore = preload("res://src/emergence/contract_store.gd")
const InstitutionFormation = preload("res://src/emergence/institution_formation.gd")

var contracts: ContractStore


func before_each():
	contracts = ContractStore.new()


func _fulfill_a_contract(party_a: String, party_b: String) -> void:
	var contract := contracts.propose("trade", [party_a, party_b], [], "", -1.0, 1.0)
	contracts.accept(contract.id, 1.0)
	contracts.activate(contract.id, 1.0)
	contracts.fulfill(contract.id, 1.0)


# -- shared_contract_count counts real, fulfilled coordination ---------------

func test_shared_contract_count_starts_at_zero():
	assert_eq(InstitutionFormation.shared_contract_count(contracts, "household:1", "household:2"), 0)


func test_shared_contract_count_counts_fulfilled_contracts_between_both_parties():
	_fulfill_a_contract("household:1", "household:2")
	_fulfill_a_contract("household:1", "household:2")
	assert_eq(InstitutionFormation.shared_contract_count(contracts, "household:1", "household:2"), 2)


## A contract with only ONE of the two parties does not count -- it has to
## be shared BETWEEN them, not just touch one of them.
func test_shared_contract_count_ignores_contracts_with_only_one_party():
	_fulfill_a_contract("household:1", "household:3")
	assert_eq(InstitutionFormation.shared_contract_count(contracts, "household:1", "household:2"), 0)


## Only FULFILLED counts -- a merely proposed or active (not yet completed)
## contract is not "repeated SUCCESS" yet, and a breached/defaulted one is
## the opposite of coordination working.
func test_shared_contract_count_ignores_unfulfilled_contracts():
	var contract := contracts.propose("trade", ["household:1", "household:2"], [], "", -1.0, 1.0)
	contracts.accept(contract.id, 1.0)
	assert_eq(InstitutionFormation.shared_contract_count(contracts, "household:1", "household:2"), 0)


func test_shared_contract_count_ignores_breached_contracts():
	var contract := contracts.propose("trade", ["household:1", "household:2"], [], "", -1.0, 1.0)
	contracts.accept(contract.id, 1.0)
	contracts.activate(contract.id, 1.0)
	contracts.breach(contract.id, 1.0)
	assert_eq(InstitutionFormation.shared_contract_count(contracts, "household:1", "household:2"), 0)


# -- hysteresis: forms at a high bar, dissolves only well below it -----------

func test_should_form_is_false_below_the_formation_threshold():
	for i in InstitutionFormation.FORMATION_THRESHOLD - 1:
		_fulfill_a_contract("household:1", "household:2")
	assert_false(InstitutionFormation.should_form(contracts, "household:1", "household:2"))


func test_should_form_is_true_at_the_formation_threshold():
	for i in InstitutionFormation.FORMATION_THRESHOLD:
		_fulfill_a_contract("household:1", "household:2")
	assert_true(InstitutionFormation.should_form(contracts, "household:1", "household:2"))


## The dissolution threshold is a REAL gap below formation, not the same
## number -- that gap is what hysteresis actually means: at the formation
## threshold itself, an already-formed institution must NOT be considered
## for dissolution, only a genuine regression should trigger it.
func test_dissolution_threshold_is_a_real_gap_below_formation():
	assert_lt(InstitutionFormation.DISSOLUTION_THRESHOLD, InstitutionFormation.FORMATION_THRESHOLD)


func test_should_dissolve_is_false_right_at_the_formation_threshold():
	for i in InstitutionFormation.FORMATION_THRESHOLD:
		_fulfill_a_contract("household:1", "household:2")
	assert_false(InstitutionFormation.should_dissolve(contracts, "household:1", "household:2", 1.0))


func test_should_dissolve_is_true_at_or_below_the_dissolution_threshold():
	for i in InstitutionFormation.DISSOLUTION_THRESHOLD:
		_fulfill_a_contract("household:1", "household:2")
	assert_true(InstitutionFormation.should_dissolve(contracts, "household:1", "household:2", 1.0))


# -- recent_shared_contract_count: a real signal that CAN fall back to zero -

## Unlike shared_contract_count (all-time, used for FORMATION -- a strong
## track record should never be forgotten), recent_shared_contract_count is
## what DISSOLUTION reads: only contracts fulfilled within the trailing
## RECENT_WINDOW_SECONDS count, so a pair that stops coordinating genuinely
## reads as "gone quiet" rather than being protected forever by history that
## happened once, long ago.

func test_recent_shared_contract_count_counts_a_contract_still_inside_the_window():
	_fulfill_a_contract("household:1", "household:2")  # created_at = 1.0
	var now := 1.0 + InstitutionFormation.RECENT_WINDOW_SECONDS
	assert_eq(InstitutionFormation.recent_shared_contract_count(contracts, "household:1", "household:2", now), 1)


func test_recent_shared_contract_count_excludes_a_contract_outside_the_window():
	_fulfill_a_contract("household:1", "household:2")  # created_at = 1.0
	var now := 1.0 + InstitutionFormation.RECENT_WINDOW_SECONDS + 1.0
	assert_eq(InstitutionFormation.recent_shared_contract_count(contracts, "household:1", "household:2", now), 0)


## The literal gap this closes: an institution with plenty of ALL-TIME
## history (well above FORMATION_THRESHOLD, so shared_contract_count alone
## would keep it "safe" forever) genuinely becomes dissolve-eligible once
## enough real time has passed with no NEW coordination -- proving
## should_dissolve is no longer structurally unable to fire once formed.
func test_should_dissolve_becomes_true_after_the_window_passes_with_no_new_contracts():
	for i in InstitutionFormation.FORMATION_THRESHOLD + 5:  # well above formation, on purpose
		_fulfill_a_contract("household:1", "household:2")
	var still_recent := 1.0 + InstitutionFormation.RECENT_WINDOW_SECONDS
	assert_false(InstitutionFormation.should_dissolve(contracts, "household:1", "household:2", still_recent))

	var gone_quiet := 1.0 + InstitutionFormation.RECENT_WINDOW_SECONDS + 1.0
	assert_true(InstitutionFormation.should_dissolve(contracts, "household:1", "household:2", gone_quiet))


## should_form still reads the all-time count -- a strong track record is
## exactly why an institution SHOULD form, unaffected by this change.
func test_should_form_still_uses_the_all_time_count_not_the_recent_window():
	for i in InstitutionFormation.FORMATION_THRESHOLD:
		_fulfill_a_contract("household:1", "household:2")
	assert_true(InstitutionFormation.should_form(contracts, "household:1", "household:2"))
