extends SceneTree

## Measures the intro CONTACT SHEET's real grid from the file on disk.
##
## The 2026-09-17 replacement is 20 columns x 6 rows of frames drawn on
## black, separated by thin LIGHT grid lines, with a white timestamp caption
## ("0.00s" ... "4.96s") printed inside the top of every cell. There are no
## magenta dividers and no fully-background lines, so the detectors written
## for the old art see one giant band.
##
## The grid lines are the one thing that is bright everywhere, including
## across the near-black first row, so they are what this measures: a line
## whose mean brightness stands well above the sheet's own is a divider.
## Captions are found the same honest way -- the rows inside a cell that
## carry near-white pixels.
##
## Reads the raw file on purpose: an imported texture can be stale, which is
## exactly how a swapped sheet got past the guard test once.

const IntroSplashSheet = preload("res://src/rendering/intro_splash_sheet.gd")


## A grid line is drawn across EVERYTHING, so every pixel along it is light.
## Content lines always have some black in them (between globes, in a
## corner), so the MINIMUM along the line separates the two cleanly where a
## mean cannot: by the end of the animation the globe itself is brighter than
## the dividers.
static func _min_brightness(image: Image, index: int, along_rows: bool) -> float:
	var inner: int = image.get_width() if along_rows else image.get_height()
	var lowest := 1.0
	for j in inner:
		var x: int = j if along_rows else index
		var y: int = index if along_rows else j
		var pixel := image.get_pixel(x, y)
		lowest = minf(lowest, maxf(pixel.r, maxf(pixel.g, pixel.b)))
	return lowest


## Indices whose darkest pixel is still light: the grid lines.
static func dividers(image: Image, along_rows: bool, floor_brightness: float) -> Array:
	var outer: int = image.get_height() if along_rows else image.get_width()
	var found: Array = []
	for i in outer:
		if _min_brightness(image, i, along_rows) >= floor_brightness:
			found.append(i)
	return found


static func _caption_bottom(image: Image, cell: Rect2i) -> int:
	var lowest := -1
	for y in range(cell.position.y, cell.end.y):
		for x in range(cell.position.x, cell.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.75 and pixel.g > 0.75 and pixel.b > 0.75:
				lowest = y
				break
	return lowest


## Consecutive runs of divider indices collapsed to one boundary each --
## a drawn line is 1-3px wide and what the crop wants is where it sits.
## Where each cell BEGINS: the sheet's own edge, then the first pixel after
## each divider run ends. Not the run's centre -- a drawn line is 1-3px wide
## and a crop that starts inside it carries the line's own ink in its first
## column, which is what "still not correct" looked like once before.
static func _cell_starts(indices: Array) -> Array:
	var starts: Array = [0]
	var previous := -99
	var run_start := -1
	for i in indices:
		if i != previous + 1 and run_start >= 0:
			starts.append(previous + 1)
		if i != previous + 1:
			run_start = i
		previous = i
	if run_start >= 0:
		starts.append(previous + 1)
	return starts


func _init() -> void:
	# Read through a buffer, not Image.load_from_file: that warns on a
	# res:// path ("this will not work on export") and an engine warning
	# fails a GUT run, which the guard test needs to avoid. This is still
	# the file on disk, not the import cache.
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/sprites/intro.png"))
	print("sheet: %dx%d" % [image.get_width(), image.get_height()])

	var columns := _cell_starts(dividers(image, false, IntroSplashSheet.DIVIDER_BRIGHTNESS))
	var rows := _cell_starts(dividers(image, true, IntroSplashSheet.DIVIDER_BRIGHTNESS))
	print("cell lefts (%d): %s" % [columns.size(), columns])
	print("cell tops (%d): %s" % [rows.size(), rows])
	var narrowest := image.get_width()
	for i in columns.size():
		var next: int = int(columns[i + 1]) - 1 if i + 1 < columns.size() else image.get_width()
		narrowest = mini(narrowest, next - int(columns[i]))
	var shortest := image.get_height()
	for i in rows.size():
		var next: int = int(rows[i + 1]) - 1 if i + 1 < rows.size() else image.get_height()
		shortest = mini(shortest, next - int(rows[i]))
	print("narrowest cell %d  shortest cell %d" % [narrowest, shortest])
	var lefts: Array = columns
	var tops: Array = rows

	# The caption band, measured INSIDE a cell (never across a divider, which
	# is itself light): the timestamp occupies rows 11..21 of every cell.
	# 28 clears it with margin and still sits well above the earliest art.
	var caption := 28
	# Where the GLOBE sits in each cell -- the question the last two passes
	# got wrong. Its disc, not a brightness centroid: the content itself
	# changes across the sheet (a light streak sweeps, a wordmark appears),
	# so a centroid tracks the animation rather than the framing. Measured
	# down the middle of the cell, where the disc is, as an offset from the
	# cell's own top.
	for row in tops.size():
		var top: int = int(tops[row])
		var bottom: int = (int(rows[row]) if row < rows.size() else image.get_height())
		var extents: Array = []
		for column in [1, 6, 12, 19]:
			var left: int = int(lefts[column])
			var first := -1
			var last := -1
			for y in range(top + caption, bottom):
				for x in range(left + 20, left + 60):
					if maxf(image.get_pixel(x, y).r, image.get_pixel(x, y).b) > 0.20:
						if first < 0:
							first = y - top
						last = y - top
						break
			extents.append("c%d:%d..%d" % [column, first, last])
		print("row %d (cell %dpx tall): disc rows from cell top -- %s" % [
			row, bottom - top, " ".join(extents)
		])
	print("column divider indices: %s" % [dividers(image, false, IntroSplashSheet.DIVIDER_BRIGHTNESS)])
	print("row divider indices: %s" % [dividers(image, true, IntroSplashSheet.DIVIDER_BRIGHTNESS)])
	quit()


static func _narrowest(starts: Array, extent: int) -> int:
	var smallest := extent
	for i in starts.size():
		var next: int = int(starts[i + 1]) - 1 if i + 1 < starts.size() else extent
		smallest = mini(smallest, next - int(starts[i]))
	return smallest
