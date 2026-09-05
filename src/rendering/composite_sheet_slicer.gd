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

## How many THICK coarse cells (see _is_thick) a connected patch of them
## needs before it counts as a drawing's own core, eligible to seed a split
## (see _blob_boxes). Small ones are noise, not a second drawing -- a
## cluster of petals or leaves solid enough to pass _is_thick on its own,
## measured on the real cherry sheet at 4-22 cells, sitting in the gap
## between two real crowns and embedded inside one crown's own box, which
## without this filter reads as a THIRD core and (correctly, but
## needlessly) trips the overlap safety net in _blob_boxes, undoing a split
## that was otherwise exactly right. The real crown/trunk/fruit cores this
## must never exclude measure at minimum several hundred cells on every
## sheet checked -- the gap between real content and noise is wide enough
## that this only has to clear the noise with margin, not find an exact
## line.
const MIN_CORE_CELLS := 50


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

	for box in boxes:
		if float(box.size.x * box.size.y) / sheet_area < MIN_REGION_FRACTION:
			continue
		var trimmed := _trim(sheet, box)
		if trimmed.size.x > 0 and trimmed.size.y > 0:
			found.append(trimmed)

	found.sort_custom(_reading_order)
	return found


## Repeatedly unions any two regions that still overlap, until none do. Not
## currently reachable from regions_in -- _clip_apart (split boxes) and
## _merge_touching's has_core rule (separate raw components) between them
## account for every overlap source measured on the real sheets -- but kept
## as a named, tested unit in case some future sheet finds a third one
## before regions_in's own contract (test_regions_do_not_overlap) does.
static func _merge_overlapping(regions: Array[Rect2i]) -> Array[Rect2i]:
	var working := regions.duplicate()
	var merged := true
	while merged:
		merged = false
		var result: Array[Rect2i] = []
		for region in working:
			var joined := false
			for index in result.size():
				if result[index].intersects(region):
					result[index] = result[index].merge(region)
					joined = true
					merged = true
					break
			if not joined:
				result.append(region)
		working = result
	return working


