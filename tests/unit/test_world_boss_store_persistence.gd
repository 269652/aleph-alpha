extends GutTest

## WorldBossStorePersistence: pure I/O for the emergence world-boss store --
## mirrors EventStorePersistence/.../InstitutionStorePersistence/
## PlayerSave's role exactly.

const WorldBossStorePersistence = preload("res://src/emergence/world_boss_store_persistence.gd")
const WorldBossStore = preload("res://src/emergence/world_boss_store.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")

const TEST_PATH := "user://test_world_boss_store.bin"

var persistence: WorldBossStorePersistence


func before_each():
	persistence = WorldBossStorePersistence.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(persistence.has_save(TEST_PATH))


func test_save_then_load_round_trips_a_real_store():
	var store := WorldBossStore.new()
	var boss := store.promote("creature:1", "predator", 900.0, 800.0, [], 1.0)

	persistence.save(store, TEST_PATH)
	var restored: WorldBossStore = persistence.load_store(TEST_PATH)

	assert_eq(restored.get_boss(boss.id).species, "predator")
	assert_eq(restored.active_boss_for("creature:1").id, boss.id)


func test_loading_with_no_save_file_returns_an_empty_store():
	var restored: WorldBossStore = persistence.load_store(TEST_PATH)
	assert_null(restored.active_boss_for("creature:1"))


func test_wipe_removes_an_existing_save():
	persistence.save(WorldBossStore.new(), TEST_PATH)
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	persistence.wipe(TEST_PATH)
	assert_false(persistence.has_save(TEST_PATH))
