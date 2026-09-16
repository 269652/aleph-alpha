extends RefCounted

## docs/concept/village_growth.md's own bookkeeping: who in this settlement
## actually has a roof, how much spare room stands, and which households are
## still waiting for one.
##
## Both the growth ladder and immigration ask this. The ladder needs
## `housed_count` (an unhoused household outranks every other rung) and the
## first waiting household to credit a new house's ownership to;
## immigration needs `spare_house_capacity` (a village with no spare roof
## and nowhere left to build takes nobody in).
##
## Housing is resolved through the SAME ConstructionProject.property_id
## scheme village and player houses already share -- a house's property id
## is a pure function of its SITE, so "who lives here" is answered by
## deriving the id from the building record's own chunk/origin and asking
## HouseholdStore who owns it. Nothing new is persisted and no second
## residency index is introduced that could drift from the ownership one.
##
## Pure and static, explicit dependencies in, no stored state -- the same
## shape SettlementSpareCapacity/SettlementTier/VillageGrowth already use.

const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")


## `household_ids`: the settlement's real households (EarthChunkManager.
## _households_in_settlement). `building_records`: what really stands here
## (EarthChunkManager.buildings_in_chunk -- each carrying `id`,
## `origin_local` and `chunk_coord`). `household_store`: the real
## HouseholdStore.
##
## Returns `{housed_count, house_capacity, spare_house_capacity,
## unhoused_household_ids}`. `unhoused_household_ids` is SORTED, so a
## repeated decision credits the same household with the same plot rather
## than the village queuing a second house somewhere else next tick.
static func of(household_ids: Array, building_records: Array, household_store) -> Dictionary:
	var capacity := 0
	var housed := {}
	for record in building_records:
		var building_id: String = record.get("id", "")
		var building_capacity := BuildingCatalog.capacity_of(building_id)
		if building_capacity <= 0:
			continue  # nobody lives in a hall, a mill or a brewery
		capacity += building_capacity
		var owner: String = household_owning(
			record.get("chunk_coord", Vector2i.ZERO), record.get("origin_local", Vector2i.ZERO), household_store
		)
		if owner != "":
			housed[owner] = true

	var unhoused: Array[String] = []
	for household_id in household_ids:
		if not housed.has(household_id):
			unhoused.append(household_id)
	unhoused.sort()

	# Everyone housed occupies one place in the roof they own. Single-member
	# households are all this substrate has (see Household's own doc
	# comment), so "how many people are already under a roof" is exactly
	# how many households are.
	var housed_count: int = housed.size()
	return {
		"housed_count": housed_count,
		"house_capacity": capacity,
		"spare_house_capacity": maxi(capacity - housed_count, 0),
		"unhoused_household_ids": unhoused,
	}


## Which household owns the building standing at this site, or "" -- the
## readout's own "whose house is this" lookup, and the one this module's
## own housing count is built on. Derives the property id from the site
## exactly as ConstructionProject does, so a house granted by the real
## completion path and one asked about here can never disagree.
static func household_owning(chunk_coord: Vector2i, origin_local: Vector2i, household_store) -> String:
	var property_id: String = ConstructionProject.for_site(chunk_coord, origin_local, "", "").property_id()
	return household_store.owner_of(property_id)
