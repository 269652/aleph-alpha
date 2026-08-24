extends GutTest

## Household (see docs/emergence/01-society-and-institutions.md "Households"
## and docs/emergence/03-contracts-property-economy.md "Property").
##
## "The smallest persistent economic/social unit above an individual" -- track
## members and property. Deliberately SINGLE-MEMBER for this first slice: no
## partnership/reproduction system exists yet to justify who belongs to whose
## household (see docs/roadmap.md's Emergence Phase 3 note), so inventing
## multi-member families now would be exactly the premature complexity the
## master brief warns against. A single person living alone is still a real
## household, just the smallest possible one.

const Household = preload("res://src/emergence/household.gd")


func test_forming_a_household_names_its_founder_as_a_member():
	var household := Household.for_founder("npc:1")
	assert_eq(household.members, ["npc:1"])


## Keyed by the founder's own entity ref -- the same "deterministic key, not
## an allocated ID" idiom EntityRef itself already uses, so no new ID scheme
## has to be persisted or protected from collision.
func test_the_household_id_is_derived_from_its_founder():
	var household := Household.for_founder("npc:483920")
	assert_eq(household.id, "household:483920")


func test_a_fresh_household_owns_no_property():
	var household := Household.for_founder("npc:1")
	assert_eq(household.property, [])
