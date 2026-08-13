extends GutTest

## PlayerSave: pure I/O for the player's persisted state -- mirrors
## ChunkSerializer's role (mechanics only, no game-domain knowledge of what
## the dictionary means; see docs/concept/persistence.md). Player itself owns
## turning live state into/out of the plain Dictionary this reads and writes
## (see test_player_persistence.gd).

const PlayerSave = preload("res://src/gameplay/player_save.gd")

const TEST_PATH := "user://test_player_save.bin"

var save: PlayerSave


func before_each():
	save = PlayerSave.new()


func after_each():
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_has_save_is_false_when_no_file_exists():
	assert_false(save.has_save(TEST_PATH))


func test_has_save_is_true_after_saving():
	save.save({"health": 80.0}, TEST_PATH)
	assert_true(save.has_save(TEST_PATH))


func test_save_then_load_round_trips_the_dictionary():
	var data := {"health": 80.0, "inventory": [{"id": "iron_sword", "count": 1}]}
	save.save(data, TEST_PATH)
	assert_eq(save.load_data(TEST_PATH), data)


func test_loading_with_no_save_file_returns_an_empty_dictionary():
	assert_eq(save.load_data(TEST_PATH), {})


func test_wipe_removes_an_existing_save():
	save.save({"health": 80.0}, TEST_PATH)
	save.wipe(TEST_PATH)
	assert_false(save.has_save(TEST_PATH))


func test_wipe_on_a_missing_save_does_not_error():
	save.wipe(TEST_PATH)
	assert_false(save.has_save(TEST_PATH))
