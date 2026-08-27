extends GutTest

const LicenseStore = preload("res://src/licensing/license_store.gd")

var _test_paths: Array[String] = []


func after_each():
	for path in _test_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_test_paths.clear()


func _write_temp_file(name: String, contents: String) -> String:
	var path := "user://%s" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
	_test_paths.append(path)
	return path


func test_reads_the_first_existing_candidate_path():
	var path := _write_temp_file("test_license_store_a.txt", "ABCDE-FGHIJ")
	assert_eq(LicenseStore.read_code([path]), "ABCDE-FGHIJ")


func test_skips_missing_candidates_and_reads_the_next_one_that_exists():
	var real_path := _write_temp_file("test_license_store_b.txt", "REALCODE")
	var missing_path := "user://this_file_does_not_exist_%d.txt" % randi()
	assert_eq(LicenseStore.read_code([missing_path, real_path]), "REALCODE")


func test_returns_empty_string_when_no_candidate_exists():
	assert_eq(LicenseStore.read_code(["user://definitely_missing_license.txt"]), "")


func test_returns_empty_string_for_an_empty_candidate_list():
	assert_eq(LicenseStore.read_code([]), "")


## A customer pasting a code into a text file is very likely to leave a
## trailing newline or stray whitespace -- must not silently fail
## verification over something that isn't part of the actual code.
func test_trims_surrounding_whitespace_and_newlines():
	var path := _write_temp_file("test_license_store_c.txt", "  ABCDE-FGHIJ\r\n\n")
	assert_eq(LicenseStore.read_code([path]), "ABCDE-FGHIJ")


func test_default_candidate_paths_checks_the_executable_directory_first_then_user_dir():
	var paths := LicenseStore.default_candidate_paths()
	assert_eq(paths.size(), 2)
	assert_true(paths[0].ends_with("license.txt"))
	assert_eq(paths[1], "user://license.txt")


## write_code() is the save half of the in-game "enter a license key" UI --
## a customer pasting a new code should be able to overwrite whatever was
## there before, not just append/create-if-missing.
func test_write_code_writes_a_code_that_read_code_then_reads_back():
	var path := "user://test_license_store_write_a.txt"
	_test_paths.append(path)
	LicenseStore.write_code([path], "NEWCODE-12345")
	assert_eq(LicenseStore.read_code([path]), "NEWCODE-12345")


func test_write_code_trims_surrounding_whitespace_before_writing():
	var path := "user://test_license_store_write_b.txt"
	_test_paths.append(path)
	LicenseStore.write_code([path], "  NEWCODE-12345  \n")
	assert_eq(LicenseStore.read_code([path]), "NEWCODE-12345")


func test_write_code_overwrites_an_existing_file_rather_than_leaving_stale_content():
	var path := _write_temp_file("test_license_store_write_c.txt", "OLDCODE")
	LicenseStore.write_code([path], "REPLACEMENT")
	assert_eq(LicenseStore.read_code([path]), "REPLACEMENT")


## A stale, still-present old license.txt next to the executable must not
## keep shadowing a freshly-saved one -- read_code() returns the FIRST
## existing candidate, so saving has to refresh every candidate, not just
## whichever one happens to be writable/first.
func test_write_code_writes_to_every_candidate_path_not_just_the_first():
	var path_a := "user://test_license_store_write_d.txt"
	var path_b := "user://test_license_store_write_e.txt"
	_test_paths.append(path_a)
	_test_paths.append(path_b)
	LicenseStore.write_code([path_a, path_b], "BOTHCODE")
	assert_eq(LicenseStore.read_code([path_a]), "BOTHCODE")
	assert_eq(LicenseStore.read_code([path_b]), "BOTHCODE")


func test_write_code_returns_true_when_at_least_one_path_is_writable():
	var path := "user://test_license_store_write_f.txt"
	_test_paths.append(path)
	assert_true(LicenseStore.write_code([path], "SOMECODE"))


## A path under a directory that doesn't exist can't be opened for
## writing -- write_code() must not crash on that, and must not falsely
## report success when every candidate failed.
func test_write_code_returns_false_when_every_path_is_unwritable():
	var unwritable := "user://this_directory_does_not_exist_%d/license.txt" % randi()
	assert_false(LicenseStore.write_code([unwritable], "SOMECODE"))
