extends RefCounted

## The illustrated tree art: trunk, seasonal canopy, and fruit (see
## docs/concept/flora.md#illustrated-trees).
##
## A tree is composited from three separate pieces rather than drawn as one
## image, because they change on different clocks: the trunk never changes,
## the canopy changes four times a year, and the fruit changes as a crop
## ripens. Drawn as one image it would take an entire tree's worth of art for
## every combination of the three.
##
## This class only LOADS and SLICES the sheets. Compositing them into a tree
## is ProceduralTreeSprite's job, exactly as IllustratedFlowerHead hands
## frames to ProceduralFlowerSprite.
##
## Art is per species and optional: a species with sheets is drawn from them,
## one without falls back to the procedural painter unchanged. Adding a
## species costs its three sheets and one line here.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const CompositeSheetSlicer = preload("res://src/rendering/composite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_DIR := "res://assets/sprites/trees"

## Species with illustrated art. Everything else is procedural.
##
## Listed rather than probed for on disk: a missing file should be a visible
## registration, not a silent fallback that leaves an artist wondering why
## their sheet does nothing.
const SPECIES_WITH_ART := ["cherry", "walnut", "acorn", "hazelnut", "pine", "apple"]

## ## The canopy frames, in sheet order
##
## Four frames left to right. They map to seasons by MEANING rather than by
## index, because the sheet's order and SeasonCycle.SEASONS' order are not the
## same and never have to be: the sheet runs bare, blossom, leaf, turning,
## while the season list starts at spring.
##
## Written down explicitly because this is exactly the kind of thing that
## silently works until a sheet is authored in a different order -- and the
## failure would be a forest in blossom under snow.
##
## This table says which frame a name MEANS. It does not say when a tree wears
## it: a forest in blossom under snow was in fact reported, and the mapping was
## not at fault -- SeasonTransition spends the last third of every season
## turning into the next, so a third of winter was already reporting "turning
## into spring". WHEN is TreePhenology's job now (src/world/tree_phenology.gd,
## docs/concept/seasons.md), and it addresses these frames through exactly
## these four names.
const CANOPY_BARE := 0
const CANOPY_BLOSSOM := 1
const CANOPY_LEAF := 2
const CANOPY_TURNING := 3
const CANOPY_FRAME_COUNT := 4

## ## The fifth frame: snow
##
## A sheet may carry ONE more drawing past the four seasons -- how much snow
## lies on the branches. It is not a fifth entry in `_CANOPY_FRAME_BY_SEASON`
## because it is not a season at all: which season frame a tree wears is a
## pure function of the world clock (see docs/concept/seasons.md, "The canopy
## is on the clock, not on the simulation"), while how much of it is under
## snow is a live WEATHER fact -- the same simulation-driven quantity the
## GROUND's own lying snow already is (SnowLayer/EarthChunkManager.
## _snow_depth, accumulated from real weather via Snowfall.accumulate, and
## forceable with `/weather`). The ground carries a real, separate snow
## OVERLAY on top of its clock-driven season tint (see seasons.md, "The
## ground carries the season too"); the canopy's snow frame follows that same
## precedent rather than becoming a fifth phenology stage.
##
## Optional, unlike the four season frames: a species without this column
## simply has none, and every reader of `canopy_frames_for` must keep working
## exactly as it did before this frame could exist -- see `has_snow_frame_for`.
const CANOPY_SNOW := 4

const _CANOPY_FRAME_BY_SEASON := {
	"winter": CANOPY_BARE,
	"spring": CANOPY_BLOSSOM,
	"summer": CANOPY_LEAF,
	"autumn": CANOPY_TURNING,
}

## What an unrecognised season falls back to. In leaf is the safe default: a
## tree that is unexpectedly green is a tree, where a tree that is
## unexpectedly bare reads as dead.
const _FALLBACK_SEASON := "summer"

