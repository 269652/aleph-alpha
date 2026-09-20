extends SceneTree

## Does the intro's earth actually hold still, and where does it not?
##
## Reported live, after five separate stabilisation passes had already
## shipped: *"Can you properly stabilize the intro animation? The earth
## should be scaled and stabilised so there's no jitter and zooming"*.
##
## Every earlier pass measured the PIPELINE -- the crop window, the upscale
## factor, the texture filter, the display box -- and every one of them
## found and fixed something real. This measures the ART. intro.png is a
## 10x5 contact sheet drawn by an image model, not a rendered video cut into
## cells, and nothing made it draw the earth at one size in all five rows.
##
## Two rulers, because they answer different questions:
##
## - The LIT BAND: the first and last row of a frame carrying a real share
##   of its light. Cheap, and it is the same ruler
##   test_intro_splash_sheet.gd asserts on. Its two edges move together when
##   the picture is displaced and apart when it is rescaled.
## - The band AS DRAWN: the same median with this row's own correction
##   divided back out, which is the size the sheet really drew the earth at.
##   That column is the artifact itself, reported from checked-in code
##   rather than from a number in a comment.
##
## What this probe deliberately does NOT do is register one row against
## another in the frames themselves. It was tried, both as a 2-D search and
## as a 1-D fit on the row-brightness profile, and at the boundary that
## matters most -- rows 2 to 3, where the ring and the wordmark arrive --
## both rail at the end of their own range. Two frames a second apart in
## this animation are not the same picture shifted, so a fit that assumes
## they are finds nothing and says so loudly. The numbers in
## _ROW_DRAWN_SCALE came from a full 2-D similarity registration run offline
## over all seven interior columns of each boundary, where the agreement
## between columns (+/-0.005) is what says the answer is real; the two
## columns below are the consequence of it, and are what anybody can
## re-check here.

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")

const _LIT_ROW_SHARE := 0.15


func _initialize() -> void:
	var frames := IntroSplashSheet.new().generate_textures()
	if frames.is_empty():
		print("no frames -- the sheet did not load")
		quit()
		return
	var columns: int = IntroSplashSheet._COLUMN_LEFTS.size()
	print("%d frames, %d columns per contact-sheet row" % [frames.size(), columns])
	print()
	print("%-5s %-5s %-5s %-6s %-6s %s" % ["frame", "top", "bot", "height", "moved", ""])
	var bands: Array[Vector2i] = []
	for texture in frames:
		bands.append(_lit_band(texture.get_image()))
	var worst_inside := 0
	var worst_boundary := 0
	for i in bands.size():
		var moved := 0
		if i > 0:
			moved = absi(bands[i].x - bands[i - 1].x) + absi(bands[i].y - bands[i - 1].y)
			if i % columns == 0:
				worst_boundary = maxi(worst_boundary, moved)
			else:
				worst_inside = maxi(worst_inside, moved)
		print("%-5d %-5d %-5d %-6d %-6d %s" % [
			i, bands[i].x, bands[i].y, bands[i].y - bands[i].x, moved,
			"<-- crosses a contact-sheet row" if i % columns == 0 and i > 0 else "",
		])
	print()
	print("worst movement inside a row: %dpx;  across a row boundary: %dpx" % [
		worst_inside, worst_boundary,
	])
	print()
	print("%-6s %-10s %-12s %s" % ["row", "band", "as drawn", "vs row 1"])
	var rows: int = IntroSplashSheet._ROW_TOPS.size()
	var reference := 0.0
	for row in rows:
		var heights: Array[int] = []
		for column in columns:
			var band := bands[row * columns + column]
			heights.append(band.y - band.x)
		heights.sort()
		var median := float(heights[heights.size() / 2])
		var as_drawn: float = median / IntroSplashSheet._ROW_DRAWN_SCALE[row]
		if row == 1:
			reference = as_drawn
		print("  %-4d %-10.0f %-12.1f %s" % [
			row, median, as_drawn,
			"--" if row == 0 else "%.3f" % (as_drawn / reference),
		])
	print()
	print("Row 0 is the approach -- the earth is still arriving, so its band is")
	print("the starfield's and its row is not comparable with the rest.")
	quit()


## The picture's own vertical extent -- see test_intro_splash_sheet.gd's
## _lit_band, which this mirrors so the probe and the test cannot disagree
## about what they are looking at.
func _lit_band(image: Image) -> Vector2i:
	var rows := PackedFloat32Array()
	rows.resize(image.get_height())
	var brightest := 0.0
	for y in image.get_height():
		var total := 0.0
		for x in image.get_width():
			total += image.get_pixel(x, y).get_luminance()
		rows[y] = total
		brightest = maxf(brightest, total)
	var top := -1
	var bottom := -1
	for y in rows.size():
		if rows[y] > brightest * _LIT_ROW_SHARE:
			if top < 0:
				top = y
			bottom = y
	return Vector2i(top, bottom)
