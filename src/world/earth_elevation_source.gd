extends RefCounted

## Real-world elevation, bilinearly sampled from a bundled equirectangular
## grayscale image (see assets/data/CREDITS.md). Encoding: 0.0 = -8000m,
## 1.0 = +6400m, linear; sea level (0m) sits at ~0.5556.
const DEFAULT_IMAGE_PATH := "res://assets/data/world_elevation.png"

var _image: Image
var _width: int
var _height: int


func _init(image_path: String = DEFAULT_IMAGE_PATH) -> void:
	_image = Image.load_from_file(image_path)
	_width = _image.get_width()
	_height = _image.get_height()


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


func _pixel_elevation(x: int, y: int) -> float:
	return _image.get_pixel(x, y).r