## ## What a fruit frame means
##
## The fruit block is laid out in ROWS, and the rows mean different things:
## the first row is the crop AS IT HANGS ON THE TREE -- drawn on a branch,
## with leaves or needles -- and the rows below it are what you get once you
## have picked it: shelled, cracked open, the kernel.
##
## Every sheet follows it. Walnut, acorn and hazelnut each draw two on-tree
## stages and two harvested ones; pine draws three of each, its extra on-tree
## stage being a bare needle sprig carrying no cone at all.
##
## Ripe is therefore the LAST on-tree stage and unripe the one before it,
## counted from the END rather than the start. Counted from the start, pine's
## bare sprig would be its unripe crop and its green cone the ripe one -- a
## tree bearing needles instead of cones.
##
## The frames below the first row are not drawn on trees at all. They are the
## fruit's later life and belong to item art.
const SEPARATE_FRUIT_FRAME_COUNT := 2

## Sliced frames live here, keyed by sheet path, because a forest asks for the
## same canopy for every tree in it. Static so the cache is shared across every
## instance rather than per renderer.
static var _frame_cache := {}
static var _image_cache := {}
## Sliced composite sheets, keyed by path.
static var _composite_cache := {}


static func has_art_for(species: String) -> bool:
	return SPECIES_WITH_ART.has(species)


## ## Two layouts
##
## Art arrives either as three separate files (trunk_x, canopy_x, fruit_x) or
## as ONE composite holding all of it. The composite wins where it exists,
## because it is how the art is actually generated -- one image is one prompt
## and one file to manage.
##
## A composite is cut up by FINDING the drawings on it (see CompositeSheetSlicer)
## rather than by a declared grid, then read by position: the top band is the
## canopy strip, the largest drawing below it is the trunk, and the rest are
## fruit in reading order. That is the layout a person naturally draws, and it
## does not have to be described per species.
static func composite_path_for(species: String) -> String:
	return "%s/composite_%s.png" % [_SHEET_DIR, species] if has_art_for(species) else ""


## Whether this species ships as one image rather than three.
##
## Asks the filesystem rather than trying to load and seeing what happens:
## Image.load_from_file logs an engine error for a missing file, so probing by
## loading fills the log with errors for every species that uses the
## three-file layout.
func has_composite(species: String) -> bool:
	var path := composite_path_for(species)
	return path != "" and _sheet_exists(path)


