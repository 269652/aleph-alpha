extends GutTest

## VillageCensus: docs/concept/village_growth.md's own bookkeeping -- who in
## this settlement actually has a roof, how much spare capacity stands, and
## which households are still waiting for one. Pure: real household ids, the
## real building records EarthChunkManager.buildings_in_chunk returns, and
## the real HouseholdStore ownership index go in; no world state is touched.

const VillageCensus = preload("res://src/emergence/village_census.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")

const _CHUNK := Vector2i(3, -4)


func _record(building_id: String, origin: Vector2i) -> Dictionary:
	return {"id": building_id, "origin_local": origin, "chunk_coord": _CHUNK}


## Grants the house at `origin` to a fresh household for `founder_id`,
## through the SAME ConstructionProject.property_id scheme the real
## completion path uses -- so this test cannot pass against a census that
## invented its own id shape.
func _house_owned_by(store, founder_id: String, origin: Vector2i) -> String:
	var household = store.form_household(founder_id)
	store.grant_property(household.id, ConstructionProject.for_site(_CHUNK, origin, "house_small", household.id).property_id())
	return household.id


func test_an_empty_settlement_has_nobody_housed_and_nobody_waiting():
	var census: Dictionary = VillageCensus.of([], [], HouseholdStore.new())
	assert_eq(census["housed_count"], 0)
	assert_eq(census["spare_house_capacity"], 0)
	assert_eq(census["unhoused_household_ids"], [] as Array[String])


## A household that has LEFT the settlement still owns the house it built:
## EarthChunkManager._record_household_departure appends an event and
## touches nothing else -- no roof is released, no villager goes anywhere.
## So the census met roofs whose owners were not on the roster it was
## handed, and counted them among "ours" anyway. Reported live off the
## settlement card: *"Population 1 (10 housed)"*, which is impossible on
## its face -- you cannot have ten of one household under roofs.
##
## It is not cosmetic. `housed_count >= household_count` tells
## VillageGrowth.next_building there is nobody left to house, and
## `spare_house_capacity = capacity - housed_count` tells
## VillageImmigration there is no room to take anybody in. A village with
## ghost owners can therefore never raise another house NOR accept a
## newcomer, and its population can only fall -- reported in the same
## breath: *"The villages population is declining"*.
##
## VillageAssembly names the contract this breaks in its own argument
## list: "housed_count -- how many of THEM have a roof".
func test_a_roof_owned_by_somebody_who_has_left_is_not_counted_as_ours():
	var store = HouseholdStore.new()
	var ours := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	# Departed: still owns its house, no longer on the settlement's roster.
	_house_owned_by(store, EntityRef.for_npc(2), Vector2i(8, 8))

	var census: Dictionary = VillageCensus.of(
		[ours],
		[_record("house_small", Vector2i(4, 4)), _record("house_small", Vector2i(8, 8))],
		store
	)
	assert_eq(census["housed_count"], 1, "a household that left was counted among ours")


## Never more of us under roofs than there are of us. The invariant the
## card's own line reads as, stated directly so no future owner lookup can
## break it quietly.
func test_no_more_households_are_housed_than_there_are_households():
	var store = HouseholdStore.new()
	var ours := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	var records: Array = [_record("house_small", Vector2i(4, 4))]
	for i in range(2, 12):
		_house_owned_by(store, EntityRef.for_npc(i), Vector2i(i * 2, i * 2))
		records.append(_record("house_small", Vector2i(i * 2, i * 2)))

	var census: Dictionary = VillageCensus.of([ours], records, store)
	assert_lte(int(census["housed_count"]), 1, "more roofs than households were counted as ours")


## ...and the roof they left behind is room the village may count on
## again, which is what lets it take somebody in rather than freezing.
func test_a_roof_whose_owner_has_left_is_room_the_village_still_has():
	var store = HouseholdStore.new()
	var ours := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	_house_owned_by(store, EntityRef.for_npc(2), Vector2i(8, 8))

	var census: Dictionary = VillageCensus.of(
		[ours],
		[_record("house_small", Vector2i(4, 4)), _record("house_small", Vector2i(8, 8))],
		store
	)
	assert_gt(int(census["spare_house_capacity"]), 0, "the village had no room and could never grow again")


