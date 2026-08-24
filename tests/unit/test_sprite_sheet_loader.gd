extends GutTest

## Pins SpriteSheetLoader: the shared "prefer the imported resource, fall
## back to a raw file read only when there is no import" behaviour every
## illustrated-art loader in this codebase delegates to (IllustratedStone
## Sprite, IllustratedAnimalSprite, IllustratedFlowerHead, IllustratedTerrain
## Sprite, IllustratedTree) -- see the class's own doc comment for why a raw
## Image.load_from_file is a bug, not just noisy: it also does not ship in
## an exported build the way an imported resource does.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## A real, checked-in imported asset. Any registered sheet would do; this one
## is small and already used by EarthElevationSource.
const _IMPORTED_PATH := "res://assets/data/world_elevation.png"
const _FALLBACK_PATH := "user://sprite_sheet_loader_test_fixture.png"


func after_each():
	if FileAccess.file_exists(_FALLBACK_PATH):
		DirAccess.remove_absolute(_FALLBACK_PATH)


## The whole reason this class exists: a raw Image.load_from_file on an
## imported PNG logs an engine WARNING ("Loaded resource as image file, this
## will not work on export") that GUT's error tracker counts as an
## unhandled error and fails the test over, even though nothing actually
## asserted false -- see EarthElevationSource's own _init before this fix
## for a real example of it firing on every construction.
func test_loading_an_imported_resource_does_not_log_an_engine_warning():
	SpriteSheetLoader.load_image(_IMPORTED_PATH)
	assert_engine_error_count(0, "load()-ing an imported resource should not warn")


func test_loading_an_imported_resource_returns_its_real_pixels():
	var image := SpriteSheetLoader.load_image(_IMPORTED_PATH)
	assert_not_null(image)
	assert_gt(image.get_width(), 0)
	assert_gt(image.get_height(), 0)


## The fallback this class exists for: a path that is genuinely on disk but
## was never imported (e.g. a fixture written at runtime, or a headless test
## run before `--import` has been run) must still load real pixel data, by
## reading the file directly.
func test_loading_an_unimported_file_falls_back_to_a_direct_read():
	var source: Image = load(_IMPORTED_PATH).get_image()
	source.save_png(_FALLBACK_PATH)
	assert_false(
		ResourceLoader.exists(_FALLBACK_PATH), "fixture must not be a registered resource"
	)

	var image := SpriteSheetLoader.load_image(_FALLBACK_PATH)

	assert_not_null(image)
	assert_eq(image.get_width(), source.get_width())
	assert_eq(image.get_height(), source.get_height())
