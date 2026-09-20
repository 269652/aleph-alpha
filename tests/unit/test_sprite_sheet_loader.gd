extends GutTest

## Pins SpriteSheetLoader: every illustrated-art sheet loader
## (IllustratedStoneSprite, IllustratedAnimalSprite, IllustratedFlowerHead,
## IllustratedTerrainSprite) used to read its sheet with
## Image.load_from_file(path) directly. That works, but logs an engine
## warning -- "Loaded resource as image file, this will not work on export"
## -- the first time any given sheet is actually loaded in a run. GUT treats
## an unhandled engine warning as an "Unexpected Error" and fails whichever
## test happens to be first to touch a given sheet (each class then caches
## its sliced frames, so every later test touching the SAME sheet passes
## clean) -- an order-dependent flake confirmed in test_stone_renderer.gd.
##
## IllustratedTree hit this same warning first and fixed it by preferring
## load() -- which uses the sheet's own real *.png.import, generated the
## first time the project opened in the editor, exactly the resource the
## warning's own message asks for -- over the raw file read (see its
## _load_image). This pulls that fix out into a shared loader every
## illustrated-art class can use instead of duplicating it per file.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## A real sheet, already imported -- every sheet under assets/sprites/ has
## its own *.png.import checked into the repo (generated the first time the
## project opened in the editor), pebbles.png included.
const REAL_SHEET_PATH := "res://assets/sprites/pebbles.png"


func test_loads_a_real_imported_sheet():
	var image: Image = SpriteSheetLoader.load_image(REAL_SHEET_PATH)
	assert_not_null(image)
	assert_gt(image.get_width(), 0)
	assert_gt(image.get_height(), 0)


## The actual regression: loading a sheet that already has a real .import
## must not log the export warning that a raw Image.load_from_file triggers.
func test_loading_a_real_imported_sheet_does_not_trigger_the_export_warning():
	SpriteSheetLoader.load_image(REAL_SHEET_PATH)
	assert_engine_error_count(
		0, "loading an already-imported sheet should not warn about raw file loads"
	)


## Same pixels as loading the resource directly -- proves the loader is not
## some lossy or differently-formatted path, just a warning-free route to the
## same content (every sheet's .import is lossless: compress/mode=0).
func test_returns_the_same_pixels_as_loading_the_resource_directly():
	var expected: Image = (load(REAL_SHEET_PATH) as Texture2D).get_image()
	var actual: Image = SpriteSheetLoader.load_image(REAL_SHEET_PATH)
	assert_eq(actual.get_format(), expected.get_format())
	assert_eq(actual.get_data(), expected.get_data())


## Falls back to reading the file directly for a path ResourceLoader does not
## recognize -- a freshly-added sheet in a headless test run that has never
## opened the project in the editor (see IllustratedTree._load_image, which
## pinned this exact fallback first). A user:// copy of a real sheet stands
## in for "not part of the imported res:// tree" without needing an actual
## unimported fixture checked into the repo.
func test_falls_back_to_the_raw_file_when_the_resource_is_not_imported():
	var fixture_path := "user://sprite_sheet_loader_fixture.png"
	var out := FileAccess.open(fixture_path, FileAccess.WRITE)
	out.store_buffer(FileAccess.get_file_as_bytes(REAL_SHEET_PATH))
	out.close()
	assert_false(
		ResourceLoader.exists(fixture_path), "user:// is not part of the imported res:// tree"
	)

	var image: Image = SpriteSheetLoader.load_image(fixture_path)
	var expected: Image = (load(REAL_SHEET_PATH) as Texture2D).get_image()
	assert_not_null(image)
	assert_eq(image.get_width(), expected.get_width())
	assert_eq(image.get_height(), expected.get_height())
	assert_engine_error_count(0, "a real file outside the imported res:// tree should not warn")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


## Every sheet the repo actually ships loads, cleanly, on a checkout that
## has never been opened in the editor.
##
## This is the case the fallback above was written for and did not really
## cover: a sheet whose *.png.import IS committed but whose imported
## artifact under .godot/ has never been generated. ResourceLoader.exists()
## answers TRUE off the sidecar alone, so the loader took the load() branch
## and load() failed on the missing .ctex -- a null image and an engine
## error, on a file that is right there on disk.
##
## Found with assets/sprites/vehicles/cart.png, whose sidecar was committed
## in a container that never ran an editor import; the whole cart suite
## failed on art that loads fine from its own bytes.
func test_every_sheet_the_repo_ships_loads_without_an_engine_error():
	var checked := 0
	for path in _every_sheet_path("res://assets/sprites"):
		var image: Image = SpriteSheetLoader.load_image(path)
		assert_not_null(image, "%s did not load" % path)
		if image != null:
			assert_gt(image.get_width(), 0, "%s loaded empty" % path)
		checked += 1
	assert_gt(checked, 0, "precondition: the repo ships sheets at all")
	assert_engine_error_count(0, "a sheet on disk is a sheet that loads quietly")


func _every_sheet_path(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [root, entry]
		if dir.current_is_dir():
			out.append_array(_every_sheet_path(full))
		elif entry.ends_with(".png"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func test_returns_null_for_a_path_that_does_not_exist():
	assert_null(SpriteSheetLoader.load_image("res://assets/sprites/not_a_real_sheet.png"))


# -- every shipped sheet carries its own .import sidecar --------------------
#
# The tolerant loader above hides this one, and that is the point: a sheet
# whose *.png.import was never committed still loads through
# SpriteSheetLoader, because the fallback reads its bytes. But the art
# classes that use `load()` directly -- the structure sheets, the yards --
# get a NULL texture on a fresh checkout, and a null texture in a
# sprite-crop test reads exactly like a genuine sheet regression.
#
# Twice in one day: the two yard sheets (fixed by 3e7286cb) and then
# fern.png, which took down test_no_house_crop_cuts_through_the_top_of_its_
# own_drawing with "Cannot call method 'get_image' on a null value" on a
# file that was right there on disk.
#
# On a fresh clone -- CI, or a new container -- "the sidecar is on disk" and
# "the sidecar was committed" are the same statement, which is what makes
# this checkable at all from inside the engine.


## Every *.png under `root` with no *.png.import beside it.
func _sheets_missing_a_sidecar(root: String) -> Array:
	var missing: Array = []
	for path in _every_sheet_path(root):
		if not FileAccess.file_exists(path + ".import"):
			missing.append(path)
	return missing


## The rule itself, against a sheet deliberately left without one -- so a
## green result below means "nothing is missing", never "nothing was
## looked at".
func test_a_sheet_with_no_sidecar_is_found():
	var dir := "user://sidecar_fixture"
	DirAccess.make_dir_recursive_absolute(dir)
	var bare := "%s/bare.png" % dir
	var out := FileAccess.open(bare, FileAccess.WRITE)
	out.store_buffer(FileAccess.get_file_as_bytes(REAL_SHEET_PATH))
	out.close()

	assert_eq(
		_sheets_missing_a_sidecar(dir), [bare],
		"a sheet with no .import beside it has to be findable, or the sweep below proves nothing"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(bare))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func test_every_shipped_sheet_carries_its_own_import_sidecar():
	var missing := _sheets_missing_a_sidecar("res://assets/sprites")
	assert_eq(
		missing, [],
		"these sheets load as null through load() on a fresh checkout: %s" % str(missing)
	)
