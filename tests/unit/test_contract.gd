extends GutTest

## Contract (see docs/emergence/03-contracts-property-economy.md "Contracts":
## "Contract { parties[], obligations[], consideration[], deadline,
## enforcement, status }"). Pure data -- ContractStore owns assigning `id`
## and driving status transitions, the same split Event/EventStore already
## use.

const Contract = preload("res://src/emergence/contract.gd")


func test_carries_its_type_parties_and_terms():
	var contract := Contract.new(
		"rent", ["household:1", "household:2"], ["10 wood/week"], "use of the east field", 100.0
	)
	assert_eq(contract.type, "rent")
	assert_eq(contract.parties, ["household:1", "household:2"])
	assert_eq(contract.obligations, ["10 wood/week"])
	assert_eq(contract.consideration, "use of the east field")
	assert_eq(contract.deadline, 100.0)


func test_starts_proposed():
	var contract := Contract.new("rent", ["household:1"], [], "", -1.0)
	assert_eq(contract.status, Contract.PROPOSED)


func test_a_deadline_defaults_to_none():
	var contract := Contract.new("rent", ["household:1"], [], "")
	assert_eq(contract.deadline, -1.0)


func test_every_documented_status_exists():
	var expected := [
		"proposed", "accepted", "active", "fulfilled",
		"breached", "defaulted", "cancelled", "renegotiated",
	]
	for status in expected:
		assert_true(Contract.STATUSES.has(status), "missing documented status: %s" % status)