## ## Splitting a blob with more than one solid core
##
## Plain flood-fill connectivity is not enough on its own: two real drawings
## can be joined by content that is real (not background) but never more
## than a coarse cell thin -- measured on the current tree art, a canopy
## crown drawn close enough to touch its neighbour (cherry blossom against
## the leaf canopy beside it), and a canopy column fused straight into its
## own trunk by a scatter of falling-leaf debris in the gap between them
## (hazelnut, apple). Both are two drawings, not one, but a single flood
## fill cannot tell that apart from a genuinely thin PART of one drawing
## (bare winter branches, a fruit's stem) -- connectivity alone treats both
## exactly the same.
##
## The two are told apart by THICKNESS instead. A real drawing is solid
## over an area many cells across; a bridge -- a thin branch line, a
## scattered chain of falling leaves not quite touching -- is at most one
## cell wide in some direction, so no 2x2 block of coarse cells around it is
## ever entirely filled. Cells that pass this test seed a drawing's CORE;
## a plain flood fill (unchanged from before) still finds every connected
## region, but a region containing more than one core is a false merge, and
## its cells are re-split by nearest core instead of kept as one box.
##
## A region with zero or one core is left exactly as plain flood-fill found
## it -- this is what keeps a genuinely thin drawing (bare winter branches,
## which may have no thick cell anywhere but their own trunk) from being
## fragmented at every thin stretch: with only one core (or none) there is
## nothing to split by, so the safety this needs costs nothing on the
## common case.
static func _blob_boxes(sheet: Image) -> Array[Rect2i]:
	var wide := sheet.get_width() / DETECTION_STEP
	var high := sheet.get_height() / DETECTION_STEP
	var filled := {}
	for y in high:
		for x in wide:
			if not is_background(sheet.get_pixel(x * DETECTION_STEP, y * DETECTION_STEP)):
				filled[Vector2i(x, y)] = true

	# Raw connected components: today's plain flood-fill, unchanged --
	# every filled cell reachable from every other by eight-connectivity, so
	# a drawing joined only corner-to-corner is still one blob. Cells are
	# tagged with which raw component they belong to, for the split step
	# below.
	var raw_of := {}
	var raw_cells: Array = [] # Array[Array[Vector2i]], indexed by raw id
	for start in filled:
		if raw_of.has(start):
			continue
		var id := raw_cells.size()
		var members: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		raw_of[start] = id
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			members.append(at)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var next := Vector2i(at.x + dx, at.y + dy)
					if raw_of.has(next) or not filled.has(next):
						continue
					raw_of[next] = id
					queue.append(next)
		raw_cells.append(members)

	# Cores: connected components of THICK cells only (see _is_thick) -- the
	# solid interior of each real drawing. A component smaller than
	# MIN_CORE_CELLS is noise, not a second drawing, and is dropped back
	# into the ordinary (non-core) pool -- its cells stay part of whatever
	# raw component they were already in, just no longer eligible to seed
	# or justify a split.
	var core_of := {}
	var core_sizes := {} # core id -> cell count
	var next_core_id := 0
	for start in filled:
		if core_of.has(start) or not _is_thick(filled, start.x, start.y):
			continue
		var id := next_core_id
		next_core_id += 1
		var members: Array[Vector2i] = [start]
		var queue: Array[Vector2i] = [start]
		core_of[start] = id
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var next := Vector2i(at.x + dx, at.y + dy)
					if (
						core_of.has(next) or not filled.has(next)
						or not _is_thick(filled, next.x, next.y)
					):
						continue
					core_of[next] = id
					members.append(next)
					queue.append(next)
		core_sizes[id] = members.size()
		if members.size() < MIN_CORE_CELLS:
			for cell in members:
				core_of.erase(cell)

	# Which cores fall inside each raw component -- more than one means a
	# false merge.
	var cores_in_raw := {} # raw id -> Dictionary[core id, true]
	for cell in core_of:
		var raw_id: int = raw_of[cell]
		if not cores_in_raw.has(raw_id):
			cores_in_raw[raw_id] = {}
		cores_in_raw[raw_id][core_of[cell]] = true

	# Each box is tagged with the raw component (family) it came from, so
	# _merge_touching below can join boxes from DIFFERENT raw components
	# that legitimately overlap (its original purpose -- see its own doc
	# comment) without re-fusing two boxes deliberately split out of the
	# SAME one, which almost always still touch along the line they were
	# split at.
	var boxes: Array[Rect2i] = []
	var families: Array[int] = []
	var box_has_core: Array[bool] = []
	for raw_id in raw_cells.size():
		var members: Array = raw_cells[raw_id]
		var cores: Dictionary = cores_in_raw.get(raw_id, {})
		var new_boxes: Array[Rect2i] = (
			_boxes_from_cells(members) if cores.size() <= 1
			else _split_by_nearest_core(members, core_of)
		)
		# Every box to come out of this raw component carries a real core of
		# its own -- exactly one each if split (see _split_by_nearest_core),
		# or the raw component's own single core (if it has one) when left
		# whole. See _merge_touching's own doc comment for why this matters
		# past this point.
		var has_core: bool = cores.size() >= 1
		for box in new_boxes:
			boxes.append(box)
			families.append(raw_id)
			box_has_core.append(has_core)
	return _merge_touching(boxes, families, box_has_core, MERGE_GAP_PX)


## Whether coarse cell (x, y) sits inside some entirely-filled 2x2 block of
## coarse cells -- real 2D bulk, in some orientation, at the coarse
## resolution blob detection already works at. A cell that is filled but
## never part of such a block is at most a coarse cell wide in every
## direction: a thin branch line, a diagonal chain of scattered marks --
## never a real drawing's own solid interior. See the doc comment on
## _blob_boxes above for why this is the thing that tells a bridge apart
## from a real drawing's own thin extremities.
static func _is_thick(filled: Dictionary, x: int, y: int) -> bool:
	for corner in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var bx: int = x + corner.x
		var by: int = y + corner.y
		if (
			filled.has(Vector2i(bx, by))
			and filled.has(Vector2i(bx + 1, by))
			and filled.has(Vector2i(bx, by + 1))
			and filled.has(Vector2i(bx + 1, by + 1))
		):
			return true
	return false


