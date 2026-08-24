extends GutTest

## EventStorePersistence: pure I/O for the emergence event store -- mirrors
## PlayerSave/ChunkSerializer's role (mechanics only, no knowledge of what an
## event means). EventStore itself owns turning live state into/out of the
## plain Array this reads and writes (see EventStore.to_dicts/from_dicts).
##
## Follows the same store_var/get_var convention PlayerSave/ChunkSerializer
## already established for user://-backed Variant persistence, rather than
## inventing a second convention for one more kind of world state.

const EventStorePersistence = preload("res://src/emergence/event_store_persistence.gd")
const EventStore = preload("res://src/emergence/event_store.gd")
const Event = preload("res://src/emergence/event.gd")

const TEST_PATH := "user://test_emergence_events.bin"

var persistence: EventStorePersistence


func before_each():
	persistence = EventStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_has_save_is_true_after_saving():
	persistence.save(EventStore.new(), TEST_PATH)
	assert_true(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := EventStore.new()
	var cause_id: String = store.append(Event.new("drought", 1.0))
	var effect_id: String = store.append(Event.new("crop_failure", 2.0))
	store.link_cause(effect_id, cause_id)

	persistence.save(store, TEST_PATH)
	var restored: EventStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.size(), 2)
	assert_eq(restored.get_event(effect_id).causes, [cause_id])
	assert_eq(restored.get_event(cause_id).consequences, [effect_id])


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: EventStore = persistence.load_store(TEST_PATH)
	assert_eq(restored.size(), 0)


## A restored store must keep assigning ids correctly, or a fresh event
## recorded after loading could collide with one that already exists.
func test_a_loaded_store_continues_the_id_sequence():
	var store := EventStore.new()
	store.append(Event.new("a"))
	persistence.save(store, TEST_PATH)
	var restored: EventStore = persistence.load_store(TEST_PATH)
	var new_id: String = restored.append(Event.new("b"))
	assert_eq(new_id, "evt_1_b")


func test_wipe_removes_an_existing_save():
	persistence.save(EventStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
