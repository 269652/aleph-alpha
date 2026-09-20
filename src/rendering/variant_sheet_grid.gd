extends RefCounted

## Where a grid sheet's cells really are (docs/concept/building.md,
## "Building variant sheets").
##
## Dividing a sheet evenly ASSUMES the art was laid out on an exact pitch
## with no margin. Hand-drawn sheets are not: `house_1.png`'s own rows sit
## roughly 213px apart inside a 1122px image with 45px of blank at the
## bottom, so an even fifth-of-the-height cut lands 8px low on the first
## boundary and 44px low on the last -- slicing the chimney off one cottage
## and gluing a strip of the next one's grass along the top of another.
## Measured, not assumed: `tools/probe_house_variant_sheet.gd` reports how
## much art each cut line passes through.
##
## So the cuts are found in the sheet's own background GUTTERS -- the runs
## of near-background rows or columns between one building and the next --
## and fall back to even division whenever a sheet genuinely has none, or
## has a different number than the caller expected. Detection is an
## improvement on even division, never a precondition for slicing: a sheet
## this cannot read still cuts, just evenly.
##
## The same auto-detected-bands idea `IllustratedAnimalSprite` already uses
## for its multi-row animal sheets, generalized to both axes and to a dark
## background.
##
## Pure and static -- an Image in, Rect2i out, no state, no engine
## dependency beyond Image itself.

## How light a pixel must be to count as ART rather than as the sheet's own
## dark background. Matches IllustratedStructureSprite's own black key
## (_BLACK_MAX, 0.05) with a little headroom, so a pixel this module calls
## background is one the frame cut would key out anyway.
const BACKGROUND_MAX := 0.08

## What share of a line may be art while the line still counts as a gutter.
## Not zero: a stray antialiased pixel from a neighbouring cell's shadow
## must not stop a real gutter from being recognised.
const GUTTER_ART_TOLERANCE := 0.01

## A band thinner than this is a speck, not a building -- so a few bright
## pixels in the margin can never be mistaken for a row of art.
const MIN_BAND_THICKNESS := 4


## How magenta a pixel must be to read as one of a sheet's own DIVIDER
## LINES rather than as art -- the same thresholds every illustrated sheet
## in this codebase already keys on (IllustratedStructureSprite,
## IllustratedWormSprite and the rest), reused rather than re-measured.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15

## What share of a line must be magenta before it counts as a divider. Not
## 1.0: a real divider is drawn over, and antialiased against, the art on
## both sides of it, so a few pixels along its length are never quite
## magenta.
const DIVIDER_LINE_SHARE := 0.6


## How light a pixel must be, on every channel, to read as one of the thin
## near-white RULE LINES the production sheets draw between their cells and
## around the canvas -- measured on warehouse.png, whose line reads
## (0.992, 0.969, 0.996). The same 0.85 floor the magenta key already uses,
## applied to all three channels instead of two.
const RULE_LINE_MIN := 0.85

## What share of a line must be real art before the line counts as content
## rather than as background, margin or rule line.
##
## Measured across every sheet on the fixed-grid contract: at 2% all five
## (warehouse, sawmill, city_hall, farmhouse, blacksmith) resolve to
## exactly their 5 drawn rows. At 1% city_hall's own drop shadow splits
## into 7 and farmhouse into 6; at 5% a faint roofline is lost and sawmill
## splits into 6. Pinned by
## test_content_bands_reads_five_rows_from_every_fixed_grid_sheet.
const CONTENT_ART_SHARE := 0.02