## The bounding box of a set of coarse cells, scaled back up to sheet
## pixels -- shared by both the ordinary (one-core) and split (multi-core)
## paths through _blob_boxes so they produce boxes the same way.
static func _boxes_from_cells(cells: Array) -> Array[Rect2i]:
	if cells.is_empty():
		return []
	var first: Vector2i = cells[0]
	var left: int = first.x
	var right: int = first.x
	var top: int = first.y
	var bottom: int = first.y
	for cell in cells:
		left = mini(left, cell.x)
		right = maxi(right, cell.x)
		top = mini(top, cell.y)
		bottom = maxi(bottom, cell.y)
	return [Rect2i(
		left * DETECTION_STEP,
		top * DETECTION_STEP,
		(right - left + 1) * DETECTION_STEP,
		(bottom - top + 1) * DETECTION_STEP
	)]


## Splits a raw component that contains more than one core by handing every
## one of its cells to whichever core is nearest -- a multi-source flood
## race seeded from every core cell at once, so the boundary falls wherever
## two cores' waves actually meet rather than at an arbitrary line. Seeds
## are sorted before seeding only so an exact tie (a cell equidistant from
## two cores) resolves the same way on every run, not to bias the race
## itself.
static func _split_by_nearest_core(members: Array, core_of: Dictionary) -> Array[Rect2i]:
	var in_component := {}
	for cell in members:
		in_component[cell] = true

	var seeds: Array = []
	for cell in members:
		if core_of.has(cell):
			seeds.append(cell)
	seeds.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)

	var owner := {}
	var queue: Array[Vector2i] = []
	for cell in seeds:
		if owner.has(cell):
			continue
		owner[cell] = core_of[cell]
		queue.append(cell)

	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var next := Vector2i(at.x + dx, at.y + dy)
				if owner.has(next) or not in_component.has(next):
					continue
				owner[next] = owner[at]
				queue.append(next)

	var groups := {} # core id -> Array[Vector2i]
	for cell in owner:
		var id = owner[cell]
		if not groups.has(id):
			groups[id] = []
		groups[id].append(cell)

	var boxes: Array[Rect2i] = []
	for id in groups:
		boxes.append_array(_boxes_from_cells(groups[id]))

	# Nearest-core assignment partitions CELLS cleanly, but the resulting
	# bounding RECTANGLES can still overlap where two real drawings'
	# silhouettes interleave right at their shared boundary (measured on
	# the real cherry sheet: two crowns split correctly by cell, 8px of
	# rectangle overlap left at the seam). No region may overlap another
	# (see test_regions_do_not_overlap), so any pair still touching this
	# way is clipped apart -- the real content this costs is a handful of
	# pixels exactly at the seam, already the boundary a person would draw
	# by hand between two drawings this close together.
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			if boxes[i].intersects(boxes[j]):
				var clipped := _clip_apart(boxes[i], boxes[j])
				boxes[i] = clipped[0]
				boxes[j] = clipped[1]
	return boxes


## Shrinks two overlapping boxes just enough that they no longer overlap,
## cutting along whichever axis actually separates their CENTRES more --
## horizontal if one sits further left/right of the other than above/below,
## vertical otherwise -- at the midpoint of their overlap on that axis. See
## the doc comment on _split_by_nearest_core above for why this is needed
## at all.
static func _clip_apart(a: Rect2i, b: Rect2i) -> Array[Rect2i]:
	var overlap := a.intersection(b)
	var a_center := a.position + a.size / 2
	var b_center := b.position + b.size / 2
	var a_clipped := a
	var b_clipped := b
	if absi(a_center.x - b_center.x) >= absi(a_center.y - b_center.y):
		var line: int = (overlap.position.x + overlap.position.x + overlap.size.x) / 2
		if a_center.x <= b_center.x:
			a_clipped.size.x = mini(a.size.x, line - a.position.x)
			b_clipped.position.x = line
			b_clipped.size.x = (b.position.x + b.size.x) - line
		else:
			b_clipped.size.x = mini(b.size.x, line - b.position.x)
			a_clipped.position.x = line
			a_clipped.size.x = (a.position.x + a.size.x) - line
	else:
		var line: int = (overlap.position.y + overlap.position.y + overlap.size.y) / 2
		if a_center.y <= b_center.y:
			a_clipped.size.y = mini(a.size.y, line - a.position.y)
			b_clipped.position.y = line
			b_clipped.size.y = (b.position.y + b.size.y) - line
		else:
			b_clipped.size.y = mini(b.size.y, line - b.position.y)
			a_clipped.position.y = line
			a_clipped.size.y = (a.position.y + a.size.y) - line
	return [a_clipped, b_clipped]