## Whether a sheet is actually on disk, in either the imported resource or as
## a plain file (a headless test run has not necessarily imported anything).
static func _sheet_exists(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


static func trunk_path_for(species: String) -> String:
	return "%s/trunk_%s.png" % [_SHEET_DIR, species] if has_art_for(species) else ""


static func canopy_path_for(species: String) -> String:
	return "%s/canopy_%s.png" % [_SHEET_DIR, species] if has_art_for(species) else ""


static func fruit_path_for(species: String) -> String:
	return "%s/fruit_%s.png" % [_SHEET_DIR, species] if has_art_for(species) else ""


## The canopy frame for a season. Falls back rather than failing: an unknown
## season should not take a forest down.
func canopy_for(species: String, season: String) -> Texture2D:
	var frames := canopy_frames_for(species)
	if frames.is_empty():
		return null
	var index: int = _CANOPY_FRAME_BY_SEASON.get(
		season, _CANOPY_FRAME_BY_SEASON[_FALLBACK_SEASON]
	)
	return frames[clampi(index, 0, frames.size() - 1)]


## Every canopy frame for this species, in sheet order: the four seasons,
## then a fifth snow frame if the sheet has one (see CANOPY_SNOW).
##
## Empty for a species with no art, which the caller reads as "paint it
## procedurally".
func canopy_frames_for(species: String) -> Array[Texture2D]:
	if has_composite(species):
		return _composite_parts(species)["canopy"]
	return _canopy_frames_from_sheet(canopy_path_for(species))


## Whether this species' canopy carries a fifth, snow-covered frame past its
## four seasons -- true for any species whose real sheet content turned out
## to hold more than CANOPY_FRAME_COUNT drawings, composite or separate-file
## alike, so a species gains this the moment its art does, with no roster to
## maintain here.
func has_snow_frame_for(species: String) -> bool:
	return canopy_frames_for(species).size() > CANOPY_FRAME_COUNT


## The snow-covered canopy, or null for a species whose sheet has no fifth
## frame yet -- the fallback a caller gates a snow blend on, so a species
## without this frame is never asked to blend toward one.
func snow_canopy_for(species: String) -> Texture2D:
	if not has_snow_frame_for(species):
		return null
	return canopy_frames_for(species)[CANOPY_SNOW]


## Every fruit frame this species has, in sheet order.
func fruit_frames_for(species: String) -> Array[Texture2D]:
	if has_composite(species):
		return _composite_parts(species)["fruit"]
	return _frames(fruit_path_for(species), SEPARATE_FRUIT_FRAME_COUNT)


## The crop as it hangs on the tree: the first ROW of the fruit block, in
## ripening order.
##
## A species whose art is three separate files has no rows to speak of, so its
## whole fruit sheet is the on-tree sequence -- which is what the cherry sheet
## is.
func on_tree_frames_for(species: String) -> Array[Texture2D]:
	if has_composite(species):
		return _composite_parts(species)["on_tree"]
	return fruit_frames_for(species)


## What the crop becomes once picked -- shelled, cracked open, the kernel.
## Never drawn on a tree; this is item art.
func harvest_frames_for(species: String) -> Array[Texture2D]:
	if has_composite(species):
		return _composite_parts(species)["harvest"]
	var empty: Array[Texture2D] = []
	return empty


## The fruit as it hangs on the tree: the LAST on-tree stage when ripe, the one
## before it when not.
##
## Counted from the end so a species with an extra early stage still ripens
## into the right frame (see "What a fruit frame means").
func fruit_for(species: String, ripe: bool) -> Texture2D:
	var frames := on_tree_frames_for(species)
	if frames.is_empty():
		return null
	var index: int = frames.size() - (1 if ripe else 2)
	return frames[clampi(index, 0, frames.size() - 1)]


## The trunk, which is one image rather than a strip -- it never changes.
func trunk_for(species: String) -> Texture2D:
	if has_composite(species):
		var trunks: Array[Texture2D] = _composite_parts(species)["trunk"]
		return null if trunks.is_empty() else trunks[0]
	var path := trunk_path_for(species)
	if path == "":
		return null
	var image := _load_image(path)
	if image == null:
		return null
	if not _frame_cache.has(path):
		var frames: Array[Texture2D] = [ImageTexture.create_from_image(image)]
		_frame_cache[path] = frames
	return _frame_cache[path][0]


## Cuts a composite sheet into its three roles.
##
## Read by POSITION rather than by a declared grid: the top band -- every
## drawing overlapping the topmost one vertically -- is the canopy strip, the
## first row below it is the trunk (see _trunk_row), and the rest are fruit
## in reading order. Cached per sheet, because slicing is a real cost and a
## forest asks for the same sheet for every tree in it.
func _composite_parts(species: String) -> Dictionary:
	var path := composite_path_for(species)
	if _composite_cache.has(path):
		return _composite_cache[path]

	var canopy: Array[Texture2D] = []
	var trunk: Array[Texture2D] = []
	var fruit: Array[Texture2D] = []
	var on_tree: Array[Texture2D] = []
	var harvest: Array[Texture2D] = []
	var sheet := _load_image(path)
	if sheet != null:
		var regions := CompositeSheetSlicer.regions_in(sheet)
		var below: Array[Rect2i] = []
		var canopy_x_centers: Array = []
		if not regions.is_empty():
			var band_bottom: int = regions[0].position.y + regions[0].size.y
			for region in regions:
				if region.position.y < band_bottom:
					canopy_x_centers.append(region.position.x + region.size.x / 2.0)
					# canopy[0] is always CANOPY_BARE (see the sheet-order
					# comment above) -- the one canopy role that never draws
					# anything pale by design, so it is the only one keyed
					# aggressively (see CompositeSheetSlicer.cut_out).
					var bare := canopy.is_empty()
					canopy.append(ImageTexture.create_from_image(
						CompositeSheetSlicer.cut_out(sheet, region, bare)
					))
				else:
					below.append(region)

		# The trunk is the first ROW under the canopy strip (see _trunk_row).
		# Usually one drawing; every other member of that row is a
		# season-tinted duplicate of the very same trunk, not a fruit stage,
		# so only the first survives.
		var trunk_row := _trunk_row(below)
		var fruit_regions: Array[Rect2i] = []
		for index in below.size():
			if trunk_row.has(index):
				if index == trunk_row[0]:
					trunk.append(ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, below[index])))
				continue
			fruit_regions.append(below[index])

		# Which of the rows below the trunk is the real on-tree fruit/nut row
		# -- see _on_tree_row's own doc comment for why this is no longer
		# simply "the first row". Its regions may be MERGES of more than one
		# of fruit_regions' own entries (see _merge_same_column_fragments),
		# so they are cut fresh from the sheet rather than reusing an
		# already-cut piece.
		var on_tree_regions: Array = _on_tree_row(fruit_regions, canopy_x_centers, sheet)
		for region in on_tree_regions:
			var rect: Rect2i = region
			on_tree.append(ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, rect)))
		for region in fruit_regions:
			var rect: Rect2i = region
			# Skip harvest for any fragment a merge above already folded
			# into an on_tree region -- otherwise the same fragmented
			# drawing's pieces would ALSO show up separately as harvested
			# item art, on top of their own now-reassembled on-tree copy.
			var absorbed := false
			for on_tree_region in on_tree_regions:
				var on_tree_rect: Rect2i = on_tree_region
				if on_tree_rect.encloses(rect):
					absorbed = true
					break
			if not absorbed:
				harvest.append(ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, rect)))
		fruit.append_array(on_tree)
		fruit.append_array(harvest)

	var parts := {
		"canopy": canopy,
		"trunk": trunk,
		"fruit": fruit,
		"on_tree": on_tree,
		"harvest": harvest,
	}
	_composite_cache[path] = parts
	return parts


