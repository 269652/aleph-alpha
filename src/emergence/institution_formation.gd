extends RefCounted

## Whether a cluster has coordinated enough to form (or keep) an institution
## (see docs/emergence/01-society-and-institutions.md "Emergence":
## "Institution candidates arise when clusters repeatedly coordinate around
## a common problem or opportunity... Use hysteresis: formation,
## stabilization, and dissolution thresholds prevent flicker").
##
## Grounded in something that actually exists rather than a synthetic
## trigger: FULFILLED contracts between the same two parties are real,
## already-tracked "repeated success" (one of docs/emergence/01's own
## candidate-scoring factors) -- no new coordination-tracking system needed,
## ContractStore already IS the record of who has coordinated with whom.

const ContractStore = preload("res://src/emergence/contract_store.gd")
const Contract = preload("res://src/emergence/contract.gd")

## How many fulfilled contracts two parties need to share before an
## institution forms between them. Tested (not eyeballed) against the
## hysteresis behaviour it produces (test_institution_formation.gd), not any
## specific "correct" number -- there is no real economy data yet to derive
## one from.
const FORMATION_THRESHOLD := 3

## Below FORMATION_THRESHOLD on purpose -- an already-formed institution
## should not dissolve just because its count sits at the same edge that
## formed it, only once coordination genuinely regresses well past it. That
## gap IS what hysteresis means.
const DISSOLUTION_THRESHOLD := 1


## How many FULFILLED contracts name BOTH `party_a` and `party_b`.
## Fulfilled, not any status: a merely proposed/active contract is not
## "repeated success" yet, and a breached/defaulted one is the opposite of
## coordination working.
static func shared_contract_count(store: ContractStore, party_a: String, party_b: String) -> int:
	var count := 0
	for contract in store.contracts_for(party_a):
		if contract.status == Contract.FULFILLED and contract.parties.has(party_b):
			count += 1
	return count


static func should_form(store: ContractStore, party_a: String, party_b: String) -> bool:
	return shared_contract_count(store, party_a, party_b) >= FORMATION_THRESHOLD


static func should_dissolve(store: ContractStore, party_a: String, party_b: String) -> bool:
	return shared_contract_count(store, party_a, party_b) <= DISSOLUTION_THRESHOLD