func test_a_household_owning_a_real_house_here_counts_as_housed():
	var store = HouseholdStore.new()
	var housed := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	var census: Dictionary = VillageCensus.of([housed], [_record("house_small", Vector2i(4, 4))], store)
	assert_eq(census["housed_count"], 1)
	assert_eq(census["unhoused_household_ids"], [] as Array[String])


func test_a_household_with_no_house_is_named_as_waiting():
	var store = HouseholdStore.new()
	var housed := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	var waiting = store.form_household(EntityRef.for_npc(2))
	var census: Dictionary = VillageCensus.of(
		[housed, waiting.id], [_record("house_small", Vector2i(4, 4))], store
	)
	assert_eq(census["housed_count"], 1)
	assert_eq(census["unhoused_household_ids"], [waiting.id] as Array[String])


## Unhoused ids come back in a stable order so the same household is
## credited with the same plot on every repeated decision, rather than the
## village queuing a second house somewhere else next tick.
func test_the_waiting_list_is_deterministically_ordered():
	var store = HouseholdStore.new()
	var ids: Array[String] = []
	for seed_value in [903, 101, 557]:
		ids.append(store.form_household(EntityRef.for_npc(seed_value)).id)
	var first: Dictionary = VillageCensus.of(ids, [], store)
	ids.reverse()
	var second: Dictionary = VillageCensus.of(ids, [], store)
	assert_eq(first["unhoused_household_ids"], second["unhoused_household_ids"])
	assert_eq(first["unhoused_household_ids"].size(), 3)


## A house standing empty is real spare room -- exactly what immigration
## reads when it asks whether the village can take anyone in.
func test_spare_capacity_is_the_room_that_stands_beyond_the_people_in_it():
	var store = HouseholdStore.new()
	var housed := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	var census: Dictionary = VillageCensus.of(
		[housed], [_record("house_large", Vector2i(4, 4)), _record("house_small", Vector2i(9, 9))], store
	)
	# house_large (3) + house_small (1) = 4 capacity, one single-member
	# household living in it.
	assert_eq(census["house_capacity"], 4)
	assert_eq(census["spare_house_capacity"], 3)


func test_a_civic_or_production_building_is_never_counted_as_housing():
	var census: Dictionary = VillageCensus.of(
		[], [_record("city_hall", Vector2i(4, 4)), _record("sawmill", Vector2i(9, 9))], HouseholdStore.new()
	)
	assert_eq(census["house_capacity"], 0, "nobody lives in a hall or a mill")


## A house standing with no owner is a roof waiting for someone -- which is
## exactly what lets a village take a household in before it has built
## anything new, and what stops five homeless households reading as five
## housed ones just because one house stands.
func test_a_house_nobody_owns_yet_is_real_spare_room_and_houses_nobody():
	var store = HouseholdStore.new()
	var ids: Array[String] = []
	for i in 5:
		ids.append(store.form_household(EntityRef.for_npc(i)).id)
	var census: Dictionary = VillageCensus.of(ids, [_record("house_small", Vector2i(4, 4))], store)
	assert_eq(census["spare_house_capacity"], 1, "an empty house is a roof waiting for someone")
	assert_eq(census["housed_count"], 0, "an unowned house shelters nobody")
	assert_eq(census["unhoused_household_ids"].size(), 5)


## Defensive, and stated rather than assumed: every caller multiplies or
## compares against this, so it is never allowed below zero whatever the
## records say.
func test_spare_capacity_is_never_negative():
	var store = HouseholdStore.new()
	var ids: Array[String] = []
	for i in 4:
		ids.append(_house_owned_by(store, EntityRef.for_npc(i), Vector2i(i * 5, 4)))
	# Only ONE of the four owned houses still stands here (the rest razed,
	# or sited in a neighbouring chunk) -- four owners, one roof's capacity.
	var census: Dictionary = VillageCensus.of(ids, [_record("house_small", Vector2i(0, 4))], store)
	assert_gte(census["spare_house_capacity"], 0)


## Which house a household lives in, for the readout that has to name it.
func test_the_house_a_household_owns_can_be_looked_up_by_its_site():
	var store = HouseholdStore.new()
	var housed := _house_owned_by(store, EntityRef.for_npc(1), Vector2i(4, 4))
	assert_eq(VillageCensus.household_owning(_CHUNK, Vector2i(4, 4), store), housed)
	assert_eq(VillageCensus.household_owning(_CHUNK, Vector2i(9, 9), store), "", "nobody owns an empty plot")
