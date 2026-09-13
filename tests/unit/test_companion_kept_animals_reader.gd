extends GutTest

## CompanionKeptAnimalsReader: scans the bounded chunk_kept_animals
## directory (one .bin file per chunk, KeptAnimals.save_all/load_all's own
## format) and flattens every chunk's kept animals into one Array, each
## record tagged with the chunk_coord it came from. See
## docs/concept/companion_server.md's Companions section: KeptAnimals
## persists real trust/order/wander_seed per animal, but per-chunk -- this
## is the "scan every chunk's save file" plumbing that view was missing.

const CompanionKeptAnimalsReader = preload("res://src/companion_server/companion_kept_animals_reader.gd")
const KeptAnimals = preload("res://src/world/kept_animals.gd")

const TEST_DIR := "user://test_companion_kept_animals_reader"
const TEST_DIR_MISSING := "user://test_companion_kept_animals_reader_missing"


func after_each():
	_wipe_test_dir(TEST_DIR)


func _wipe_test_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func test_a_missing_directory_returns_an_empty_array():
	var result := CompanionKeptAnimalsReader.read_all(TEST_DIR_MISSING)
	assert_eq(result, [])


func test_reads_and_tags_a_real_kept_animal_fixture_with_its_chunk_coord():
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var animals := [{
		"species": "horse",
		"position": Vector2(10, 20),
		"trust": 0.75,
		"order": 1,
		"is_tied": true,
		"tied_to": Vector2(5, 5),
		"wander_seed": 42,
	}]
	KeptAnimals.save_all(animals, "%s/0_0.bin" % TEST_DIR)

	var result := CompanionKeptAnimalsReader.read_all(TEST_DIR)

	assert_eq(result.size(), 1)
	assert_eq(result[0]["species"], "horse")
	assert_eq(result[0]["wander_seed"], 42)
	assert_eq(result[0]["chunk_coord"], Vector2i(0, 0))


func test_parses_negative_chunk_coordinates_from_the_filename():
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var animals := [{
		"species": "wolf",
		"position": Vector2.ZERO,
		"trust": 1.0,
		"order": 0,
		"is_tied": false,
		"tied_to": Vector2.ZERO,
		"wander_seed": 7,
	}]
	KeptAnimals.save_all(animals, "%s/-3_-2.bin" % TEST_DIR)

	var result := CompanionKeptAnimalsReader.read_all(TEST_DIR)

	assert_eq(result.size(), 1)
	assert_eq(result[0]["chunk_coord"], Vector2i(-3, -2))