## ## Finding the real on-tree fruit/nut row
##
## Reported: "the fruit entities are scaled wrong and cherries don't bear
## fruits at all it seems, apples neither and nuts do, but not uniformly".
## Confirmed directly: fruit_for("cherry", true) was a single autumn leaf,
## not cherries; fruit_for("apple"/"walnut"/"pine", true) was the SNOW-
## covered branch, not a ripe one.
##
## The richer composite art draws more below the trunk than the old
## two-row (on-tree / harvested) model assumed. Every species measured now
## draws a bare/snow TWIG closeup immediately under the trunk -- one per
## canopy column, no fruit on it at all -- and cherry, acorn and hazelnut
## additionally draw a row of single leaf/blossom/bud DETAIL closeups
## before their real fruit/nut row. Treating "the first row below the
## trunk" as the fruit either grabbed the twig row outright (cherry) or let
## the detail row bleed into it (acorn, hazelnut -- see the old
## `first_row_bottom` threshold this replaces, which only compared a
## candidate's own TOP against the very first region's BOTTOM: one
## short-but-first twig made that threshold too generous and swept in
## whatever detail row sat just below it too).
##
## Two independent, measured signals tell a real fruit row apart from
## either kind of placeholder:
##
## - FILL. A bare/snow twig is reliably sparse -- measured on the real
##   sheets, 0.19-0.24 of its own bounding box is drawn content. A single
##   leaf/blossom detail closeup OR a real fruit/nut cluster both measure
##   0.50-0.63 -- a wide, clean gap (see MIN_SUBSTANTIAL_FILL). This alone
##   separates a twig row from either of the other two, but not a detail
##   row from a real fruit row: both are comparably dense. A row qualifies
##   if its DENSEST member clears the bar, not every member -- a species'
##   real fruit row still carries a genuinely-sparse twig in its own
##   bare-winter column (no fruit in winter), sitting in the very same row
##   as its dense fruiting columns.
##
## - COLUMN DISCIPLINE. The real fruit row (like the twig row before it)
##   draws at most one item per canopy column. A detail row does not:
##   measured on the real cherry sheet, its blossom column alone carries
##   three separate closeups (a flower plus two loose petals) while its
##   other columns carry one. More than one region landing in the same
##   column is exactly what a closeup row looks like and a real fruit row
##   never does.
##
## Walking top to bottom and returning the first row that passes both
## checks handles every species measured without knowing in advance how
## many placeholder rows come first: apple/walnut/pine/hazelnut/acorn draw
## real fruit immediately below the trunk, so their very first row already
## qualifies; cherry's twig row fails on fill and its detail row fails on
## column discipline, so the walk continues to its real, further-down
## fruit row.
##
## The chosen row's own SNOW-column entry, if it has one, is then dropped
## (see _without_snow_column) -- the same "not a season, a weather overlay"
## reasoning canopy_for's own season table already applies to CANOPY_SNOW,
## extended here so fruit_for's ripe/unripe pick can never land on a
## snow-dusted branch instead of a genuinely ripe one.
##
## Falls back to the LAST row -- not the first -- if nothing ever cleanly
## passes both checks.
##
## Measured on the real cherry sheet: its twig row and its real fruit row
## are not perfectly separated by blob detection -- a leafy, cherry-bearing
## twig gets cut into two or three pieces (see _merge_same_column_fragments'
## own doc comment for why, and for how those pieces are put back together
## rather than picked between), so BOTH of cherry's below-trunk rows carry
## one column with more than one candidate and neither cleanly passes.
## Between the two, the row closer to the real fruit (further down the
## sheet, past the twig/detail placeholders) is always the better guess
## than the one right under the trunk -- real fruit is drawn progressively
## further down as a sheet gets busier, never before its own placeholders.
static func _on_tree_row(fruit_regions: Array[Rect2i], canopy_x_centers: Array, sheet: Image) -> Array:
	var rows := _group_into_rows(fruit_regions)
	for row in rows:
		if _looks_like_real_fruit(row, sheet, canopy_x_centers):
			return _without_snow_column(_merge_same_column_fragments(row, canopy_x_centers), canopy_x_centers)
	if rows.is_empty():
		return []
	var chosen: Array = rows[-1]
	return _without_snow_column(_merge_same_column_fragments(chosen, canopy_x_centers), canopy_x_centers)