## Every band of real ART along one axis: the runs of lines that are
## neither the sheet's own dark cell background, nor its magenta margin,
## nor one of its light rule lines.
##
## This is the finder for the sheets whose cells sit on an exact COLUMN
## pitch but on irregular ROWS -- warehouse.png's row boundaries are at
## 188, 376, 566 and 786, so no single pitch lands on them. row_bands
## cannot read them (it looks for dark gutters, and the margin here is
## magenta) and neither can art_bands (it looks for magenta divider lines,
## and the line here is near-white), so this asks what is art directly
## instead of what the gap is made of.
##
## Falls back to even division when the sheet yields a different number of
## bands than asked for -- the same "still cuts, just evenly" contract the
## other finders keep.
static func content_bands(image: Image, count: int, horizontal: bool) -> Array:
	if count <= 0:
		return []
	var length := image.get_height() if horizontal else image.get_width()
	var across := image.get_width() if horizontal else image.get_height()
	if length <= 0 or across <= 0:
		return _even_bands(length, count)

	var tolerance := int(float(across) * CONTENT_ART_SHARE)
	var found: Array = []
	var start := -1
	for i in length:
		var art := 0
		for j in across:
			var pixel := image.get_pixel(j, i) if horizontal else image.get_pixel(i, j)
			if _is_art(pixel):
				art += 1
				if art > tolerance:
					break
		var is_content := art > tolerance
		if is_content and start < 0:
			start = i
		elif not is_content and start >= 0:
			if i - start >= MIN_BAND_THICKNESS:
				found.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0 and length - start >= MIN_BAND_THICKNESS:
		found.append(Vector2i(start, length - 1))

	return found if found.size() == count else _even_bands(length, count)


## Neither background, margin nor rule line -- so, a pixel of the drawing.
static func _is_art(color: Color) -> bool:
	if _is_magenta(color):
		return false
	if color.r <= BACKGROUND_MAX and color.g <= BACKGROUND_MAX and color.b <= BACKGROUND_MAX:
		return false
	return not (
		color.r >= RULE_LINE_MIN and color.g >= RULE_LINE_MIN and color.b >= RULE_LINE_MIN
	)


## Every band of non-divider content between a sheet's own MAGENTA DIVIDER
## LINES, along one axis. Unlike row_bands/column_bands below, which look
## for DARK gutters, this reads the sheets that draw a real line between
## one cell and the next (house_1_1.png .. house_1_5.png, well.png).
##
## Returns everything it finds, labels and margins included -- deciding
## which of those bands are art is art_bands' job, and keeping the two
## apart is what lets a probe report the raw truth
## (tools/probe_building_lifecycle_sheet.gd).
static func divider_bands(image: Image, horizontal: bool) -> Array:
	var length := image.get_height() if horizontal else image.get_width()
	var across := image.get_width() if horizontal else image.get_height()
	if length <= 0 or across <= 0:
		return []
	var bands: Array = []
	var start := -1
	for i in length:
		var magenta := 0
		for j in across:
			if _is_magenta(image.get_pixel(j, i) if horizontal else image.get_pixel(i, j)):
				magenta += 1
		var is_divider: bool = float(magenta) / float(across) >= DIVIDER_LINE_SHARE
		if not is_divider and start < 0:
			start = i
		elif is_divider and start >= 0:
			if i - start >= MIN_BAND_THICKNESS:
				bands.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0 and length - start >= MIN_BAND_THICKNESS:
		bands.append(Vector2i(start, length - 1))
	return bands


## The `count` divider bands that actually hold the ART grid: the
## consecutive run whose cells are most ALIKE in size.
##
## A real sheet carries bands that are not art and must not be cut into it
## -- the house sheets have a column-label row across the top, a row-label
## gutter down the left and a blank margin on the right, each a genuine
## divider-separated band (measured with
## tools/probe_building_lifecycle_sheet.gd: rows 39, 77, 84, 101, 103, 99,
## 101, 95, 97, 89, 105; columns 109, 168, 168, 167, 168, 168, 169, 169,
## 169, 46). Art cells are drawn on a pitch and so are near-identical in
## size; a label or a margin is conspicuously not. Picking the least-varied
## run finds the art window without anyone writing down where the labels
## happen to be on one particular sheet.
##
## Falls back to even division when the sheet has fewer bands than asked
## for -- the same "still cuts, just evenly" contract _bands already keeps.
static func art_bands(image: Image, count: int, horizontal: bool) -> Array:
	if count <= 0:
		return []
	var length := image.get_height() if horizontal else image.get_width()
	var bands := divider_bands(image, horizontal)
	if bands.size() < count:
		return _even_bands(length, count)
	var best_start := 0
	var best_spread := INF
	for start in range(0, bands.size() - count + 1):
		var spread := _size_spread(bands, start, count)
		if spread < best_spread:
			best_spread = spread
			best_start = start
	return bands.slice(best_start, best_start + count)


