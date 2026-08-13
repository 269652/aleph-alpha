extends GutTest

## WorldReset: the New Game side of docs/concept/persistence.md -- wipes a
## user://-backed directory of per-chunk persistence files (EarthChunkManager's
## MODIFICATIONS_DIR/PLANTED_TREES_DIR/FISH_POPULATION_DIR) so a fresh world
## doesn't inherit a previous run's edits. Doesn't touch EarthChunkManager
## itself -- only the directory paths it already exposes as public constants.

const WorldReset = preload("res://src/world/world_reset.gd")

const TEST_DIR := "user://test_world_reset_dir"

var reset: WorldReset


func before_each():
	reset = WorldReset.new()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after_each():
	_remove_dir_recursive(TEST_DIR)


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_file(name: String) -> void:
	var file := FileAccess.open(TEST_DIR + "/" + name, FileAccess.WRITE)
	file.store_var({"stub": true})
	file.close()


func test_wipe_directory_removes_every_file_in_it():
	_write_file("0_0.bin")
	_write_file("1_-1.bin")

	reset.wipe_directory(TEST_DIR)

	assert_false(FileAccess.file_exists(TEST_DIR + "/0_0.bin"))
	assert_false(FileAccess.file_exists(TEST_DIR + "/1_-1.bin"))


func test_wipe_directory_on_a_missing_directory_does_not_error():
	reset.wipe_directory("user://does_not_exist_at_all")
	# No crash/error is the assertion; nothing else to check.
	assert_true(true)


func test_wipe_directory_leaves_the_directory_itself_usable_afterward():
	_write_file("0_0.bin")
	reset.wipe_directory(TEST_DIR)
	_write_file("2_2.bin")  # writing again should still work
	assert_true(FileAccess.file_exists(TEST_DIR + "/2_2.bin"))
