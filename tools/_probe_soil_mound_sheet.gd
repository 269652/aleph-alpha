extends SceneTree

## Throwaway: measure assets/sprites/terrain/soil_mound.png's real row/column
## grid bands (see tools/probe_intro_sheet.gd's own "measure before pinning
## constants" convention) so IllustratedSoilMoundSprite's _ROW_BANDS/
## _COLUMN_BANDS (or magenta-key row scan) can be wired against real numbers
## instead of assumed ones.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")

const _MAGENTA_RED_MIN := 0.55
const _MAGENTA_BLUE_MIN := 0.55


func _init() -> void:
	var raw := Image.load_from_file("res://assets/sprites/terrain/soil_mound.png")
	print("sheet size: ", raw.get_width(), "x", raw.get_height())
	print("format: ", raw.get_format())
	print("corner pixel (0,0): ", raw.get_pixel(0, 0))
	print("pixel (5,5): ", raw.get_pixel(5, 5))
	var w := raw.get_width()
	var h := raw.get_height()
	print("pixel center: ", raw.get_pixel(w / 2, h / 2))
	print("pixel top-mid: ", raw.get_pixel(w / 2, 2))

	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	# Try alpha-based row band detection first (transparent/black background).
	var alpha_bands := _detect_row_bands_alpha(image)
	print("alpha-based row bands (", alpha_bands.size(), "): ", alpha_bands)

	var slicer := SpriteSheetSlicer.new()
	for row_index in alpha_bands.size():
		var band: Vector2i = alpha_bands[row_index]
		var frames := slicer.detect_frames(image, band.x, band.y)
		print("row ", row_index, " y=[", band.x, ",", band.y, "): ", frames.size(), " frames -> ", frames)

	quit()


static func _is_content_alpha(color: Color) -> bool:
	return color.a > 0.05 or (color.r + color.g + color.b) > 0.15


static func _detect_row_bands_alpha(image: Image) -> Array:
	var bands: Array = []
	var start := -1
	for y in image.get_height():
		var has_content := false
		for x in image.get_width():
			if _is_content_alpha(image.get_pixel(x, y)):
				has_content = true
				break
		if has_content and start == -1:
			start = y
		elif not has_content and start != -1:
			bands.append(Vector2i(start, y))
			start = -1
	if start != -1:
		bands.append(Vector2i(start, image.get_height()))
	return bands