## Joins boxes that overlap or sit within `gap` of each other, repeatedly,
## until nothing more merges -- one merge can bring two others into range.
## Meant for absorbing a detached stray -- a twig, a leaf -- into the real
## drawing its box happens to touch or fall inside; a box that carries a
## real CORE of its own (see _is_thick/MIN_CORE_CELLS) is never a stray, so
## two boxes that BOTH have one are never joined however much they overlap,
## however close together `gap` allows -- that combination is always two
## real, separate drawings (measured on the real hazelnut/apple sheets: a
## canopy crown and a solid, 1900-cell hanging nut cluster below it,
## belonging to two DIFFERENT raw components whose boxes merely touch,
## fused into one by exactly this pass before the has_core check existed).
##
## Two boxes sharing the same FAMILY never merge with each other either,
## however much they overlap: a family is the raw connected component (see
## _blob_boxes) a box came from, and two boxes from the same one only exist
## because they were deliberately split apart there -- merging them back
## together on the strength of their own rectangles touching, which split
## from one shape they almost always still do, would silently undo it. A
## merged box keeps the family AND the has_core flag of whichever side
## absorbed the other, so it still won't re-fuse with that side's own
## sibling, or newly qualify to block a merge it couldn't have blocked
## before.
static func _merge_touching(
	boxes: Array[Rect2i], families: Array[int], has_core: Array[bool], gap: int
) -> Array[Rect2i]:
	var merged := true
	var working := boxes.duplicate()
	var working_families := families.duplicate()
	var working_has_core := has_core.duplicate()
	while merged:
		merged = false
		var result: Array[Rect2i] = []
		var result_families: Array[int] = []
		var result_has_core: Array[bool] = []
		for index in working.size():
			var box: Rect2i = working[index]
			var family: int = working_families[index]
			var core: bool = working_has_core[index]
			var joined := false
			for existing_index in result.size():
				if result_families[existing_index] == family:
					continue
				if not result[existing_index].grow(gap).intersects(box.grow(gap)):
					continue
				if result_has_core[existing_index] and core:
					# Two real, separate drawings -- never fused into one,
					# but their rectangles still may not overlap (see
					# test_regions_do_not_overlap), so they are clipped
					# apart at their shared boundary instead, the same way
					# a split's own siblings are (see _clip_apart).
					if result[existing_index].intersects(box):
						var clipped := _clip_apart(result[existing_index], box)
						result[existing_index] = clipped[0]
						box = clipped[1]
						merged = true
					continue
				result[existing_index] = result[existing_index].merge(box)
				result_has_core[existing_index] = result_has_core[existing_index] or core
				joined = true
				merged = true
				break
			if not joined:
				result.append(box)
				result_families.append(family)
				result_has_core.append(core)
		working = result
		working_families = result_families
		working_has_core = result_has_core
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


## ## White speckles scattered through a drawing's own interior
##
## Reported: "the new tree sprites have white speckles around outline" (pine's
## turning/autumn frame named specifically). NOT a keying/background problem
## -- confirmed directly: `aggressive` keying (which erodes background and its
## anti-aliased halo to convergence) leaves these pixels completely untouched,
## and sampling their raw colour shows them fully OPAQUE, sitting among
## normal richly-saturated foliage colour with no gradient leading to them.
## That rules out anti-aliasing (a blend always has neighbours between the
## two colours it blends) and unreached background (background here reads
## near-white AND low-saturation, exactly like these pixels, but a real gap
## between foliage clusters is many pixels across, not a single fleck) --
## what is left is noise baked into the source art itself, most likely an
## artifact of however these sheets were generated.
##
## The real, measured signal that tells a speckle apart from a genuine pale
## FEATURE (a snow-covered bough, a blossom petal) is not colour -- both read
## identically pale/low-saturation -- but SIZE: grouping pale pixels into
## connected components (8-connectivity, same style as the blob detection
## above), a speckle is a small fleck and a real feature is a large patch,
## with a wide, clean gap between the two on every real sheet measured. Pine's
## turning and leaf frames -- neither of which has any business drawing real
## pale content -- top out at 40 and 61 pixels for their single LARGEST pale
## component. Pine's snow frame -- real, legitimate pale content throughout --
## has plenty of small pale fragments too (its own edges), but its real snow
## patches run 446 to 1123 pixels each: an order of magnitude past anything
## either non-snow frame ever reaches. A single fixed size threshold
## comfortably inside that gap catches every measured speckle without ever
## reaching a real patch's own size, on any of the three frames checked.
const SPECKLE_MAX_COMPONENT_PIXELS := 150