## ## Why a column ever carries more than one region here at all
##
## Not a second drawing: CompositeSheetSlicer's blob/core detection
## (_is_thick/MIN_CORE_CELLS, tuned and measured against the much larger
## canopy strip -- crowns of several thousand cells, a real hazelnut/apple
## nut cluster measured at 1900 cells) finds MULTIPLE separate "cores" of
## real 2D bulk inside a single, much smaller fruit-block drawing -- a
## leafy twig with a cherry forming on it, cut into 2-3 pieces at a
## leaf-cluster boundary. Measured directly (SLICER_DEBUG probe against the
## real cherry sheet): the false cores this produces top out around 600
## cells, well short of the ~1900-cell floor a real second drawing needs to
## clear -- so the two cases don't collide on cell count, but they also
## don't collide on RATIO (a genuinely fused pair -- two touching canopy
## crowns -- split close to evenly, e.g. 2988/3675 cells; the false splits
## here range from a lopsided 84/959 up to a fairly even 380/226/256/167,
## so no single count or ratio threshold tells every real case from every
## false one apart without either missing some of these false splits or
## wrongly un-splitting a real pair).
##
## So this is fixed at the layer that already knows the answer instead:
## every one of these false splits was ONE connected raw component before
## CompositeSheetSlicer split it (that is the only way it could have found
## more than one core inside a single region in the first place), so
## reunioning whatever pieces land in the same canopy column recovers
## exactly the original drawing, pixels included -- no tuning, no
## threshold, and nothing for a genuinely separate touching pair (which
## split into DIFFERENT columns, not the same one) to be caught by.
##
## Deliberately not fixed in CompositeSheetSlicer itself: retuning
## _is_thick/MIN_CORE_CELLS to stop finding these false cores would have to
## clear the real cherry/apple/hazelnut splits' own measured floor (the
## 1900-cell nut cluster above, and the synthetic regression tests in
## test_composite_sheet_slicer.gd, whose small solid test blobs sit well
## inside the same 84-600 false-core range measured here) -- there is no
## single number that is a false core in the fruit block and a real one in
## the canopy strip and in that test file at once. Reassembling the
## fragments where they are already known to belong -- one canopy column --
## sidesteps needing one.
static func _merge_same_column_fragments(row: Array, canopy_x_centers: Array) -> Array:
	var union_by_column := {} # column index -> Rect2i
	for region in row:
		var rect: Rect2i = region
		var column := _nearest_canopy_column(rect, canopy_x_centers)
		union_by_column[column] = rect if not union_by_column.has(column) else union_by_column[column].merge(rect)
	var merged: Array = []
	for column in union_by_column:
		merged.append(union_by_column[column])
	return merged


