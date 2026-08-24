extends GutTest

## HouseholdStorePersistence: pure I/O for the emergence household store --
## mirrors EventStorePersistence/MemoryStorePersistence/PlayerSave's role
## exactly.

const HouseholdStorePersistence = preload("res://src/emergence/household_store_persistence.gd")
const HouseholdStore = preload("res://src/emergence/household_store.gd")

const TEST_PATH := "user://test_household_store.bin"

var persistence: HouseholdStorePersistence


func before_each():
	persistence = HouseholdStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := HouseholdStore.new()
	var household := store.form_household("npc:1")
	store.grant_property(household.id, "house:0_0_0")

	persistence.save(store, TEST_PATH)
	var restored: HouseholdStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.household_for("npc:1").property, ["house:0_0_0"])
	assert_eq(restored.owner_of("house:0_0_0"), household.id)


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: HouseholdStore = persistence.load_store(TEST_PATH)
	assert_null(restored.household_for("npc:1"))


func test_wipe_removes_an_existing_save():
	persistence.save(HouseholdStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
