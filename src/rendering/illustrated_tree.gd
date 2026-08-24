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
const CANOPY_BARE := 0
const CANOPY_BLOSSOM := 1
const CANOPY_LEAF := 2
const CANOPY_TURNING := 3
const CANOPY_FRAME_COUNT := 4

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


## Every canopy frame for this species, in sheet order. Empty for a species
## with no art, which the caller reads as "paint it procedurally".
func canopy_frames_for(species: String) -> Array[Texture2D]:
	if has_composite(species):
		return _composite_parts(species)["canopy"]
	return _frames(canopy_path_for(species), CANOPY_FRAME_COUNT)


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
## largest drawing below it is the trunk, and the rest are fruit in reading
## order. Cached per sheet, because slicing is a real cost and a forest asks
## for the same sheet for every tree in it.
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
					canopy.append(ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, region)))
				else:
					below.append(region)

		# The trunk is the biggest thing under the canopy strip. Picked by size
		# rather than position, so the lower half can be arranged freely.
		var trunk_index := -1
		var largest := 0
		for index in below.size():
			var area: int = below[index].size.x * below[index].size.y
			if area > largest:
				largest = area
				trunk_index = index
		var fruit_regions: Array[Rect2i] = []
		for index in below.size():
			var texture := ImageTexture.create_from_image(CompositeSheetSlicer.cut_out(sheet, below[index]))
			if index == trunk_index:
				trunk.append(texture)
			else:
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


## Slices a sheet into `count` equal frames left to right.
##
## Equal slices, so a frame that came out a pixel wider than its neighbours
## would drift the whole strip -- pinned by
## test_canopy_frames_are_all_the_same_size.
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