## Groups `regions` into rows: two regions that mutually overlap in Y --
## directly, or transitively through a chain of others -- are the same row,
## since a hand-drawn row is not perfectly straight and a short item (a
## bare-winter twig) can sit shorter than its neighbours in the very same
## row. Unlike _trunk_row's own overlap check, membership here is NOT also
## gated on similar height: _trunk_row is deliberately narrow (it exists
## only to catch near-identical duplicate copies of one drawing), where a
## real row of DIFFERENT drawings -- a short twig beside a tall fruit
## cluster -- is exactly the shape this must still recognise as one row.
##
## Returned top to bottom, each row's own members left to right.
static func _group_into_rows(regions: Array[Rect2i]) -> Array:
	var rows: Array = [] # Array[Array[Rect2i]]
	for region in regions:
		var joined: Array = [region]
		var remaining: Array = []
		for row in rows:
			var overlaps := false
			for member in row:
				var member_rect: Rect2i = member
				if (
					region.position.y < member_rect.position.y + member_rect.size.y
					and member_rect.position.y < region.position.y + region.size.y
				):
					overlaps = true
					break
			if overlaps:
				joined.append_array(row)
			else:
				remaining.append(row)
		remaining.append(joined)
		rows = remaining
	for row in rows:
		var typed_row: Array[Rect2i] = []
		for region in row:
			typed_row.append(region)
		typed_row.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position.x < b.position.x)
		row.clear()
		row.append_array(typed_row)
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		var a_rect: Rect2i = a[0]
		var b_rect: Rect2i = b[0]
		var a_top := a_rect.position.y
		var b_top := b_rect.position.y
		for member in a:
			var member_rect: Rect2i = member
			a_top = mini(a_top, member_rect.position.y)
		for member in b:
			var member_rect: Rect2i = member
			b_top = mini(b_top, member_rect.position.y)
		return a_top < b_top
	)
	return rows


## How much of a region's own bounding box is drawn content, not background
## -- see CompositeSheetSlicer.is_background. See _on_tree_row's own doc
## comment for the real measurements (twig 0.19-0.24, leaf/fruit 0.50-0.63)
## this sits in the middle of, with real margin either side.
const MIN_SUBSTANTIAL_FILL := 0.35

