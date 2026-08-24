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
