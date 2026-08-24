extends RefCounted

## The smallest persistent economic/social unit above an individual (see
## docs/emergence/01-society-and-institutions.md "Households" and
## docs/emergence/03-contracts-property-economy.md "Property").
##
## Deliberately SINGLE-MEMBER for this first slice: no partnership/
## reproduction system exists yet to justify who belongs to whose household
## (see docs/roadmap.md's Emergence Phase 3 note), so inventing multi-member
## families now would be exactly the premature complexity the master brief
## warns against. A single person living alone is still a real household,
## just the smallest possible one -- and HouseholdStore.merge (once written)
## is where two single-member households would become one, whenever a real
## partnership mechanic exists to trigger it.

const EntityRef = preload("res://src/emergence/entity_ref.gd")

## An entity reference (see EntityRef) for every member of this household.
var members: Array[String] = []
## Entity references (see EntityRef) for everything this household owns.
var property: Array[String] = []
## Keyed by its founder's own entity ref -- the same "deterministic key, not
## an allocated ID" idiom EntityRef itself uses, so no new counter has to be
## persisted or protected from collision just to hand out household ids.
var id: String


static func for_founder(founder_id: String) -> RefCounted:
	var household = new()
	household.id = EntityRef.for_kind("household", EntityRef.key_of(founder_id))
	# A bare `[founder_id]` array literal does not type-infer as Array[String]
	# when assigned into a typed field -- the same quirk Rumor.transmit hit
	# (Invalid assignment of property... with value of type 'Array').
	household.members.append(founder_id)
	return household
