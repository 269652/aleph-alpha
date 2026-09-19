extends RefCounted

## A persistent organization (see
## docs/emergence/01-society-and-institutions.md "Institutions": "a
## persistent organization with membership, shared purpose, leadership,
## resources, assets, rules, reputation, obligations, external
## relationships, territory/influence, and historical memory").
##
## Deliberately does NOT duplicate factions.md's aggregate-reputation model
## (see docs/roadmap.md's Emergence Phase 6 note) -- an institution is a new
## organizational ENTITY with its own membership, existing alongside
## factions.md's reputation, which stays a PROJECTION over individual
## relationships, not something an institution overrides or replaces.

## The documented "start with" roster (docs/emergence/07-implementation-
## roadmap.md Phase 6).
const TYPES := ["guild", "cooperative", "militia", "merchant_company", "criminal_group"]

const ACTIVE := "active"
const DISSOLVED := "dissolved"
const STATUSES := [ACTIVE, DISSOLVED]

## Assigned by InstitutionStore.form; empty until then.
var id := ""

var type: String
var members: Array[String] = []
## Entity reference of the current leader, or "" if none -- "Informal
## leaders can precede formal leadership" (docs/emergence/01), and there is
## no trust/reputation/social-centrality data yet to pick one from, so this
## is never auto-assigned.
var leader := ""
var goals: Array[String] = []
var status: String
var created_at: float

## docs/concept/village_estates.md's guild chest (Zunftkasse): `item_id ->
## units` this institution is holding in relief for its own members.
##
## Lives here rather than in a second parallel store for the same reason a
## household's estate lives on the Household: an Institution is this
## project's persistent unit for a body of people, so
## InstitutionStorePersistence carries the chest with no new file and no
## second source of truth. Empty for every institution that is not a guild,
## and for a guild that has never had a surplus to set aside.
var chest: Dictionary = {}


func _init(a_type: String, a_members: Array, a_created_at: float) -> void:
	type = a_type
	for member in a_members:
		members.append(str(member))
	created_at = a_created_at
	status = ACTIVE
