extends SceneTree

## Throwaway measurement tool: assets/sprites/animals/worm.png is a perfectly
## regular 8-column x 4-row grid (1536/8=192, 1024/4=256 exactly, confirmed:
## every row's own detect_frames finds column starts within 2px of i*192).
## detect_frames' content-gap heuristic misreads the early coiled-worm poses
## in row 4 (an internal notch between the loop and the body reads as a
## second frame boundary) -- rather than fight that per-row, this slices the
## KNOWN fixed grid directly and hands normalize_frames the outer rects,
## which finds each frame's own tight content bbox regardless of where the
## outer rect came from. Confirms every one of the 32 cells has real,
## reasonably-bounded content before this becomes the shipped slicing code.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

const _COLUMNS := 8
const _ROWS := 4
const _CELL_W := 192
const _CELL_H := 256

const _ROW_NAMES := ["crawl", "emerge", "retreat", "die"]


func _init() -> void:
	var raw := Image.load_from_file("res://assets/sprites/animals/worm.png")
	print("sheet size: ", raw.get_width(), "x", raw.get_height())

	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))

	var slicer := SpriteSheetSlicer.new()
	var canvas_size := Vector2i(200, 260)
	var baseline_y := 250

	for row in _ROWS:
		var frames: Array[Rect2i] = []
		for col in _COLUMNS:
			frames.append(Rect2i(col * _CELL_W, row * _CELL_H, _CELL_W, _CELL_H))
		var normalized := slicer.normalize_frames(image, frames, canvas_size, baseline_y)
		print("row ", row + 1, " (", _ROW_NAMES[row], "): ", normalized.size(), " normalized frames")
		for i in normalized.size():
			var bounds := _painted_bounds(normalized[i])
			print("  frame ", i, " content bounds: ", bounds, " blank=", bounds.size.x <= 0)

	quit()


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _painted_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.1:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