## The pixel rect of cell (row, column) in a `columns` x `rows` grid whose
## cells are separated by magenta divider lines.
static func divider_cell_rect(image: Image, columns: int, rows: int, row: int, column: int) -> Rect2i:
	var row_band: Vector2i = art_bands(image, rows, true)[clampi(row, 0, rows - 1)]
	var column_band: Vector2i = art_bands(image, columns, false)[clampi(column, 0, columns - 1)]
	return Rect2i(
		column_band.x, row_band.x,
		column_band.y - column_band.x + 1, row_band.y - row_band.x + 1
	)


## How much the sizes of `count` bands starting at `start` differ, as a
## share of the largest -- scale-free, so it compares a run of 100px cells
## against a run of 200px ones on the same terms.
static func _size_spread(bands: Array, start: int, count: int) -> float:
	var smallest := INF
	var largest := 0.0
	for i in range(start, start + count):
		var band: Vector2i = bands[i]
		var size := float(band.y - band.x + 1)
		smallest = minf(smallest, size)
		largest = maxf(largest, size)
	if largest <= 0.0:
		return INF
	return (largest - smallest) / largest


## The sheets' own chroma-key background. Public because a caller reading
## a cell has to agree with this module about what is background and what
## is drawing -- IllustratedStructureSprite._is_rule_line_row does -- and
## two independent copies of one key is how a fringe survives a crop.
static func is_background(color: Color) -> bool:
	return _is_magenta(color)


static func _is_magenta(color: Color) -> bool:
	return (
		color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN
		and color.g <= _MAGENTA_GREEN_MAX
	)


## The `count` content bands running down `image`, as [start_y, end_y]
## inclusive Vector2i pairs, top to bottom. Falls back to an even division
## when the sheet has no readable gutters or a different number of bands.
static func row_bands(image: Image, count: int) -> Array:
	return _bands(image, count, true)


## The same along the other axis: `count` content bands running across.
static func column_bands(image: Image, count: int) -> Array:
	return _bands(image, count, false)


## The pixel rect of cell (row, column) in a `columns` x `rows` grid,
## combining both axes' detected bands.
static func cell_rect(image: Image, columns: int, rows: int, row: int, column: int) -> Rect2i:
	var row_band: Vector2i = row_bands(image, rows)[clampi(row, 0, rows - 1)]
	var column_band: Vector2i = column_bands(image, columns)[clampi(column, 0, columns - 1)]
	return Rect2i(
		column_band.x, row_band.x,
		column_band.y - column_band.x + 1, row_band.y - row_band.x + 1
	)


static func _bands(image: Image, count: int, horizontal: bool) -> Array:
	if count <= 0:
		return []
	var length := image.get_height() if horizontal else image.get_width()
	var across := image.get_width() if horizontal else image.get_height()
	if length <= 0 or across <= 0:
		return _even_bands(length, count)

	var tolerance := int(float(across) * GUTTER_ART_TOLERANCE)
	var found: Array = []
	var start := -1
	for i in length:
		var art := 0
		for j in across:
			var pixel := image.get_pixel(j, i) if horizontal else image.get_pixel(i, j)
			if pixel.r > BACKGROUND_MAX or pixel.g > BACKGROUND_MAX or pixel.b > BACKGROUND_MAX:
				art += 1
				if art > tolerance:
					break
		var is_content := art > tolerance
		if is_content and start < 0:
			start = i
		elif not is_content and start >= 0:
			if i - start >= MIN_BAND_THICKNESS:
				found.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0 and length - start >= MIN_BAND_THICKNESS:
		found.append(Vector2i(start, length - 1))

	# A different number of bands than asked for is not a licence to guess
	# which ones to merge or split -- an even division is the honest answer.
	return found if found.size() == count else _even_bands(length, count)


## Cumulative rounding, the same shape IllustratedStructureSprite._cell_rect
## uses, so a non-evenly-divisible length loses no row to truncation.
static func _even_bands(length: int, count: int) -> Array:
	var bands: Array = []
	for i in count:
		var start := int(round(float(length) * i / count))
		var end := int(round(float(length) * (i + 1) / count)) - 1
		bands.append(Vector2i(start, maxi(end, start)))
	return bands
