extends RefCounted

## Cuts a composite sheet into its individual drawings.
##
## The tree art arrives as ONE image holding a canopy strip, a trunk and
## several fruit (see IllustratedTree). It is laid out for a human to read
## rather than on a fixed grid: the regions are different sizes, in different
## arrangements, and there are different numbers of them per species -- a
## cherry has two fruit frames where a walnut has four.
##
## So the drawings are FOUND rather than assumed.
##
## ## Why blobs and not gutters
##
## The obvious approach is to look for empty rows and columns and cut there.
## It does not survive this art: the autumn canopy has leaves drawn falling
## away beneath it, and those strays bridge the gap between the canopy strip
## and everything below it. No row on the walnut sheet is entirely empty, so a
## gutter search finds one region covering the whole sheet.
##
## Each drawing is instead found as a connected BLOB of content. Strays are
## naturally separate blobs, and are dropped for being far too small to be a
## drawing -- which costs the autumn canopy its falling leaves, invisible at
## the size a tree actually renders.

## What counts as empty.
##
## The sheets come with a MIX of backgrounds -- mostly transparent, but with
## semi-opaque near-white in places (the walnut sheet's corner is white at 0.9
## alpha). Treating only alpha as background misses the white entirely.
## A pixel more transparent than opaque is background.
##
## Set high on purpose. These sheets carry a faint halo around every drawing --
## about one percent of the sheet at each alpha level between clear and solid --
## and at a low threshold that web counts as content and joins every drawing on
## the sheet into a single blob. Measured across the sheets, the drawings
## themselves are at 0.9 alpha or above, so nothing real is near this line.
## A pixel must be nearly solid to count as part of a drawing.
##
## Set high on purpose. These sheets carry a soft halo around every drawing --
## roughly one percent of the sheet at each alpha level between clear and
## solid -- and at any lower threshold that web counts as content and joins
## every drawing on the sheet into one blob. Measured across the sheets, the
## drawings themselves sit at 0.9 alpha and above, so nothing real is near
## this line.
##
## Some sheets also carry a painted backdrop in their RGB channels UNDER a
## zero alpha, which is invisible in game but makes an image viewer show a
## background that is not really there. Alpha is the only channel worth
## trusting here.
const BACKGROUND_ALPHA := 0.9
const BACKGROUND_WHITE := 0.90

## How colourful a pale pixel may be and still count as background. Walnut meat
## and cherry blossom are both nearly white, and a looser rule would eat the
## fruit off the sheet.
const BACKGROUND_MAX_SATURATION := 0.08

## Blobs are found on a downsampled copy of the sheet.
##
## These sheets are around 1.5 million pixels and a flood fill in GDScript
## over all of them is slow enough to notice. The drawings are hundreds of
## pixels across, so a quarter-scale pass locates them just as reliably for a
## sixteenth of the work; the resulting boxes are trimmed against the FULL
## resolution afterwards, so nothing is lost from the edges of a drawing.
const DETECTION_STEP := 4

## A blob smaller than this fraction of the sheet is a stray mark -- a leaf
## drawn falling from a canopy -- rather than a drawing in its own right.
##
## The gap is wide: on the walnut sheet the smallest real drawing covers about
## 5% of it and a falling leaf about 0.03%, so anything in between would do.
const MIN_REGION_FRACTION := 0.004

## How close two blobs must be to count as one drawing.
##
## Zero: their boxes have to actually OVERLAP. Neighbouring drawings on these
## sheets are only about 24 pixels apart -- measured on the walnut sheet, where
## the canopies start at x=16, 396, 780 and 1160 and are around 356 wide -- so
## any tolerance worth the name swallows the gap between them and returns the
## whole sheet as one region, which is exactly what a generous value did.
##
## Overlap alone still does the job it is here for: a detached twig or leaf
## whose box falls inside a drawing's box is absorbed into it.
const MERGE_GAP_PX := 0


static func is_background(color: Color) -> bool:
	if color.a < BACKGROUND_ALPHA:
		return true
	return (
		color.r >= BACKGROUND_WHITE
		and color.g >= BACKGROUND_WHITE
		and color.b >= BACKGROUND_WHITE
		and color.s <= BACKGROUND_MAX_SATURATION
	)


## Every drawing on the sheet, in reading order: top to bottom, and left to
## right within a band.
static func regions_in(sheet: Image) -> Array[Rect2i]:
	var found: Array[Rect2i] = []
	if sheet == null or sheet.get_width() == 0:
		return found

	var boxes := _blob_boxes(sheet)
	var sheet_area := float(sheet.get_width() * sheet.get_height())
	boxes = _merge_touching(boxes, MERGE_GAP_PX)

	for box in boxes:
		if float(box.size.x * box.size.y) / sheet_area < MIN_REGION_FRACTION:
			continue
		var trimmed := _trim(sheet, box)
		if trimmed.size.x > 0 and trimmed.size.y > 0:
			found.append(trimmed)
	found.sort_custom(_reading_order)
	return found


