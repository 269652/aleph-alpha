extends RefCounted

## The collection of Households and what they own (see
## docs/emergence/03-contracts-property-economy.md "Property": "Property is
## an ownership relationship... Owners may be individuals, households,
## institutions, or governments").
##
## Same shape as EventStore/MemoryStore: a plain RefCounted collection, no
## engine dependency, its own to_dicts/from_dicts for HouseholdStorePersistence
## to wrap.

const Household = preload("res://src/emergence/household.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")

var _households: Dictionary = {}   # id -> Household
var _by_member: Dictionary = {}    # entity_id -> household_id
var _owner_of: Dictionary = {}     # property_id -> household_id


## A household for `founder_id`, forming a fresh single-member one if this is
## the first time this entity has been asked about -- idempotent, so a
## villager does not get a second household just because something asked
## twice.
func form_household(founder_id: String) -> Household:
	if _by_member.has(founder_id):
		return _households[_by_member[founder_id]]
	var household: Household = Household.for_founder(founder_id)
	_households[household.id] = household
	_by_member[founder_id] = household.id
	return household


func household_for(entity_id: String) -> Household:
	if not _by_member.has(entity_id):
		return null
	return _households[_by_member[entity_id]]


## Looks a household up by its OWN id, as opposed to household_for's lookup
## by member -- the same "get_X by X's own id" accessor ContractStore.
## get_contract/InstitutionStore.get_institution already provide, needed
## here so a caller holding only a household id (e.g. one read back out of
## _households_in_settlement) can resolve it without also holding one of its
## members' entity ids.
func get_household(household_id: String) -> Household:
	return _households.get(household_id)


## Grants `property_id` to `household_id`, TRANSFERRING it away from whoever
## owned it before -- property has at most one owner at a time, the same
## real-world invariant a title deed enforces. Re-granting to the same owner
## it already has is a harmless no-op, not a duplicate list entry.
func grant_property(household_id: String, property_id: String) -> void:
	var previous_owner: String = _owner_of.get(property_id, "")
	if previous_owner == household_id:
		return
	if previous_owner != "" and _households.has(previous_owner):
		_households[previous_owner].property.erase(property_id)

	_owner_of[property_id] = household_id
	if _households.has(household_id):
		_households[household_id].property.append(property_id)


func owner_of(property_id: String) -> String:
	return _owner_of.get(property_id, "")


## The household ids these members belong to, each once, in the order the
## members were given. A member the store has never heard of is skipped --
## an entity with no household is not an error, it is somebody who has not
## settled anywhere.
func household_ids_of_members(member_ids: Array) -> Array:
	var ids: Array = []
	for member_id in member_ids:
		var household_id: String = _by_member.get(member_id, "")
		if household_id != "" and not ids.has(household_id):
			ids.append(household_id)
	return ids


## `{estate -> households}` over the given household ids -- the ONE input
## every estate mechanism is fed (EstateConsumption.demand_for,
## VillageLabor.supply_for, VillageAssembly.next_building). Answered here
## rather than by each caller counting by hand, so there is one reading of
## a settlement's standing rather than three that could disagree.
##
## An id the store has never heard of counts as nobody, which is the right
## answer for a roster read back out of an event graph that has outrun the
## household file.
func estate_census(household_ids: Array) -> Dictionary:
	var census := {}
	for household_id in household_ids:
		var household: Household = _households.get(household_id)
		if household == null:
			continue
		census[household.estate] = int(census.get(household.estate, 0)) + 1
	return census


## For HouseholdStorePersistence -- pure serialization, no FileAccess (same
## split EventStore/EventStorePersistence already use).
func to_dicts() -> Array:
	var out: Array = []
	for id in _households:
		var household: Household = _households[id]
		out.append({
			"id": household.id,
			"members": household.members,
			"property": household.property,
			"wallet_balance": household.wallet.balance,
			"estate": household.estate,
			"good_run_days": household.good_run_days,
			"short_run_days": household.short_run_days,
		})
	return out


## Rebuilds a store from to_dicts()' output, re-deriving the member and
## property indexes from the households themselves rather than persisting
## them separately -- one source of truth, same reasoning as
## EventStore.from_dicts.
static func from_dicts(dicts: Array) -> RefCounted:
	var store = new()
	for d in dicts:
		var household: Household = Household.new()
		household.id = d.get("id", "")
		for member in d.get("members", []):
			household.members.append(str(member))
		for property_id in d.get("property", []):
			household.property.append(str(property_id))
		household.wallet.add(int(d.get("wallet_balance", 0)))
		# A save written before estates existed carries no standing at all.
		# It reads back as a cottager rather than as an empty string every
		# downstream lookup then quietly fails on -- the same migration
		# default Household.for_founder itself applies.
		household.estate = str(d.get("estate", VillageEstates.STARTING_ESTATE))
		household.good_run_days = float(d.get("good_run_days", 0.0))
		household.short_run_days = float(d.get("short_run_days", 0.0))

		store._households[household.id] = household
		for member in household.members:
			store._by_member[member] = household.id
		for property_id in household.property:
			store._owner_of[property_id] = household.id
	return store