## Whether `row` is the real on-tree fruit/nut row -- see _on_tree_row's own
## doc comment for the two signals this checks (fill and column
## discipline).
static func _looks_like_real_fruit(row: Array, sheet: Image, canopy_x_centers: Array) -> bool:
	if row.is_empty() or canopy_x_centers.is_empty():
		return false
	var columns_seen := {}
	var best_fill := 0.0
	for region in row:
		var rect: Rect2i = region
		var column := _nearest_canopy_column(rect, canopy_x_centers)
		if columns_seen.has(column):
			return false # more than one region in this column -- a detail row
		columns_seen[column] = true
		best_fill = maxf(best_fill, _fill_fraction(sheet, rect))
	return best_fill >= MIN_SUBSTANTIAL_FILL


## Drops whichever region in `row` lands under the SNOW canopy column, if
## any -- see _on_tree_row's own doc comment. A species whose real fruit
## row has no snow-column entry at all (cherry: no snow-covered cherry
## cluster is drawn) is returned unchanged.
static func _without_snow_column(row: Array, canopy_x_centers: Array) -> Array:
	if canopy_x_centers.size() <= CANOPY_SNOW:
		return row
	var kept: Array = []
	for region in row:
		var rect: Rect2i = region
		if _nearest_canopy_column(rect, canopy_x_centers) != CANOPY_SNOW:
			kept.append(region)
	return kept


## Which of the canopy strip's own columns `region` sits under -- nearest by
## X-centre, the same "measure against the canopy's own real positions"
## idiom the trunk row and canopy strip already use elsewhere in this file.
static func _nearest_canopy_column(region: Rect2i, canopy_x_centers: Array) -> int:
	var center := region.position.x + region.size.x / 2.0
	var nearest := 0
	var nearest_distance := INF
	for index in canopy_x_centers.size():
		var distance: float = absf(center - float(canopy_x_centers[index]))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = index
	return nearest


## The fraction of `region`'s own area (sampled, not exhaustively -- a fruit
## block region is small enough that this is cheap either way, but the same
## coarse-then-exact idiom CompositeSheetSlicer.DETECTION_STEP already uses
## keeps this fast on the largest regions too) that is drawn content rather
## than background.
static func _fill_fraction(sheet: Image, region: Rect2i) -> float:
	var clipped := region.intersection(Rect2i(0, 0, sheet.get_width(), sheet.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return 0.0
	var step: int = maxi(1, mini(clipped.size.x, clipped.size.y) / 40)
	var filled := 0
	var total := 0
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y, step):
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x, step):
			total += 1
			if not CompositeSheetSlicer.is_background(sheet.get_pixel(x, y)):
				filled += 1
	return float(filled) / float(maxi(total, 1))


## How close two regions' heights must be to count as copies of the same
## drawing rather than a trunk overlapping a shorter fruit row beside it.
##
## Measured on the real sheets, the two cases sit far apart with a wide gap
## between them: a genuine duplicated trunk row's members are always within
## 3% of each other's height (0.973 the worst real case, on walnut), while a
## real trunk is never less than about 1.65x taller than the closest fruit
## row it happens to overlap in y (0.608 the closest real case, on apple).
## 0.85 sits in the middle of that gap with real margin either side.
const TRUNK_ROW_HEIGHT_RATIO := 0.85


## The trunk is the first ROW of drawings below the canopy strip -- normally
## one drawing, but an artist may draw it once PER canopy column (season-
## tinted) instead of sharing a single image across all of them. Every
## region sharing that row is a duplicate of the very same trunk, not a
## fruit stage, so `_composite_parts` keeps only the first and drops the
## rest rather than misreading them as extra fruit.
##
## Position rather than size, unlike the trunk's old selection rule --
## measured on a real sheet where a duplicated trunk row and a blob merged
## out of an on-branch fruit drawing and its harvested forms landed within a
## few percent of each other in AREA, so "biggest" could no longer tell them
## apart and picked the merged fruit blob instead of any real trunk.
##
## Vertical overlap alone is not enough, though: a real, well-structured
## sheet's single trunk is tall enough to overlap a shorter fruit row sitting
## beside it (not below it), which swept that fruit row into the trunk role
## entirely when this was tried with overlap alone. A region only joins the
## row when it ALSO stands close to the first region's own height (see
## TRUNK_ROW_HEIGHT_RATIO) -- true of five near-identical trunk copies drawn
## side by side, false of a trunk and the fruit beside it.
static func _trunk_row(below: Array[Rect2i]) -> Array[int]:
	var row: Array[int] = []
	if below.is_empty():
		return row
	var first: Rect2i = below[0]
	for index in below.size():
		var candidate: Rect2i = below[index]
		var overlaps_y: bool = (
			candidate.position.y < first.position.y + first.size.y
			and first.position.y < candidate.position.y + candidate.size.y
		)
		if not overlaps_y:
			continue
		var height_ratio := float(mini(candidate.size.y, first.size.y)) / float(
			maxi(candidate.size.y, first.size.y)
		)
		if height_ratio >= TRUNK_ROW_HEIGHT_RATIO:
			row.append(index)
	return row


