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


func test_returns_null_for_a_path_that_does_not_exist():
	assert_null(SpriteSheetLoader.load_image("res://assets/sprites/not_a_real_sheet.png"))
