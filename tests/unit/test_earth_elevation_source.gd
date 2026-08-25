extends GutTest

const EarthElevationSource = preload("res://src/world/earth_elevation_source.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## A second real, tracked, imported asset -- used only to prove the decode
## memo is genuinely keyed by path. Any bundled PNG would do; this one is
## small and unrelated to elevation, so a cache that ignored its key would
## visibly serve the wrong pixel map.
const OTHER_IMAGE_PATH := "res://assets/sprites/cobbles.png"

var source: EarthElevationSource


func before_each():
	source = EarthElevationSource.new()


## _init used to load world_elevation.png via a raw Image.load_from_file,
## which logs an engine WARNING ("Loaded resource as image file, this will
## not work on export") that GUT's error tracker counts as an unhandled
## error -- see SpriteSheetLoader's own doc comment for why. Mirrors
## test_sprite_sheet_loader.gd's own assert_engine_error_count(0, ...) check.
##
## Constructs its OWN instance rather than using before_each's `source`:
## GUT's error tracker does not attribute a warning logged during before_each
## to the test that follows it (a timing quirk, not a real pass) -- so this
## must construct inside the test body itself to actually observe the
## warning fire.
func test_construction_does_not_log_an_engine_warning():
	EarthElevationSource.new()
	assert_engine_error_count(0, "constructing EarthElevationSource should not warn")


func test_the_deepest_ocean_trench_has_very_low_elevation():
	# Mariana Trench, measured directly from the bundled asset at ~0.0431.
	assert_lt(source.elevation_at(11.0, 142.0), 0.1)


func test_the_highest_mountain_has_very_high_elevation():
	# Everest, measured directly from the bundled asset at ~0.9765.
	assert_gt(source.elevation_at(27.99, 86.92), 0.9)


func test_low_lying_land_is_close_to_the_sea_level_threshold():
	# Amazon basin, measured directly from the bundled asset at ~0.5647.
	assert_almost_eq(source.elevation_at(-3.0, -60.0), 0.5556, 0.05)


func test_open_ocean_is_below_sea_level():
	# Mid-Pacific, measured directly from the bundled asset at ~0.1882.
	assert_lt(source.elevation_at(0.0, -160.0), 0.5556)


func test_longitude_wraps_continuously_across_the_date_line():
	var just_west_of_the_date_line := source.elevation_at(0.0, 179.9)
	var just_east_of_the_date_line := source.elevation_at(0.0, -179.9)
	assert_almost_eq(just_west_of_the_date_line, just_east_of_the_date_line, 0.1)


# -- one shared decode per path, and a flat byte map instead of boxed Colors ----

## Every EarthChunkGenerator builds its own EarthElevationSource, and
## EarthChunkManager builds one generator -- i.e. one full decode of the
## 3840x1920 asset per test fixture. The pixels are identical every time and
## are never written, so the decode belongs to the PROCESS, not the instance
## (the same `static var _..._cache` shape IllustratedAnimalSprite already
## uses). Dictionaries are reference types in GDScript, so identity here is a
## real "decoded once, shared" assertion and not just a value comparison.
##
## Uses the global is_same() rather than assert_same(): a failing
## assert_same/assert_not_same STRINGIFIES both operands into its message,
## and these dictionaries hold a 7,372,800-byte PackedByteArray each -- doing
## that once took the headless runner to 14.6 GB resident before it was
## killed. Asserting on the boolean keeps the identity check exact and the
## failure message one word long.
func test_two_sources_on_the_same_path_share_one_decoded_map():
	var first := EarthElevationSource.shared_map(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var second := EarthElevationSource.shared_map(EarthElevationSource.DEFAULT_IMAGE_PATH)
	assert_true(
		is_same(first, second), "the decoded elevation map must be decoded once per process"
	)


## A different path must decode to a different map. The memo's key has to
## cover everything that can vary about the decode, and the path is the whole
## of that -- a cache that ignored it would serve one asset's pixels for
## another's, which is exactly the failure a shared static invites.
func test_a_different_path_decodes_to_a_different_map():
	var world := EarthElevationSource.shared_map(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var other := EarthElevationSource.shared_map(OTHER_IMAGE_PATH)
	assert_false(is_same(other, world), "two different assets must not share one cache entry")
	var other_width: int = other["width"]
	var world_width: int = world["width"]
	assert_ne(other_width, world_width, "and must not report each other's dimensions")


## The elevation asset is a single-channel 8-bit height field, so the byte IS
## the datum -- but Image.get_pixel() has to build and box a Color to hand it
## back, four times per bilinear sample and eight times per hillshaded tile.
## Once the source keeps the flat byte map instead, it has no reason to hold
## the Image alive at all.
func test_the_source_holds_no_decoded_image_field():
	assert_false(
		"_image" in source,
		"sampling reads a flat byte map now; retaining the Image keeps ~7.4 MB per instance alive"
	)


## THE correctness pin for the byte decode: a sample must be the SAME float
## Image.get_pixel(x, y).r would have returned, exactly -- not merely close.
## Color stores 32-bit floats, so a naive float64 `byte / 255.0` differs from
## get_pixel in EVERY sample (measured: 5000 of 5000 probe coordinates); the
## source therefore maps bytes through a PackedFloat32Array, whose stored
## values are 32-bit too. Covers both edges of both axes plus a spread of
## interior pixels, so an off-by-one-row indexing error cannot hide.
func test_pixel_samples_match_the_images_own_red_channel_exactly():
	var image := SpriteSheetLoader.load_image(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var width := image.get_width()
	var height := image.get_height()
	var coords: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(width - 1, 0),
		Vector2i(0, height - 1),
		Vector2i(width - 1, height - 1),
		Vector2i(1, 0),
		Vector2i(0, 1),
	]
	for i in 400:
		coords.append(Vector2i((i * 7919) % width, (i * 104729) % height))
	for coord in coords:
		assert_eq(
			source._pixel_elevation(coord.x, coord.y),
			image.get_pixel(coord.x, coord.y).r,
			"pixel %s must sample bit-identically to Image.get_pixel().r" % coord
		)


## The pre-refactor sampler, verbatim, written against Image.get_pixel() --
## the ORACLE for the test below. Kept here rather than as pinned decimal
## literals on purpose: Godot's own `%.17f` does not round-trip a double
## (measured -- a printed Everest reading came back 3.5e-8 off, and a printed
## mid-Pacific reading displayed identically yet compared unequal), so a
## written-down constant cannot express "bit for bit" at all. A duplicated
## reference implementation can, and it also fails loudly if the bilinear
## blend itself is ever changed rather than only its pixel access.
func _reference_elevation_at(image: Image, latitude_deg: float, longitude_deg: float) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var px_f := (longitude_deg + 180.0) / 360.0 * width
	var py_f := (90.0 - latitude_deg) / 180.0 * height

	var x0 := floori(px_f)
	var y0 := clampi(floori(py_f), 0, height - 1)
	var y1 := clampi(y0 + 1, 0, height - 1)
	var x1 := posmod(x0 + 1, width)
	x0 = posmod(x0, width)

	var fx := px_f - floorf(px_f)
	var fy := py_f - floorf(py_f)

	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, fx)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, fx)
	return lerpf(top, bottom, fy)


## The whole world's geography rides on elevation_at, so RULE: the flat-byte
## decode must return exactly what the boxed-Color decode returned -- not
## "close", exactly. Real landmarks (Mariana Trench, Everest, Amazon basin,
## mid-Pacific, Berlin) plus 300 scattered coordinates and both poles, so a
## coastline that moved by one bit anywhere fails here rather than silently
## redrawing the world.
func test_elevation_at_is_bit_for_bit_the_boxed_color_reference():
	var image := SpriteSheetLoader.load_image(EarthElevationSource.DEFAULT_IMAGE_PATH)
	var places: Array[Vector2] = [
		Vector2(11.0, 142.0),
		Vector2(27.99, 86.92),
		Vector2(-3.0, -60.0),
		Vector2(0.0, -160.0),
		Vector2(52.52, 13.405),
		Vector2(90.0, 0.0),
		Vector2(-90.0, 0.0),
		Vector2(0.0, 179.999),
		Vector2(0.0, -179.999),
	]
	for i in 300:
		places.append(Vector2(fmod(i * 7.919, 180.0) - 90.0, fmod(i * 13.7, 360.0) - 180.0))
	for place in places:
		assert_eq(
			source.elevation_at(place.x, place.y),
			_reference_elevation_at(image, place.x, place.y),
			"elevation at lat/lon %s must be bit-identical to the boxed-Color sampler" % place
		)
