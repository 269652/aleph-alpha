extends SceneTree

## Throwaway: locate the grid separator lines in the new intro.png contact
## sheet by scanning for bright pixels (the divider lines) against the
## near-black background/art.

func _init() -> void:
	var img := Image.load_from_file("res://assets/sprites/intro.png")
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("size: ", w, "x", h)

	# Scan a horizontal line through row 0's label area (should cross all
	# 20 column dividers cleanly, since that area is empty background +
	# divider lines only, no art).
	var y_probe := 5
	var cols: Array = []
	var in_line := false
	for x in w:
		var p := img.get_pixel(x, y_probe)
		var bright: bool = (p.r + p.g + p.b) > 0.5
		if bright and not in_line:
			cols.append(x)
			in_line = true
		elif not bright:
			in_line = false
	print("bright transitions at y=", y_probe, ": ", cols.size(), " -> ", cols)

	# Scan a vertical line through column 0's divider region to find rows.
	var x_probe := 3
	var rows: Array = []
	var in_line_r := false
	for y in h:
		var p := img.get_pixel(x_probe, y)
		var bright: bool = (p.r + p.g + p.b) > 0.5
		if bright and not in_line_r:
			rows.append(y)
			in_line_r = true
		elif not bright:
			in_line_r = false
	print("bright transitions at x=", x_probe, ": ", rows.size(), " -> ", rows)

	quit()
