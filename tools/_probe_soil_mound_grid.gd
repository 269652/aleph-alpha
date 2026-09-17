extends SceneTree

## Throwaway: measure assets/sprites/terrain/soil_mound.png's real row/column
## content bands using a brightness threshold (its gutters are near-black,
## not magenta -- see IllustratedTerrainSprite's "soil" entry for the same
## quirk on the same 1254x1254 template).

const _DARK_MAX := 0.06


func _init() -> void:
	var image := Image.load_from_file("res://assets/sprites/terrain/soil_mound.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	print("sheet size: ", image.get_width(), "x", image.get_height())
	print("row bands: ", _content_bands(image, true))
	print("column bands: ", _content_bands(image, false))
	quit()


static func _is_dark(c: Color) -> bool:
	return maxf(c.r, maxf(c.g, c.b)) <= _DARK_MAX


static func _content_bands(image: Image, rows: bool) -> Array:
	var bands: Array = []
	var length := image.get_height() if rows else image.get_width()
	var cross := image.get_width() if rows else image.get_height()
	var start := -1
	for i in length:
		var has_content := false
		for j in cross:
			var c: Color = image.get_pixel(j, i) if rows else image.get_pixel(i, j)
			if not _is_dark(c):
				has_content = true
				break
		if has_content and start == -1:
			start = i
		elif not has_content and start != -1:
			bands.append(Vector2i(start, i))
			start = -1
	if start != -1:
		bands.append(Vector2i(start, length))
	return bands
