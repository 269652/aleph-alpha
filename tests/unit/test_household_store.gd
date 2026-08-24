extends GutTest

## HouseholdStore: the collection of Households and what they own (see
## docs/emergence/03-contracts-property-economy.md "Property": "Property is
## an ownership relationship... Owners may be individuals, households,
## institutions, or governments").

const HouseholdStore = preload("res://src/emergence/household_store.gd")

var store: HouseholdStore


func before_each():
	store = HouseholdStore.new()


# -- forming households -------------------------------------------------------

func test_forming_a_household_registers_its_founder_as_a_member():
	var household := store.form_household("npc:1")
	assert_eq(household.members, ["npc:1"])


## Idempotent -- asking twice for the same founder returns the SAME
## household, not a duplicate. A villager does not get a second household
## just because something asked twice (the same reasoning EventStore's own
## founding-event dedupe already uses).
func test_forming_a_household_twice_for_the_same_founder_returns_the_same_one():
	var first := store.form_household("npc:1")
	var second := store.form_household("npc:1")
	assert_eq(first.id, second.id)


func test_household_for_finds_it_by_member():
	store.form_household("npc:1")
	var household := store.household_for("npc:1")
	assert_not_null(household)
	assert_eq(household.members, ["npc:1"])


func test_household_for_an_unknown_entity_is_null():
	assert_null(store.household_for("npc:999"))


func test_get_household_finds_it_by_its_own_id():
	var formed := store.form_household("npc:1")
	var found: RefCounted = store.get_household(formed.id)
	assert_not_null(found)
	assert_eq(found.id, formed.id)


func test_get_household_for_an_unknown_id_is_null():
	assert_null(store.get_household("household:999"))


# -- property ---------------------------------------------------------------

func test_granting_property_adds_it_to_the_households_own_list():
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")
	assert_eq(store.household_for("npc:1").property, ["house:0_0_0"])


func test_owner_of_finds_who_owns_a_property():
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")
	assert_eq(store.owner_of("house:0_0_0"), household.id)


func test_unowned_property_has_no_owner():
	assert_eq(store.owner_of("house:0_0_0"), "")


## Property has at most one owner at a time -- granting it to a new
## household TRANSFERS it, removing it from the previous owner's list rather
## than letting two households both claim the same house.
func test_granting_already_owned_property_to_a_new_household_transfers_it():
	var first := store.form_household("npc:1")
	var second := store.form_household("npc:2")
	store.grant_property(first.id, "house:0_0_0")
	store.grant_property(second.id, "house:0_0_0")

	assert_eq(store.owner_of("house:0_0_0"), second.id)
	assert_eq(store.household_for("npc:1").property, [])
	assert_eq(store.household_for("npc:2").property, ["house:0_0_0"])


## Granting the SAME property to its current owner again is a harmless no-op,
## not a duplicate entry in that household's property list.
func test_regranting_property_to_its_current_owner_does_not_duplicate_it():
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")
	store.grant_property(household.id, "house:0_0_0")
	assert_eq(store.household_for("npc:1").property, ["house:0_0_0"])


# -- persistence round trip (pure, no FileAccess) -----------------------------

func test_to_dicts_and_from_dicts_round_trip_a_whole_store():
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")

	var restored := HouseholdStore.from_dicts(store.to_dicts())

	assert_eq(restored.household_for("npc:1").property, ["house:0_0_0"])
	assert_eq(restored.owner_of("house:0_0_0"), household.id)
