extends GutTest

## TerrainAtlasCache: pure I/O for TerrainRenderer's baked atlas image (see
## docs/concept/art_resolution.md#boot-performance) -- mirrors PlayerSave's
## role/shape (mechanics only, path-overridable so tests never touch the
## real cache file).

const TerrainAtlasCache = preload("res://src/rendering/terrain_atlas_cache.gd")

const TEST_CACHE_PATH := "user://test_atlas_cache.png"
const TEST_VERSION_PATH := "user://test_atlas_cache_version.txt"

var cache: TerrainAtlasCache


func before_each():
	cache = TerrainAtlasCache.new()


func after_each():
	if FileAccess.file_exists(TEST_CACHE_PATH):
		DirAccess.remove_absolute(TEST_CACHE_PATH)
	if FileAccess.file_exists(TEST_VERSION_PATH):
		DirAccess.remove_absolute(TEST_VERSION_PATH)


func _make_image() -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.2, 0.1, 1.0))
	return image


func test_has_valid_cache_is_false_when_nothing_is_cached():
	assert_false(cache.has_valid_cache("v1", TEST_CACHE_PATH, TEST_VERSION_PATH))


func test_has_valid_cache_is_true_after_saving_the_same_version():
	cache.save(_make_image(), "v1", TEST_CACHE_PATH, TEST_VERSION_PATH)
	assert_true(cache.has_valid_cache("v1", TEST_CACHE_PATH, TEST_VERSION_PATH))


## The whole point of versioning: a cache built under an older generation
## algorithm must never be silently reused once the algorithm changes.
func test_has_valid_cache_is_false_when_the_version_differs():
	cache.save(_make_image(), "v1", TEST_CACHE_PATH, TEST_VERSION_PATH)
	assert_false(cache.has_valid_cache("v2", TEST_CACHE_PATH, TEST_VERSION_PATH))


func test_save_then_load_round_trips_the_image_pixels():
	var original := _make_image()
	cache.save(original, "v1", TEST_CACHE_PATH, TEST_VERSION_PATH)
	var loaded := cache.load_image(TEST_CACHE_PATH)
	assert_not_null(loaded)
	assert_eq(loaded.get_width(), original.get_width())
	assert_eq(loaded.get_height(), original.get_height())
	assert_eq(loaded.get_pixel(0, 0), original.get_pixel(0, 0))


func test_load_image_on_a_missing_file_returns_null_rather_than_crashing():
	assert_null(cache.load_image(TEST_CACHE_PATH))


func test_wipe_removes_both_the_image_and_version_files():
	cache.save(_make_image(), "v1", TEST_CACHE_PATH, TEST_VERSION_PATH)
	cache.wipe(TEST_CACHE_PATH, TEST_VERSION_PATH)
	assert_false(cache.has_valid_cache("v1", TEST_CACHE_PATH, TEST_VERSION_PATH))
	assert_null(cache.load_image(TEST_CACHE_PATH))


func test_wipe_on_a_missing_cache_does_not_error():
	cache.wipe(TEST_CACHE_PATH, TEST_VERSION_PATH)
	assert_false(cache.has_valid_cache("v1", TEST_CACHE_PATH, TEST_VERSION_PATH))
