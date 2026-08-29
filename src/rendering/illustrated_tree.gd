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
		if not regions.is_empty():
			var band_bottom: int = regions[0].position.y + regions[0].size.y
			for region in regions:
				if region.position.y < band_bottom:
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
			var texture := ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, below[index]))
			fruit.append(texture)
			fruit_regions.append(below[index])

		# Split the fruit into its rows: the first row is the crop on the tree,
		# everything below it is what the crop becomes once picked.
		if not fruit_regions.is_empty():
			var first_row_bottom: int = fruit_regions[0].position.y + fruit_regions[0].size.y
			for index in fruit_regions.size():
				if fruit_regions[index].position.y < first_row_bottom:
					on_tree.append(fruit[index])
				else:
					harvest.append(fruit[index])

	var parts := {
		"canopy": canopy,
		"trunk": trunk,
		"fruit": fruit,
		"on_tree": on_tree,
		"harvest": harvest,
	}
	_composite_cache[path] = parts
	return parts


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
