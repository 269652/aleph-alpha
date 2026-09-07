extends SceneTree

## Throwaway measurement tool: unlike worm.png (a perfectly regular grid),
## intro.png is AI-generated at 1983x793 -- not evenly divisible by the
## prompted 8 columns x 4 rows (1983/8=247.875, 793/4=198.25) -- so this
## measures the REAL row/column gutter boundaries directly rather than
## assuming arithmetic division, mirroring tools/probe_worm_sheet.gd's own
## "measure before pinning constants" convention.
##
## Two passes: first finds the 4 ROW bands by scanning for rows that are
## entirely magenta across the full sheet width (detect_frames itself only
## finds COLUMN dividers within an already-known row band -- see that
## function's own doc comment), then reuses SpriteSheetSlicer.detect_frames
## within each row band to find its own 8 column dividers.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15


func _init() -> void:
	var raw := Image.load_from_file("res://assets/sprites/intro.png")
	print("sheet size: ", raw.get_width(), "x", raw.get_height())
	print("corner pixel (0,0): ", raw.get_pixel(0, 0), " is_magenta=", _is_magenta(raw.get_pixel(0, 0)))
	print("center pixel: ", raw.get_pixel(raw.get_width() / 16, raw.get_height() / 8))

	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))

	var row_bands := _detect_row_bands(image)
	print("row bands (", row_bands.size(), "): ", row_bands)

	var slicer := SpriteSheetSlicer.new()
	for row_index in row_bands.size():
		var band: Vector2i = row_bands[row_index]
		var frames := slicer.detect_frames(image, band.x, band.y)
		print("row ", row_index, " y=[", band.x, ",", band.y, "): ", frames.size(), " frames")
		for f in frames:
			print("  ", f)

	quit()


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


## Row index ranges [top, bottom) that contain real content -- the
## row-wise analogue of detect_frames' own column scan.
static func _detect_row_bands(image: Image) -> Array:
	var bands: Array = []
	var start := -1
	for y in image.get_height():
		if _row_is_empty(image, y):
			if start >= 0:
				bands.append(Vector2i(start, y))
				start = -1
			continue
		if start < 0:
			start = y
	if start >= 0:
		bands.append(Vector2i(start, image.get_height()))
	return bands


static func _row_is_empty(image: Image, y: int) -> bool:
	for x in image.get_width():
		if image.get_pixel(x, y).a > 0.3:
			return false
	return true
