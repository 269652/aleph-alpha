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


## ## Two more bugs found keying acorn and apple
##
## `needs_keying` sheets are the exception, not the rule -- of the six
## species, only acorn and apple currently trip it, pine/hazelnut/walnut/
## cherry all having been re-exported with real alpha since the paragraph
## above was written (measured: their corner pixels read alpha 0, not the
## checkerboard's 0.96-0.99 opaque grey it describes). That made the two
## remaining opaque sheets easy to under-test -- the reachability keying
## above looked sound and had real doc comments explaining its one known
## limit, but nobody had measured it actually removing a pixel on either of
## them.
##
## It wasn't. `sheet.get_region()` returns a piece in the SHEET's own format,
## and both acorn's and apple's composite sheets decode as FORMAT_RGB8 --
## no alpha channel at all. `Image.set_pixel` on a format with no alpha
## channel silently keeps alpha at 1: the flood fill above ran, correctly
## found the background, and then every `set_pixel(..., Color(0,0,0,0))`
## did nothing. Measured directly on acorn's bare-winter frame: 92140 of
## 92140 pixels stayed opaque after cut_out, identical to before it ran, on
## a frame visibly half background when viewed. Converting the piece to
## FORMAT_RGBA8 before the fill fixes this for every needs_keying sheet;
## the fill's own logic did not need to change.
##
## That fix alone still was not enough for the bare-winter frame specifically.
## A bare tree's real branches leave gaps between them that do not reach the
## crop's own edge -- pockets of background fully enclosed by the drawing,
## which reachability protects on purpose (see above). Measured on acorn's
## winter frame: even with alpha writes actually working, edge reachability
## alone only reaches 53578 of the 59483 background pixels in the box,
## leaving enough opaque residue that the frame still measured denser than
## its own summer canopy's sampled pixel count -- backwards for a species
## that is supposed to go bare.
##
## Reachability cannot be dropped everywhere -- that is exactly the
## checkerboard-vs-snow problem the paragraph above exists to avoid, and
## acorn's own sheet has the same shape of case: its fifth, snow-covered
## canopy frame carries real near-white content that colour alone cannot
## tell from background (measured: 17163 of its 111000 pixels are
## background-coloured but NOT edge-reachable -- exactly the enclosed snow
## clumps reachability is protecting). But the bare-winter frame is the one
## canopy role that never draws anything pale by design -- no leaf, no
## blossom, no snow, just brown branches -- so `cut_out` takes an
## `aggressive` flag, used ONLY for that one frame by IllustratedTree, that
## keys every background-COLOURED pixel in the crop regardless of whether
## the fill ever reached it. Every other frame -- the other three seasons,
## the snow frame, the trunk, every fruit stage -- keeps the reachability-
## only behaviour unchanged, so a real pale drawing anywhere else on the
## sheet is exactly as protected as it always was.
##
## Even colour-based removal was not quite enough on its own. These sheets
## are anti-aliased against their opaque background, so every branch edge
## wears a thin halo of blended pixels that are near-white but not quite --
## measured on acorn's winter frame, 2228 of the pixels `is_background`
## leaves behind sit at luminance above 0.6 with saturation below 0.2, a
## band real branch colour does not otherwise occupy at that combination
## (real bark this pale on this sheet always carries more colour than
## that -- measured saturation above 0.2 whenever luminance is, up to 0.64
## at the darker end). A bare tree's branch network has a lot of edge
## length relative to its area, so this thin halo added up: acorn's winter
## frame still out-massed its own summer canopy after colour-only removal
## (32657 opaque pixels against summer's 64946, a ratio of 0.50 where a
## species that actually goes bare measures 0.42-0.45).
##
## So `aggressive` mode also ERODES the halo, one ring at a time: any pixel
## in that luminance/saturation band that touches an already-keyed pixel is
## keyed too, repeated until a pass keys nothing new. Measured to converge
## in 6-7 rounds on acorn's winter frame (round sizes 3767, 150, 73, 33, 7,
## 2, 0) and to bring the ratio to 0.45 -- in the same range as the sheets
## that never needed keying at all. Tested against the danger case this
## invites: run the same erosion on acorn's OWN snow frame and it eats
## 17539 more pixels of what measured as real snow before erosion --
## confirming this must stay off everywhere but the one frame it is safe
## for, which is exactly what the `aggressive` flag being IllustratedTree's
## choice, not a sheet-wide one, guarantees.
const HALO_LUMINANCE := 0.6
const HALO_MAX_SATURATION := 0.2

## Every background-COLOURED pixel in `piece` (see `is_background`),
## whether reachable from the edge or not, plus its anti-aliased halo --
## see the "aggressive" doc comment on `cut_out` above for why this is only
## ever safe to call on the bare-winter frame.
static func _aggressive_background(piece: Image) -> Dictionary:
	var wide := piece.get_width()
	var high := piece.get_height()
	var keyed := {}
	for y in high:
		for x in wide:
			if is_background(piece.get_pixel(x, y)):
				keyed[Vector2i(x, y)] = true
	var changed := true
	while changed:
		changed = false
		var newly: Array[Vector2i] = []
		for y in high:
			for x in wide:
				var at := Vector2i(x, y)
				if keyed.has(at):
					continue
				var pixel := piece.get_pixel(x, y)
				var luminance := (pixel.r + pixel.g + pixel.b) / 3.0
				if luminance < HALO_LUMINANCE or pixel.s > HALO_MAX_SATURATION:
					continue
				var touches_keyed := false
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if (dx != 0 or dy != 0) and keyed.has(Vector2i(x + dx, y + dy)):
							touches_keyed = true
							break
					if touches_keyed:
						break
				if touches_keyed:
					newly.append(at)
		if not newly.is_empty():
			changed = true
			for at in newly:
				keyed[at] = true
	return keyed


## Background connected to `piece`'s own edges, within `KEY_TOLERANCE` of
## `sheet`'s corner colour -- see the "Sheets with an opaque background" doc
## comment on `cut_out` above for why reachability, not colour, decides this.
static func _reachable_background(sheet: Image, piece: Image) -> Dictionary:
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
	return outside


## A region cut from `sheet` with its background made transparent: reachable
## from the edge only by default, or -- when `aggressive` is true -- every
## background-coloured pixel and its anti-aliased halo, reachable or not.
## See the two doc comments above for why the aggressive form is only ever
## safe to ask for on the bare-winter canopy frame.
static func cut_out(sheet: Image, region: Rect2i, aggressive: bool = false) -> Image:
	var piece := sheet.get_region(region)
	if not needs_keying(sheet):
		return piece
	# get_region() returns a piece in the SHEET's own format. Both known
	# needs_keying sheets (acorn, apple) decode with no alpha channel at
	# all, and set_pixel cannot store a non-1 alpha without one -- convert
	# first so the keying below actually takes effect.
	if piece.get_format() != Image.FORMAT_RGBA8:
		piece.convert(Image.FORMAT_RGBA8)
	var outside := _aggressive_background(piece) if aggressive else _reachable_background(sheet, piece)
	for at in outside:
		piece.set_pixel(at.x, at.y, Color(0, 0, 0, 0))
	return piece