## Slices a canopy sheet by FINDING its real drawings, the same blob-detection
## technique the composite layout's own canopy strip already uses (see
## CompositeSheetSlicer) -- reused here rather than reimplemented, because a
## separate canopy file is exactly the shape CompositeSheetSlicer already
## reads: a single row of drawings of different sizes. Unlike the old
## equal-width `_frames` cut, this survives a sheet whose frames are not all
## the same width, which the snow frame added to the cherry sheet is not
## (measured: 404/415/421/423/432px). It also means a species gains its
## snow frame automatically the day its sheet grows a fifth drawing -- no
## frame count to bump here, since none is declared.
func _canopy_frames_from_sheet(path: String) -> Array[Texture2D]:
	var empty: Array[Texture2D] = []
	if path == "":
		return empty
	if _frame_cache.has(path):
		return _frame_cache[path]
	var sheet := _load_image(path)
	if sheet == null:
		return empty
	var frames: Array[Texture2D] = []
	for region in CompositeSheetSlicer.regions_in(sheet):
		# frames[0] is always CANOPY_BARE, same convention as the composite
		# canopy strip -- see the aggressive-keying comment there.
		var bare := frames.is_empty()
		frames.append(ImageTexture.create_from_image(
			CompositeSheetSlicer.cut_out(sheet, region, bare)
		))
	_frame_cache[path] = frames
	return frames


## Slices a sheet into `count` equal frames left to right. Still used for
## fruit (see fruit_frames_for), whose stages are not being changed here --
## only the canopy path moved to content-based slicing (see
## _canopy_frames_from_sheet).
##
## Equal slices, so a frame that came out a pixel wider than its neighbours
## would drift the whole strip.
func _frames(path: String, count: int) -> Array[Texture2D]:
	var empty: Array[Texture2D] = []
	if path == "":
		return empty
	if _frame_cache.has(path):
		return _frame_cache[path]
	var sheet := _load_image(path)
	if sheet == null:
		return empty
	var frame_width := sheet.get_width() / count
	var frames: Array[Texture2D] = []
	for index in count:
		var frame := Image.create(
			frame_width, sheet.get_height(), false, Image.FORMAT_RGBA8
		)
		frame.blit_rect(
			sheet,
			Rect2i(index * frame_width, 0, frame_width, sheet.get_height()),
			Vector2i.ZERO
		)
		frames.append(ImageTexture.create_from_image(frame))
	_frame_cache[path] = frames
	return frames


## Loads a sheet off disk, normalized to FORMAT_RGBA8 and cached per path.
## Delegates the actual read to SpriteSheetLoader (prefers the imported
## resource, falls back to reading the file directly so the sheets work in
## a headless test run where Godot's import step has not necessarily
## happened) -- no separate existence pre-check needed here, since
## SpriteSheetLoader already returns null for a path that is neither a
## registered resource nor a real file on disk.
func _load_image(path: String) -> Image:
	if _image_cache.has(path):
		return _image_cache[path]
	var image := SpriteSheetLoader.load_image(path)
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_image_cache[path] = image
	return image