## Bounding boxes of the connected runs of content, found at DETECTION_STEP
## resolution and scaled back up.
static func _blob_boxes(sheet: Image) -> Array[Rect2i]:
	var wide := sheet.get_width() / DETECTION_STEP
	var high := sheet.get_height() / DETECTION_STEP
	var filled := {}
	for y in high:
		for x in wide:
			if not is_background(sheet.get_pixel(x * DETECTION_STEP, y * DETECTION_STEP)):
				filled[Vector2i(x, y)] = true

	var boxes: Array[Rect2i] = []
	var visited := {}
	for start in filled:
		if visited.has(start):
			continue
		# Flood the blob this pixel belongs to, tracking its extent as we go.
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		var left: int = start.x
		var right: int = start.x
		var top: int = start.y
		var bottom: int = start.y
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			left = mini(left, at.x)
			right = maxi(right, at.x)
			top = mini(top, at.y)
			bottom = maxi(bottom, at.y)
			# Eight-connected, so a drawing joined only corner-to-corner is
			# still one blob.
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var next := Vector2i(at.x + dx, at.y + dy)
					if visited.has(next) or not filled.has(next):
						continue
					visited[next] = true
					queue.append(next)
		boxes.append(Rect2i(
			left * DETECTION_STEP,
			top * DETECTION_STEP,
			(right - left + 1) * DETECTION_STEP,
			(bottom - top + 1) * DETECTION_STEP
		))
	return boxes


## Joins boxes that overlap or sit within `gap` of each other, repeatedly,
## until nothing more merges -- one merge can bring two others into range.
static func _merge_touching(boxes: Array[Rect2i], gap: int) -> Array[Rect2i]:
	var merged := true
	var working := boxes.duplicate()
	while merged:
		merged = false
		var result: Array[Rect2i] = []
		for box in working:
			var joined := false
			for index in result.size():
				if result[index].grow(gap).intersects(box.grow(gap)):
					result[index] = result[index].merge(box)
					joined = true
					merged = true
					break
			if not joined:
				result.append(box)
		working = result
	var typed: Array[Rect2i] = []
	for box in working:
		typed.append(box)
	return typed


## Shrinks a region to its content at full resolution, so a drawing's box is
## the drawing and not whatever margin the coarse pass left around it.
static func _trim(sheet: Image, area: Rect2i) -> Rect2i:
	var clipped := area.intersection(Rect2i(0, 0, sheet.get_width(), sheet.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return Rect2i(area.position, Vector2i.ZERO)
	var left: int = clipped.position.x + clipped.size.x
	var right: int = clipped.position.x - 1
	var top: int = clipped.position.y + clipped.size.y
	var bottom: int = clipped.position.y - 1
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x):
			if is_background(sheet.get_pixel(x, y)):
				continue
			left = mini(left, x)
			right = maxi(right, x)
			top = mini(top, y)
			bottom = maxi(bottom, y)
	if right < left or bottom < top:
		return Rect2i(clipped.position, Vector2i.ZERO)
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


## Reading order: down the page, and left to right within a band. Two regions
## count as sharing a band when they overlap vertically at all, which is how a
## person reads a row of drawings that are not perfectly aligned.
static func _reading_order(a: Rect2i, b: Rect2i) -> bool:
	var shares_band: bool = (
		a.position.y < b.position.y + b.size.y and b.position.y < a.position.y + a.size.y
	)
	if shares_band:
		return a.position.x < b.position.x
	return a.position.y < b.position.y


## ## Sheets with an opaque background
##
## Three of these sheets arrive with real transparency and two do not: the
## pine and hazelnut sheets are drawn on solid white. Cut out as-is, those
## trees composite with a white box around them.
##
## Colour alone cannot separate the two. The snow on the winter pine measures
## as neutral white at 0.957 and the background at 0.992 -- the same hue, the
## same zero saturation, a hair apart in brightness. Keying every white pixel
## erases the snow.
##
## So the background is found by REACHABILITY instead: flooding inward from
## the edges of the cut-out region marks what is connected to the outside.
## Anything enclosed by the drawing stays, whatever colour it is.
##
## The tolerance has to cover a CHECKERBOARD. These sheets do not merely have
## a white background -- they have a transparency checkerboard painted into
## them as pixels, alternating roughly 0.99 and 0.96 grey. A tolerance tight
## enough to tell those two apart keys only half of it and leaves the drawing
## sitting on a dithered grid.
##
## Known limit: the snow on the winter pine measures in that same range, so it
## goes with the checkerboard. Nothing here can separate them -- they are the
## same colour -- and the real fix is exporting that sheet with real alpha, as
## the cherry, walnut and acorn sheets already have.
const KEY_TOLERANCE := 0.06


## Whether this sheet needs its background keyed out -- true when its corner is
## opaque, which no sheet with real transparency has.
static func needs_keying(sheet: Image) -> bool:
	return sheet != null and sheet.get_width() > 0 and sheet.get_pixel(0, 0).a > 0.9


## A region cut from `sheet` with any background connected to its edges made
## transparent.
static func cut_out(sheet: Image, region: Rect2i) -> Image:
	var piece := sheet.get_region(region)
	if not needs_keying(sheet):
		return piece
	var key := sheet.get_pixel(0, 0)
	var wide := piece.get_width()
	var high := piece.get_height()
	var outside := {}
	var queue: Array[Vector2i] = []
	for x in wide:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, high - 1))
	for y in high:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(wide - 1, y))
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		if at.x < 0 or at.x >= wide or at.y < 0 or at.y >= high or outside.has(at):
			continue
		var pixel := piece.get_pixel(at.x, at.y)
		if absf(pixel.r - key.r) > KEY_TOLERANCE \
			or absf(pixel.g - key.g) > KEY_TOLERANCE \
			or absf(pixel.b - key.b) > KEY_TOLERANCE:
			continue
		outside[at] = true
		queue.append(at + Vector2i(1, 0))
		queue.append(at + Vector2i(-1, 0))
		queue.append(at + Vector2i(0, 1))
		queue.append(at + Vector2i(0, -1))
	for at in outside:
		piece.set_pixel(at.x, at.y, Color(0, 0, 0, 0))
	return piece
