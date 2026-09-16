extends GutTest

## ConstructionProjectStorePersistence: pure I/O for the settlement
## construction ledger -- mirrors MarketStorePersistence/
## InstitutionStorePersistence exactly (docs/concept/timber_construction.md
## "Settlement construction ledger": its own long-named "no persistence
## wrapper yet" gap, closed because a City Hall takes real hours of labour
## (docs/concept/civic_construction.md) and an in-memory ledger threw that
## away on every restart).

const ConstructionProjectStorePersistence = preload("res://src/emergence/construction_project_store_persistence.gd")
const ConstructionProjectStore = preload("res://src/emergence/construction_project_store.gd")
const ConstructionProject = preload("res://src/emergence/construction_project.gd")

const TEST_PATH := "user://test_construction_project_store.bin"

var persistence: ConstructionProjectStorePersistence


func before_each():
	persistence = ConstructionProjectStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_project_mid_build():
	var store := ConstructionProjectStore.new()
	var project := store.start_project(Vector2i(3, -2), Vector2i(14, 13), "city_hall", "settlement:3_-2")
	project.status = ConstructionProject.Status.IN_PROGRESS
	project.labor_hours_accumulated = 17.5
	project.reserved_material = {"wood": 20.0, "stone": 10.0}
	project.resident_household_id = "household:9"

	persistence.save(store, TEST_PATH)
	var restored: ConstructionProjectStore = persistence.load_store(TEST_PATH)

	var back := restored.find_project(Vector2i(3, -2), Vector2i(14, 13), "city_hall")
	assert_not_null(back)
	assert_eq(back.id, project.id)
	assert_eq(back.status, ConstructionProject.Status.IN_PROGRESS)
	assert_almost_eq(back.labor_hours_accumulated, 17.5, 0.001, "the hours already worked survive a restart")
	assert_almost_eq(back.reserved_material.get("wood", 0.0), 20.0, 0.001)
	assert_eq(back.household_id, "settlement:3_-2")
	assert_eq(back.resident_household_id, "household:9")


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: ConstructionProjectStore = persistence.load_store(TEST_PATH)
	assert_true(restored.to_dicts().is_empty())


func test_wipe_removes_an_existing_save():
	persistence.save(ConstructionProjectStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
