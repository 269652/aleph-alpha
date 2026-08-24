extends RefCounted

## An agreement between parties (see
## docs/emergence/03-contracts-property-economy.md "Contracts": "Contract {
## parties[], obligations[], consideration[], deadline, enforcement,
## status }").
##
## Pure data -- ContractStore owns assigning `id` and driving status
## transitions, the same split Event/EventStore already use. `obligations`
## and `consideration` stay free-form strings rather than structured
## amounts: this project has no real currency/resource-flow simulation
## wired to NPCs yet (see docs/roadmap.md's Emergence Phase 5, not built),
## and inventing one just to give a contract a number to hold would be
## exactly the premature complexity the master brief warns against.

## Documented initial types (docs/emergence/03): employment, supply,
## construction, loan, rent, protection, transport, trade.
const TYPES := [
	"employment", "supply", "construction", "loan", "rent", "protection", "transport", "trade",
]

## The lifecycle (docs/emergence/03): "proposed -> accepted -> active ->
## fulfilled; failure can be renegotiated, defaulted, breached, cancelled, or
## enforced." "Enforced" is an outcome of breach/default handled by
## whatever enforces it (an institution, once Phase 6 exists), not a status
## of the contract itself.
const PROPOSED := "proposed"
const ACCEPTED := "accepted"
const ACTIVE := "active"
const FULFILLED := "fulfilled"
const BREACHED := "breached"
const DEFAULTED := "defaulted"
const CANCELLED := "cancelled"
const RENEGOTIATED := "renegotiated"
const STATUSES := [
	PROPOSED, ACCEPTED, ACTIVE, FULFILLED, BREACHED, DEFAULTED, CANCELLED, RENEGOTIATED,
]

## Assigned by ContractStore.propose; empty until then.
var id := ""

var type: String
## Entity references (see EntityRef) for whoever is bound by this contract.
var parties: Array[String] = []
## Free-form, roughly one entry per party's own obligation -- what each side
## actually owes.
var obligations: Array[String] = []
## What is being exchanged, as a whole.
var consideration: String
## Tick this contract is due by, or -1.0 for no deadline.
var deadline: float
var status: String
## Tick this contract was proposed at.
var created_at: float


func _init(
	a_type: String, a_parties: Array, a_obligations: Array, a_consideration: String,
	a_deadline: float = -1.0, a_created_at: float = 0.0
) -> void:
	type = a_type
	for party in a_parties:
		parties.append(str(party))
	for obligation in a_obligations:
		obligations.append(str(obligation))
	consideration = a_consideration
	deadline = a_deadline
	created_at = a_created_at
	status = PROPOSED
