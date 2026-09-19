extends GutTest

## A household's ESTATE, and the run-lengths the ladder is read against
## (docs/concept/village_estates.md mechanisms 1 and 3).
##
## Standing lives on the Household rather than in a new parallel store, for
## the same reason its wallet and its property do: a Household is this
## project's real persistent unit, and an estate is not derivable from
## anything -- it is HISTORY, the record of a ladder a household actually
## climbed. Persisting it on the household means HouseholdStorePersistence
## carries it with no new file, no new wiring and no second source of truth.

const Household = preload("res://src/emergence/household.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")
const VillageEstates = preload("res://src/emergence/village_estates.gd")


func test_a_new_household_is_founded_at_the_bottom_rung():
	assert_eq(Household.for_founder("npc:1").estate, VillageEstates.STARTING_ESTATE)


func test_a_new_household_has_banked_no_time_at_any_standing():
	var household = Household.for_founder("npc:1")
	assert_eq(household.good_run_days, 0.0)
	assert_eq(household.short_run_days, 0.0)


func test_standing_and_its_runs_survive_a_save_and_a_load():
	var store := HouseholdStore.new()
	var household = store.form_household("npc:1")
	household.estate = "handwerker"
	household.good_run_days = 4.5
	household.short_run_days = 1.25

	var reloaded = HouseholdStore.from_dicts(store.to_dicts())
	var back = reloaded.household_for("npc:1")
	assert_eq(back.estate, "handwerker")
	assert_almost_eq(back.good_run_days, 4.5, 0.0001)
	assert_almost_eq(back.short_run_days, 1.25, 0.0001)


## A save written before estates existed carries no standing at all, and
## must read back as a cottager rather than as an empty string that every
## downstream lookup then fails on.
func test_a_save_from_before_estates_existed_reads_back_as_a_cottager():
	var reloaded = HouseholdStore.from_dicts([
		{"id": "household:1", "members": ["npc:1"], "property": [], "wallet_balance": 7},
	])
	var back = reloaded.household_for("npc:1")
	assert_eq(back.estate, VillageEstates.STARTING_ESTATE)
	assert_eq(back.good_run_days, 0.0)
	assert_eq(back.wallet.balance, 7, "the rest of the household did not survive the migration")


## An estate census over real households is what every estate mechanism is
## fed, so the store answers it directly rather than every caller counting
## by hand.
func test_the_store_counts_a_settlements_households_by_estate():
	var store := HouseholdStore.new()
	store.form_household("npc:1").estate = "bauer"
	store.form_household("npc:2").estate = "bauer"
	store.form_household("npc:3").estate = "buerger"
	var ids := ["household:npc:1", "household:npc:2", "household:npc:3"]
	var census: Dictionary = store.estate_census(store.household_ids_of_members(["npc:1", "npc:2", "npc:3"]))
	assert_eq(int(census.get("bauer", 0)), 2)
	assert_eq(int(census.get("buerger", 0)), 1)
	assert_false(census.has("kossaet"), "a village with no cottagers counted some")


func test_an_empty_roster_is_an_empty_census():
	assert_eq(HouseholdStore.new().estate_census([]), {})


func test_a_household_id_the_store_never_heard_of_counts_as_nobody():
	assert_eq(HouseholdStore.new().estate_census(["household:ghost"]), {})
