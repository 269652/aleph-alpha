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
const Wallet = preload("res://src/gameplay/wallet.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")

## An entity reference (see EntityRef) for every member of this household.
var members: Array[String] = []
## Entity references (see EntityRef) for everything this household owns.
var property: Array[String] = []
## Real gold this household holds -- the SAME Wallet class Player/NpcEconomy
## already use, not a second currency type (see docs/concept/workforce.md's
## "Wages: the player pays for a filled slot" section). Lives here, not on
## an ephemeral per-frame NpcEconomy/NpcMarker instance, because a
## Household is this project's real, persistent-in-HouseholdStore unit --
## the same reason property lives here rather than on a live node.
var wallet := Wallet.new()
## Keyed by its founder's own entity ref -- the same "deterministic key, not
## an allocated ID" idiom EntityRef itself uses, so no new counter has to be
## persisted or protected from collision just to hand out household ids.
var id: String

## This household's STANDING (docs/concept/village_estates.md mechanism 1):
## which of VillageEstates.ESTATE_IDS it holds, and therefore which house
## it lives in, which class of labour it supplies, what basket it consumes
## and what tax it pays.
##
## Lives here rather than in a second parallel store for the same reason
## the wallet and the property list do: a Household is this project's real
## persistent unit, and an estate is not derivable from anything else --
## it is HISTORY, the record of a ladder this household actually climbed.
## Putting it here means HouseholdStorePersistence carries it with no new
## file and no second source of truth.
##
## Every household is founded at the bottom rung; everything above it is
## earned through EstateAscension's charter gate, never granted.
var estate := VillageEstates.STARTING_ESTATE

## Consecutive days this household has held its standard (fed, and at or
## above its station) -- the run EstateAscension reads before letting it
## rise. Cleared the moment either half lapses.
var good_run_days := 0.0
## Consecutive days it has been below EstateAscension.SUBSISTENCE_FLOOR --
## the run read before it loses standing, or leaves.
var short_run_days := 0.0


static func for_founder(founder_id: String) -> RefCounted:
	var household = new()
	household.id = EntityRef.for_kind("household", EntityRef.key_of(founder_id))
	# A bare `[founder_id]` array literal does not type-infer as Array[String]
	# when assigned into a typed field -- the same quirk Rumor.transmit hit
	# (Invalid assignment of property... with value of type 'Array').
	household.members.append(founder_id)
	return household
