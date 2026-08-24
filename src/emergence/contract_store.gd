extends RefCounted

## Proposes and drives contracts through their lifecycle (see
## docs/emergence/03-contracts-property-economy.md "Contracts": "proposed ->
## accepted -> active -> fulfilled; failure can be renegotiated, defaulted,
## breached, cancelled, or enforced").
##
## Same shape as EventStore/MemoryStore/HouseholdStore: a plain RefCounted
## collection, no engine dependency, own to_dicts/from_dicts for
## ContractStorePersistence to wrap. Deliberately does NOT depend on
## EventStore itself -- the caller (EarthChunkManager, the same coordinator
## record_settlement_founded_if_new already is) is responsible for also
## recording a contract transition as a real event, the same
## caller-coordinates shape MemoryStore/HouseholdStore already use rather
## than each store reaching sideways into another.

const Contract = preload("res://src/emergence/contract.gd")

var _contracts: Dictionary = {}     # id -> Contract
var _order: Array[String] = []      # insertion order
var _by_party: Dictionary = {}      # entity_id -> Array[String] (contract ids)
var _next_ordinal := 0


## Proposes a new contract -- always starts PROPOSED, whatever status a
## caller might have set on the Contract object before this (there is no
## such caller here; Contract._init always starts PROPOSED itself, this is
## just the single point where that is also guaranteed by the store).
func propose(
	type: String, parties: Array, obligations: Array, consideration: String,
	deadline: float, tick: float
) -> Contract:
	var contract := Contract.new(type, parties, obligations, consideration, deadline, tick)
	var id := "con_%d_%s" % [_next_ordinal, type]
	_next_ordinal += 1
	contract.id = id
	_contracts[id] = contract
	_order.append(id)
	for party in contract.parties:
		if not _by_party.has(party):
			_by_party[party] = []
		_by_party[party].append(id)
	return contract


func get_contract(contract_id: String) -> Contract:
	return _contracts.get(contract_id)


func contracts_for(entity_id: String) -> Array[Contract]:
	var out: Array[Contract] = []
	for id in _by_party.get(entity_id, []):
		out.append(_contracts[id])
	return out


func accept(contract_id: String, _tick: float) -> bool:
	return _transition(contract_id, Contract.PROPOSED, Contract.ACCEPTED)


func activate(contract_id: String, _tick: float) -> bool:
	return _transition(contract_id, Contract.ACCEPTED, Contract.ACTIVE)


func fulfill(contract_id: String, _tick: float) -> bool:
	return _transition(contract_id, Contract.ACTIVE, Contract.FULFILLED)


func breach(contract_id: String, _tick: float) -> bool:
	return _transition(contract_id, Contract.ACTIVE, Contract.BREACHED)


func default_on(contract_id: String, _tick: float) -> bool:
	return _transition(contract_id, Contract.ACTIVE, Contract.DEFAULTED)


## Cancellation is the pre-activation exit -- proposed or accepted, not once
## a contract is already under way (that is breach/default's territory).
func cancel(contract_id: String, _tick: float) -> bool:
	var contract: Contract = _contracts.get(contract_id)
	if contract == null:
		return false
	if contract.status != Contract.PROPOSED and contract.status != Contract.ACCEPTED:
		return false
	contract.status = Contract.CANCELLED
	return true


func _transition(contract_id: String, from_status: String, to_status: String) -> bool:
	var contract: Contract = _contracts.get(contract_id)
	if contract == null:
		return false
	if contract.status != from_status:
		return false
	contract.status = to_status
	return true


## For ContractStorePersistence -- pure serialization, no FileAccess (same
## split EventStore/EventStorePersistence already use).
func to_dicts() -> Array:
	var out: Array = []
	for id in _order:
		var contract: Contract = _contracts[id]
		out.append({
			"id": contract.id,
			"type": contract.type,
			"parties": contract.parties,
			"obligations": contract.obligations,
			"consideration": contract.consideration,
			"deadline": contract.deadline,
			"status": contract.status,
			"created_at": contract.created_at,
		})
	return out


## Rebuilds a store from to_dicts()' output, re-deriving the party index and
## ordinal counter from the contracts themselves -- one source of truth,
## same reasoning as EventStore.from_dicts.
static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	var highest_ordinal := -1
	for d in dicts:
		var contract := Contract.new(
			d.get("type", ""), d.get("parties", []), d.get("obligations", []),
			d.get("consideration", ""), d.get("deadline", -1.0), d.get("created_at", 0.0)
		)
		contract.id = d.get("id", "")
		contract.status = d.get("status", Contract.PROPOSED)

		store._contracts[contract.id] = contract
		store._order.append(contract.id)
		for party in contract.parties:
			if not store._by_party.has(party):
				store._by_party[party] = []
			store._by_party[party].append(contract.id)

		var ordinal := _ordinal_of(contract.id)
		if ordinal > highest_ordinal:
			highest_ordinal = ordinal
	store._next_ordinal = highest_ordinal + 1
	return store


## "con_<ordinal>_<type>" -> ordinal, same convention EventStore._ordinal_of
## already established.
static func _ordinal_of(contract_id: String) -> int:
	var parts := contract_id.split("_", true, 2)
	if parts.size() < 2:
		return -1
	return int(parts[1])
