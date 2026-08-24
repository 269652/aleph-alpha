extends GutTest

## MemoryStorePersistence: pure I/O for the emergence memory store -- mirrors
## EventStorePersistence/PlayerSave's role exactly (mechanics only, no
## knowledge of what a memory means). MemoryStore itself owns turning live
## state into/out of the plain Array this reads and writes.

const MemoryStorePersistence = preload("res://src/emergence/memory_store_persistence.gd")
const MemoryStore = preload("res://src/emergence/memory_store.gd")
const Event = preload("res://src/emergence/event.gd")

const TEST_PATH := "user://test_memory_store.bin"

var persistence: MemoryStorePersistence


func before_each():
	persistence = MemoryStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_bank():
	var bank := MemoryStore.new()
	var event := Event.new("crop_failure", 1.0)
	event.id = "evt_0_crop_failure"
	event.actors = ["npc:1"]
	bank.witness_event(event, 1.0)

	persistence.save(bank, TEST_PATH)
	var restored: MemoryStore = persistence.load_bank(TEST_PATH)

	assert_eq(restored.memories_for("npc:1").size(), 1)
	assert_eq(restored.memories_for("npc:1")[0].event_id, "evt_0_crop_failure")


func test_loading_with_no_save_file_returns_an_empty_bank():
	var restored: MemoryStore = persistence.load_bank(TEST_PATH)
	assert_eq(restored.memories_for("npc:1"), [])


func test_wipe_removes_an_existing_save():
	persistence.save(MemoryStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
