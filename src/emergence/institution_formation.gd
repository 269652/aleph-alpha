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


## How long a real coordination window stays fresh (docs/progress.md's
## Emergence Phase 6 gap-closing entry: `shared_contract_count` alone is
## ALL-TIME and monotonically non-decreasing, so `should_dissolve` built
## against it can only ever be true BEFORE formation, never after -- a real
## structural reason automatic dissolution had no live trigger, not just an
## unbuilt one). Tested against the behaviour it produces
## (test_institution_formation.gd), same honesty as FORMATION_THRESHOLD's
## own doc comment: no real economy data yet to derive a "correct" window
## from, but real, deterministic behavior this project can pin a test to.
const RECENT_WINDOW_SECONDS := 300.0


## How many FULFILLED contracts two parties share, created within
## RECENT_WINDOW_SECONDS of `now` -- unlike shared_contract_count (all-time,
## what FORMATION reads: a strong track record should never be forgotten),
## this can genuinely fall back toward zero if a pair stops coordinating,
## which is what makes automatic DISSOLUTION a real, meaningful signal: an
## institution whose members haven't worked together recently is genuinely
## at risk, regardless of how much history they have -- the same real-world
## distinction between "has a track record" (formation) and "is still
## active" (staying formed).
static func recent_shared_contract_count(store: ContractStore, party_a: String, party_b: String, now: float) -> int:
	var count := 0
	for contract in store.contracts_for(party_a):
		if (
			contract.status == Contract.FULFILLED
			and contract.parties.has(party_b)
			and (now - contract.created_at) <= RECENT_WINDOW_SECONDS
		):
			count += 1
	return count


static func should_dissolve(store: ContractStore, party_a: String, party_b: String, now: float) -> bool:
	return recent_shared_contract_count(store, party_a, party_b, now) <= DISSOLUTION_THRESHOLD
