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
