extends GutTest

## WorldReset: the New Game side of docs/concept/persistence.md -- wipes a
## user://-backed directory of per-chunk persistence files (EarthChunkManager's
## MODIFICATIONS_DIR/PLANTED_TREES_DIR/FISH_POPULATION_DIR) so a fresh world
## doesn't inherit a previous run's edits. Doesn't touch EarthChunkManager
## itself -- only the directory paths it already exposes as public constants.

const WorldReset = preload("res://src/world/world_reset.gd")

const TEST_DIR := "user://test_world_reset_dir"
## A single-file store, standing in for player_save.bin / the emergence
## stores -- the other half of what New Game destroys.
const TEST_FILE := "user://test_world_reset_file.bin"

var reset: WorldReset


func before_each():
	reset = WorldReset.new()
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func after_each():
	_remove_dir_recursive(TEST_DIR)
	# The backup lives NEXT TO the thing it backs up, so it survives the line
	# above -- without this the second test in a run inherits the first's
	# backup and "was it replaced?" can never fail.
	_remove_dir_recursive(TEST_DIR + WorldReset.BACKUP_SUFFIX)
	if FileAccess.file_exists(TEST_FILE + WorldReset.BACKUP_SUFFIX):
		DirAccess.remove_absolute(TEST_FILE + WorldReset.BACKUP_SUFFIX)
	if FileAccess.file_exists(TEST_FILE):
		DirAccess.remove_absolute(TEST_FILE)


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


# -- backups: New Game is the only irreversible button in the game, so what --
# -- it destroys is copied aside first (see docs/concept/persistence.md) -----

func _write_at(path: String, payload: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(payload)
	file.close()


func _read_at(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var value = file.get_var()
	file.close()
	return value


## The load-bearing one: exactly the New Game sequence, in order. A backup
## that does not outlive the wipe that follows it is no backup at all.
func test_backup_file_copies_the_file_before_a_wipe_removes_it():
	_write_at(TEST_FILE, {"health": 80.0})

	assert_true(reset.backup_file(TEST_FILE), "there WAS something to back up")
	DirAccess.remove_absolute(TEST_FILE)

	assert_false(FileAccess.file_exists(TEST_FILE), "the wipe still removes the original")
	assert_true(FileAccess.file_exists(TEST_FILE + WorldReset.BACKUP_SUFFIX))
	assert_eq(_read_at(TEST_FILE + WorldReset.BACKUP_SUFFIX), {"health": 80.0})


## ONE generation, not an archive: the second New Game's backup replaces the
## first's rather than the pair of them growing without bound.
func test_backup_file_replaces_a_previous_backup_rather_than_keeping_both():
	_write_at(TEST_FILE, {"run": 1})
	reset.backup_file(TEST_FILE)
	_write_at(TEST_FILE, {"run": 2})

	reset.backup_file(TEST_FILE)

	assert_eq(_read_at(TEST_FILE + WorldReset.BACKUP_SUFFIX), {"run": 2})


## A first-ever New Game has nothing to copy. That is not an error, and it
## must not leave an empty .bak lying around for a later restore to trust.
func test_backup_file_on_a_missing_file_reports_nothing_to_back_up():
	assert_false(reset.backup_file("user://does_not_exist_at_all.bin"))
	assert_false(FileAccess.file_exists("user://does_not_exist_at_all.bin.bak"))


func test_backup_directory_survives_the_wipe_that_follows_it():
	_write_file("0_0.bin")
	_write_file("1_-1.bin")

	reset.backup_directory(TEST_DIR)
	reset.wipe_directory(TEST_DIR)

	assert_false(FileAccess.file_exists(TEST_DIR + "/0_0.bin"), "the wipe still empties the dir")
	assert_false(FileAccess.file_exists(TEST_DIR + "/1_-1.bin"))
	var backup := TEST_DIR + WorldReset.BACKUP_SUFFIX
	assert_true(FileAccess.file_exists(backup + "/0_0.bin"))
	assert_true(FileAccess.file_exists(backup + "/1_-1.bin"))


## The directory backup mirrors ONE wipe. A chunk file that existed before
## the previous New Game, and not before this one, must not still be sitting
## in the backup pretending to belong to the world we just destroyed.
func test_backup_directory_mirrors_one_wipe_not_an_accumulating_pile():
	_write_file("from_the_first_world.bin")
	reset.backup_directory(TEST_DIR)
	reset.wipe_directory(TEST_DIR)
	_write_file("from_the_second_world.bin")

	reset.backup_directory(TEST_DIR)

	var backup := TEST_DIR + WorldReset.BACKUP_SUFFIX
	assert_true(FileAccess.file_exists(backup + "/from_the_second_world.bin"))
	assert_false(
		FileAccess.file_exists(backup + "/from_the_first_world.bin"),
		"one generation, not an archive"
	)


func test_backup_directory_on_a_missing_directory_does_not_error():
	reset.backup_directory("user://does_not_exist_at_all_either")
	assert_false(DirAccess.dir_exists_absolute("user://does_not_exist_at_all_either.bak"))
