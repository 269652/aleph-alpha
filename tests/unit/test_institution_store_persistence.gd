extends GutTest

## InstitutionStorePersistence: pure I/O for the emergence institution store
## -- mirrors EventStorePersistence/.../MarketStorePersistence/PlayerSave's
## role exactly.

const InstitutionStorePersistence = preload("res://src/emergence/institution_store_persistence.gd")
const InstitutionStore = preload("res://src/emergence/institution_store.gd")
const Institution = preload("res://src/emergence/institution.gd")

const TEST_PATH := "user://test_institution_store.bin"

var persistence: InstitutionStorePersistence


func before_each():
	persistence = InstitutionStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := InstitutionStore.new()
	var institution := store.form("guild", ["household:1"], 1.0)

	persistence.save(store, TEST_PATH)
	var restored: InstitutionStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.get_institution(institution.id).type, "guild")
	assert_eq(restored.institutions_for("household:1").size(), 1)


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: InstitutionStore = persistence.load_store(TEST_PATH)
	assert_eq(restored.institutions_for("household:1"), [])


func test_wipe_removes_an_existing_save():
	persistence.save(InstitutionStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