## Replaces every pixel of a small, isolated pale speckle with a single
## average colour drawn from the non-pale opaque pixels bordering that WHOLE
## speckle -- one colour per component, not per pixel, so a speckle more than
## one pixel deep still gets a real colour for its own interior (which may
## have no non-pale pixel touching it directly). Applies everywhere, since
## the artifact this fixes has nothing to do with whether the sheet needed
## background-keying at all. A large pale connected component (see
## SPECKLE_MAX_COMPONENT_PIXELS' own doc comment) is a real feature and is
## left completely alone. Replacements are computed from the ORIGINAL pixels
## and applied only after every component has been found and sized, so
## fixing one speckle never feeds a wrong "normal" reading into sizing or
## fixing the speckle next to it.
static func despeckle(piece: Image) -> Image:
	var wide := piece.get_width()
	var high := piece.get_height()
	var is_pale := {}
	for y in high:
		for x in wide:
			var c := piece.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var luminance := (c.r + c.g + c.b) / 3.0
			if luminance >= HALO_LUMINANCE and c.s <= HALO_MAX_SATURATION:
				is_pale[Vector2i(x, y)] = true

	var visited := {}
	var speckle_components: Array = [] # Array[Array[Vector2i]]
	for start in is_pale:
		if visited.has(start):
			continue
		var members: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			members.append(at)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var next := Vector2i(at.x + dx, at.y + dy)
					if visited.has(next) or not is_pale.has(next):
						continue
					visited[next] = true
					queue.append(next)
		if members.size() <= SPECKLE_MAX_COMPONENT_PIXELS:
			speckle_components.append(members)

	var replacements := {} # Vector2i -> Color
	for members in speckle_components:
		var sum := Color(0, 0, 0)
		var count := 0
		for pos in members:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = pos.x + dx
					var ny: int = pos.y + dy
					if nx < 0 or ny < 0 or nx >= wide or ny >= high:
						continue
					if is_pale.has(Vector2i(nx, ny)):
						continue
					var nc := piece.get_pixel(nx, ny)
					if nc.a <= 0.0:
						continue
					sum += nc
					count += 1
		if count == 0:
			continue # no real content borders this speckle at all -- leave it
		var average := Color(sum.r / count, sum.g / count, sum.b / count)
		for pos in members:
			var alpha := piece.get_pixel(pos.x, pos.y).a
			replacements[pos] = Color(average.r, average.g, average.b, alpha)

	for pos in replacements:
		var color: Color = replacements[pos]
		piece.set_pixel(pos.x, pos.y, color)
	return piece


## A region cut from `sheet` with its background made transparent: reachable
## from the edge only by default, or -- when `aggressive` is true -- every
## background-coloured pixel and its anti-aliased halo, reachable or not.
## See the two doc comments above for why the aggressive form is only ever
## safe to ask for on the bare-winter canopy frame. Despeckled either way --
## see despeckle's own doc comment for why that is a separate problem from
## keying and applies whether or not the sheet needed keying at all.
static func cut_out(sheet: Image, region: Rect2i, aggressive: bool = false) -> Image:
	var piece := sheet.get_region(region)
	if not needs_keying(sheet):
		return despeckle(piece)
	# get_region() returns a piece in the SHEET's own format. Both known
	# needs_keying sheets (acorn, apple) decode with no alpha channel at
	# all, and set_pixel cannot store a non-1 alpha without one -- convert
	# first so the keying below actually takes effect.
	if piece.get_format() != Image.FORMAT_RGBA8:
		piece.convert(Image.FORMAT_RGBA8)
	var outside := _aggressive_background(piece) if aggressive else _reachable_background(sheet, piece)
	for at in outside:
		piece.set_pixel(at.x, at.y, Color(0, 0, 0, 0))
	return despeckle(piece)
