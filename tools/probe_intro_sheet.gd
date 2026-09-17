extends SceneTree

## Measurement tool for assets/sprites/intro.png -- run it after the art is
## replaced, and pin what it prints into IntroSplashSheet's own
## _COLUMN_WINDOW_LEFTS/_ROW_WINDOW_TOPS/_FRAME_WIDTH/_FRAME_HEIGHT:
##
##   <godot> --path . --headless -s tools/probe_intro_sheet.gd
##
## REWRITTEN 2026-09-17 (see docs/concept/intro_splash.md's "Re-measuring
## again: a contact sheet, not a sprite sheet"). The previous version looked
## for rows that were entirely MAGENTA, because every illustrated sheet in
## this codebase had a magenta background with real gutters keyed out of it.
## The replacement sheet has no magenta at all: it is a contact sheet on
## opaque black, with the export tool's own light-grey GRID LINES drawn
## between cells. The old probe found no gutters, reported the whole image
## as one row, and was useless for exactly the job it exists to do.
##
## So this measures the grid LINES instead -- runs of near-neutral, clearly
## lit pixels spanning most of the sheet, which real frame art (near-black
## space, or saturated blue/gold globe) never produces. The same rule
## test_intro_splash_sheet.gd's own _grid_line_runs uses, so the probe and
## the regression test can never disagree about where the grid is.

## A line pixel is brighter than this...
const _LINE_MIN_BRIGHTNESS := 0.18
## ...and this close to neutral grey (real art here is saturated or black).
const _LINE_MAX_SATURATION := 0.08
## ...and this share of a whole row/column has to qualify for it to BE a line.
const _LINE_MIN_COVERAGE := 0.45

## Where the export draws each cell's timestamp, as a fraction of a cell --
## used only to report the label's own rows, which is what tells you whether
## the pinned window tops line the six rows up with each other (see that
## test's own doc comment: the label is this sheet's alignment instrument).
const _LABEL_SCAN_ROWS := 30
const _LABEL_SCAN_LEFT := 4
const _LABEL_SCAN_RIGHT := 48
const _LABEL_MIN_INK := 4


func _init() -> void:
	var image := Image.load_from_file("res://assets/sprites/intro.png")
	if image == null:
		print("no sheet at res://assets/sprites/intro.png")
		quit()
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	print("sheet: %dx%d" % [image.get_width(), image.get_height()])

	var column_runs := _grid_line_runs(image, false)
	var row_runs := _grid_line_runs(image, true)
	print("grid: %d columns, %d rows" % [column_runs.size() + 1, row_runs.size() + 1])

	var columns := _interiors_between(column_runs, image.get_width())
	var rows := _interiors_between(row_runs, image.get_height())
	print("column interiors (left, width): %s" % str(columns))
	print("row interiors (top, height):    %s" % str(rows))

	var frame_width := _smallest(columns)
	var frame_height := _smallest(rows)
	print("_FRAME_WIDTH  := %d" % frame_width)
	print("_FRAME_HEIGHT := %d" % frame_height)

	# Windows are CENTRED horizontally in their cell (the art sits at the
	# cell's middle and the cells differ in width) and TOP-anchored
	# vertically (the art is anchored to the cell top; a trailing black
	# margin under the last row would otherwise push it down).
	var lefts: Array = []
	for interior in columns:
		lefts.append((interior as Vector2i).x + ((interior as Vector2i).y - frame_width) / 2)
	var tops: Array = []
	for interior in rows:
		tops.append((interior as Vector2i).x)
	print("_COLUMN_WINDOW_LEFTS := %s" % str(lefts))
	print("_ROW_WINDOW_TOPS     := %s  (before label alignment, see below)" % str(tops))

	# The alignment check that actually matters: the burned-in timestamp sits
	# at a constant offset below every cell's own top, so any row whose label
	# lands on a different frame row than the others needs its top nudged by
	# the difference. Row 0 typically does, because it has no grid line above
	# it -- see the concept doc.
	print("label first-ink row per sheet row (all six should match):")
	for row in rows.size():
		var top: int = tops[row]
		var first := -1
		for y in _LABEL_SCAN_ROWS:
			var found := false
			for interior in columns:
				var ink := 0
				for x in range(_LABEL_SCAN_LEFT, _LABEL_SCAN_RIGHT):
					var c := image.get_pixel((interior as Vector2i).x + x, top + y)
					if minf(c.r, minf(c.g, c.b)) > 0.60:
						ink += 1
				if ink >= _LABEL_MIN_INK:
					found = true
					break
			if found:
				first = y
				break
		print("  row %d: %d" % [row, first])
	quit()


## Runs of grid line, as [first, last] index pairs.
static func _grid_line_runs(image: Image, horizontal: bool) -> Array:
	var width := image.get_width()
	var height := image.get_height()
	var outer: int = height if horizontal else width
	var inner: int = width if horizontal else height
	var runs: Array = []
	var start := -1
	var previous := -99
	for i in outer:
		var hits := 0
		for j in range(0, inner, 2):
			var c: Color = image.get_pixel(j, i) if horizontal else image.get_pixel(i, j)
			var brightest: float = maxf(c.r, maxf(c.g, c.b))
			var darkest: float = minf(c.r, minf(c.g, c.b))
			if brightest > _LINE_MIN_BRIGHTNESS and (brightest - darkest) < _LINE_MAX_SATURATION:
				hits += 1
		if float(hits) / float(inner / 2) > _LINE_MIN_COVERAGE:
			if i != previous + 1:
				if start >= 0:
					runs.append([start, previous])
				start = i
			previous = i
	if start >= 0:
		runs.append([start, previous])
	return runs


## (start, length) of every span between consecutive grid-line runs,
## including the ones before the first line and after the last.
static func _interiors_between(runs: Array, extent: int) -> Array[Vector2i]:
	var interiors: Array[Vector2i] = []
	var cursor := 0
	for run in runs:
		interiors.append(Vector2i(cursor, int(run[0]) - cursor))
		cursor = int(run[1]) + 1
	interiors.append(Vector2i(cursor, extent - cursor))
	return interiors


static func _smallest(interiors: Array[Vector2i]) -> int:
	var smallest := 1 << 30
	for interior in interiors:
		smallest = mini(smallest, interior.y)
	return smallest
