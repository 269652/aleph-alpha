extends SceneTree

## Measurement tool for assets/sprites/beehive.png -- see
## tools/probe_worm_sheet.gd's own precedent/reasoning: a sheet whose
## dimensions divide EVENLY (2048/8=256, 768/3=256 exactly) is measured
## directly against detect_frames' own column-gap heuristic before
## deciding whether the known fixed grid or the heuristic is the right
## slicing technique to ship -- never assumed either way.
##
## FINDINGS (confirms the technique IllustratedBeehiveSprite actually
## uses): detect_frames misreads row 0 (honeycomb) and row 2 (debris) as
## 10/11 "frames" instead of the real 8 -- tripped up by internal content
## gaps in the artwork, the exact same failure mode probe_worm_sheet.gd
## already documented for worm.png's own coiled poses. Row 1 (smooth
## sealed-hive silhouettes) detects the correct 8, but for consistency
## across all three rows this ships the KNOWN fixed grid for all of them,
## not a per-row special case. Separately: every single cell's real
## content (after magenta-stripping) already touches all four edges of
## its own 256x256 cell -- the branch element runs edge-to-edge across
## each row -- so there is no dead margin for normalize_frames' own
## tight-bbox crop to actually remove; it is still used (for consistency
## with every other illustrated sheet in this codebase, and in case a
## future art revision adds real margin) but is a structural no-op on the
## current art.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

const _COLUMNS := 8
const _ROWS := 3
const _CELL_W := 256
const _CELL_H := 256

const _ROW_NAMES := ["exposed comb (growth, early)", "sealed hive (growth, late)", "harvest/destroy"]


func _init() -> void:
	var raw := Image.load_from_file("res://assets/sprites/beehive.png")
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

	print("\n-- detect_frames per row band (heuristic) --")
	for row in _ROWS:
		var top := row * _CELL_H
		var bottom := top + _CELL_H
		var detected := slicer.detect_frames(image, top, bottom, 8, 1, 0.3)
		print("row ", row, " (", _ROW_NAMES[row], "): ", detected.size(), " frames detected")
		for r in detected:
			print("  ", r)

	print("\n-- fixed-grid cell content bounds (known 256x256 cells) --")
	for row in _ROWS:
		print("row ", row, " (", _ROW_NAMES[row], "):")
		for col in _COLUMNS:
			var cell := Rect2i(col * _CELL_W, row * _CELL_H, _CELL_W, _CELL_H)
			var bounds := _painted_bounds_within(image, cell)
			print("  col ", col, " content bounds: ", bounds, " blank=", bounds.size.x <= 0)

	quit()


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _painted_bounds_within(image: Image, cell: Rect2i) -> Rect2i:
	var min_x := cell.size.x
	var min_y := cell.size.y
	var max_x := -1
	var max_y := -1
	for y in range(cell.position.y, cell.position.y + cell.size.y):
		for x in range(cell.position.x, cell.position.x + cell.size.x):
			if image.get_pixel(x, y).a > 0.1:
				var local_x := x - cell.position.x
				var local_y := y - cell.position.y
				min_x = mini(min_x, local_x)
				min_y = mini(min_y, local_y)
				max_x = maxi(max_x, local_x)
				max_y = maxi(max_y, local_y)
	if max_x < min_x:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
