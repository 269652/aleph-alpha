extends SceneTree

## Throwaway: inspect assets/sprites/buildings/stand.png's real structure --
## corner/sample pixel colors, and both near-black-gutter and magenta-
## divider content bands -- since probe_building_lifecycle_sheet.gd's
## magenta-divider scan came back oddly fragmented (alternating 4-5px slivers
## with real content bands), which usually means the true gutter colour is
## something this sheet doesn't use.


func _init() -> void:
	var image := Image.load_from_file("res://assets/sprites/buildings/stand.png")
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var w := image.get_width()
	var h := image.get_height()
	print("size: ", w, "x", h, " format: ", image.get_format())
	print("corner (0,0): ", image.get_pixel(0, 0))
	print("corner (", w - 1, ",0): ", image.get_pixel(w - 1, 0))
	print("corner (0,", h - 1, "): ", image.get_pixel(0, h - 1))
	print("center: ", image.get_pixel(w / 2, h / 2))
	print("pixel (10,10): ", image.get_pixel(10, 10))
	print("pixel (100,100): ", image.get_pixel(100, 100))
	print("pixel (627,627): ", image.get_pixel(627, 627))

	print("dark row bands: ", _content_bands(image, true, 0.06))
	print("dark column bands: ", _content_bands(image, false, 0.06))
	quit()


static func _is_dark(c: Color, max_v: float) -> bool:
	return maxf(c.r, maxf(c.g, c.b)) <= max_v


static func _content_bands(image: Image, rows: bool, max_v: float) -> Array:
	var bands: Array = []
	var length := image.get_height() if rows else image.get_width()
	var cross := image.get_width() if rows else image.get_height()
	var start := -1
	for i in length:
		var has_content := false
		for j in cross:
			var c: Color = image.get_pixel(j, i) if rows else image.get_pixel(i, j)
			if not _is_dark(c, max_v):
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
