extends RefCounted

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Real-world elevation, bilinearly sampled from a bundled equirectangular
## grayscale image (see assets/data/CREDITS.md). Encoding: 0.0 = -8000m,
## 1.0 = +6400m, linear; sea level (0m) sits at ~0.5556.
const DEFAULT_IMAGE_PATH := "res://assets/data/world_elevation.png"

## Decoded pixel maps, one per image path, shared by the whole process.
##
## Every EarthChunkGenerator builds its own EarthElevationSource and
## EarthChunkManager builds one generator, so this used to be one full decode
## of a 3840x1920 asset PER INSTANCE -- a CompressedTexture2D.get_image()
## readback, paid once per test fixture (measured ~0.9s for a test whose
## whole body is one generator construction). The pixels are identical every
## time and nothing ever writes to them, so the decode belongs to the process,
## not the instance. Same `static var _..._cache: Dictionary` shape
## IllustratedAnimalSprite._frame_cache and IllustratedCropSprite already use.
##
## Keyed by image_path, which is the entirety of what the decode depends on --
## pinned by test_a_different_path_decodes_to_a_different_map.
static var _decoded_cache: Dictionary = {}

## byte value -> the EXACT float Image.get_pixel(x, y).r hands back for it.
##
## Color stores 32-BIT floats, so a plain float64 `byte / 255.0` is NOT the
## number get_pixel returned: it differs in every single sample (measured,
## 5000 of 5000 probe coordinates). A PackedFloat32Array stores 32-bit floats
## too, so reading an entry back reproduces get_pixel's value bit for bit --
## which is what lets the flat-byte decode below be a pure speed change and
## not a silent redrawing of the world's coastlines.
## Pinned by test_pixel_samples_match_the_images_own_red_channel_exactly.
static var _byte_to_unit: PackedFloat32Array = _build_byte_to_unit()

var _bytes: PackedByteArray
var _width: int
var _height: int


static func _build_byte_to_unit() -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(256)
	for value in 256:
		table[value] = float(value) / 255.0
	return table


## The decoded {bytes, width, height} map for `image_path`, decoded at most
## once per process. Public so a test can assert the sharing directly.
##
## The asset is required to stay a single-channel 8-bit height field: one
## byte per pixel IS the datum. A non-L8 image is converted so the flat
## indexing below stays correct, but note that replacing the asset with a
## 16-BIT height field would silently truncate it to 8 bits here -- that is a
## real constraint on the asset, recorded in docs/concept/terrain_relief.md.
static func shared_map(image_path: String) -> Dictionary:
	if not _decoded_cache.has(image_path):
		var image := SpriteSheetLoader.load_image(image_path)
		if image.get_format() != Image.FORMAT_L8:
			# On a COPY: SpriteSheetLoader.load_image goes through the shared
			# ResourceLoader cache, so converting in place could mutate an
			# Image another illustrated-art class is holding. The bundled
			# elevation asset is already L8, so this branch does not run for
			# it -- but nothing about the signature says only that asset may
			# be passed.
			image = image.duplicate()
			image.convert(Image.FORMAT_L8)
		_decoded_cache[image_path] = {
			"bytes": image.get_data(),
			"width": image.get_width(),
			"height": image.get_height(),
		}
	return _decoded_cache[image_path]


func _init(image_path: String = DEFAULT_IMAGE_PATH) -> void:
	var decoded := shared_map(image_path)
	_bytes = decoded["bytes"]
	_width = decoded["width"]
	_height = decoded["height"]


## Returns the bilinearly-interpolated elevation at a real latitude/longitude
## (degrees). Longitude wraps around the date line; latitude clamps at the poles.
func elevation_at(latitude_deg: float, longitude_deg: float) -> float:
	var px_f := (longitude_deg + 180.0) / 360.0 * _width
	var py_f := (90.0 - latitude_deg) / 180.0 * _height

	var x0 := floori(px_f)
	var y0 := clampi(floori(py_f), 0, _height - 1)
	var y1 := clampi(y0 + 1, 0, _height - 1)
	var x1 := posmod(x0 + 1, _width)
	x0 = posmod(x0, _width)

	var fx := px_f - floorf(px_f)
	var fy := py_f - floorf(py_f)

	var top := lerpf(_pixel_elevation(x0, y0), _pixel_elevation(x1, y0), fx)
	var bottom := lerpf(_pixel_elevation(x0, y1), _pixel_elevation(x1, y1), fx)
	return lerpf(top, bottom, fy)


## One elevation sample, as an array index rather than a bound engine call
## that builds and boxes a Color to carry a single byte. Four of these per
## bilinear elevation_at, and elevation_at itself runs 4x per generated cell
## and 8x per hillshaded tile -- 32,768 of these per hillshaded 32x32 chunk,
## which is what made this the innermost loop of the whole terrain path.
func _pixel_elevation(x: int, y: int) -> float:
	return _byte_to_unit[_bytes[y * _width + x]]
