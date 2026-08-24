extends GutTest

## ContractStore: proposes and drives contracts through their lifecycle (see
## docs/emergence/03-contracts-property-economy.md "Contracts": "proposed ->
## accepted -> active -> fulfilled; failure can be renegotiated, defaulted,
## breached, cancelled, or enforced").
##
## Same shape as EventStore/MemoryStore/HouseholdStore: a plain RefCounted
## collection, no engine dependency, its own to_dicts/from_dicts.

const Contract = preload("res://src/emergence/contract.gd")
const ContractStore = preload("res://src/emergence/contract_store.gd")

var store: ContractStore


func before_each():
	store = ContractStore.new()


func _propose() -> Contract:
	return store.propose("rent", ["household:1", "household:2"], ["10 wood/week"], "shelter", -1.0, 1.0)


# -- proposing ------------------------------------------------------------

func test_propose_assigns_a_deterministic_sortable_id():
	var contract := store.propose("rent", ["household:1"], [], "", -1.0, 1.0)
	assert_eq(contract.id, "con_0_rent")


func test_a_second_proposal_gets_the_next_ordinal():
	store.propose("rent", ["household:1"], [], "", -1.0, 1.0)
	var second := store.propose("loan", ["household:2"], [], "", -1.0, 1.0)
	assert_eq(second.id, "con_1_loan")


func test_get_contract_returns_the_proposed_contract():
	var contract := _propose()
	assert_eq(store.get_contract(contract.id).id, contract.id)


func test_contracts_for_finds_every_contract_a_party_is_in():
	var contract := _propose()
	assert_eq(store.contracts_for("household:1").size(), 1)
	assert_eq(store.contracts_for("household:1")[0].id, contract.id)
	assert_eq(store.contracts_for("household:2").size(), 1)


func test_contracts_for_an_uninvolved_entity_is_empty():
	_propose()
	assert_eq(store.contracts_for("household:999"), [])


# -- the happy path: proposed -> accepted -> active -> fulfilled -------------

func test_accept_moves_a_proposed_contract_to_accepted():
	var contract := _propose()
	assert_true(store.accept(contract.id, 2.0))
	assert_eq(store.get_contract(contract.id).status, Contract.ACCEPTED)


func test_activate_moves_an_accepted_contract_to_active():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	assert_true(store.activate(contract.id, 3.0))
	assert_eq(store.get_contract(contract.id).status, Contract.ACTIVE)


func test_fulfill_moves_an_active_contract_to_fulfilled():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	store.activate(contract.id, 3.0)
	assert_true(store.fulfill(contract.id, 4.0))
	assert_eq(store.get_contract(contract.id).status, Contract.FULFILLED)


# -- failure paths, only reachable from ACTIVE --------------------------------

func test_breach_moves_an_active_contract_to_breached():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	store.activate(contract.id, 3.0)
	assert_true(store.breach(contract.id, 4.0))
	assert_eq(store.get_contract(contract.id).status, Contract.BREACHED)


func test_default_on_moves_an_active_contract_to_defaulted():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	store.activate(contract.id, 3.0)
	assert_true(store.default_on(contract.id, 4.0))
	assert_eq(store.get_contract(contract.id).status, Contract.DEFAULTED)


## Cancellation is the pre-activation exit -- proposed or accepted, not once
## a contract is already under way.
func test_cancel_moves_a_proposed_contract_to_cancelled():
	var contract := _propose()
	assert_true(store.cancel(contract.id, 2.0))
	assert_eq(store.get_contract(contract.id).status, Contract.CANCELLED)


func test_cancel_moves_an_accepted_contract_to_cancelled():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	assert_true(store.cancel(contract.id, 3.0))
	assert_eq(store.get_contract(contract.id).status, Contract.CANCELLED)


# -- invalid transitions are refused, not silently allowed --------------------

func test_cannot_activate_a_contract_that_was_never_accepted():
	var contract := _propose()
	assert_false(store.activate(contract.id, 2.0))
	assert_eq(store.get_contract(contract.id).status, Contract.PROPOSED)


func test_cannot_fulfill_a_contract_that_is_not_active():
	var contract := _propose()
	assert_false(store.fulfill(contract.id, 2.0))


func test_cannot_breach_a_contract_that_is_not_active():
	var contract := _propose()
	assert_false(store.breach(contract.id, 2.0))


func test_cannot_cancel_a_contract_that_is_already_active():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	store.activate(contract.id, 3.0)
	assert_false(store.cancel(contract.id, 4.0))
	assert_eq(store.get_contract(contract.id).status, Contract.ACTIVE)


## A terminal contract stays exactly where it is -- fulfilled is fulfilled,
## it does not get re-fulfilled or re-breached.
func test_a_fulfilled_contract_cannot_transition_further():
	var contract := _propose()
	store.accept(contract.id, 2.0)
	store.activate(contract.id, 3.0)
	store.fulfill(contract.id, 4.0)
	assert_false(store.breach(contract.id, 5.0))
	assert_eq(store.get_contract(contract.id).status, Contract.FULFILLED)


func test_acting_on_an_unknown_contract_id_is_refused_not_an_error():
	assert_false(store.accept("con_999_nothing", 1.0))


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var contract := _propose()
	store.accept(contract.id, 2.0)

	var restored := ContractStore.from_dicts(store.to_dicts())

	assert_eq(restored.get_contract(contract.id).status, Contract.ACCEPTED)
	assert_eq(restored.contracts_for("household:1").size(), 1)


func test_a_restored_store_continues_the_id_sequence():
	_propose()
	var restored := ContractStore.from_dicts(store.to_dicts())
	var new_contract: Contract = restored.propose("loan", ["household:3"], [], "", -1.0, 5.0)
	assert_eq(new_contract.id, "con_1_loan")
