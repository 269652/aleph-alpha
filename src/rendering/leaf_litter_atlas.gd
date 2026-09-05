extends RefCounted

## The illustrated fallen-leaf STAMPS LeafLitterRenderer's shared MultiMesh
## draws with (see docs/concept/leaf_litter.md, SnowStampAtlas which this
## mirrors).
##
## This class only prepares ART -- it packs every TreeSpecies/season pair's
## litter texture into one runtime atlas on a FIXED cell grid (unlike
## grass_blades.png's pre-baked sheet of irregular UV pairs): a fixed grid
## means addressing a cell costs a single small index, which leaves the
## renderer's own per-instance channel budget with room for its fall-phase
## timing (see LeafLitterRenderer's own doc comment).
##
## Every species/season pair gets its own cell -- real illustrated art (see
## IllustratedTree.foliage_leaf_for) where the artist has drawn it, and the
## SAME generic procedural sprite DroppedItem always fell back to otherwise
## for any pair that lacks it. Every one of the 6 species x 2 seasons this
## project ships today actually HAS real illustrated art (verified directly;
## an earlier draft of this feature's own plan named "pine/autumn" as a gap,
## which is no longer -- or was never actually -- true), so the fallback
## path exists for whenever a future species/season genuinely lacks art,
## not because one currently does.

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

## Only ever the two seasons a leaf actually falls in (see
## EarthChunkManager.step_fruiting's own leaf_fall_season) -- spring/winter
## never appear on a fallen leaf's own record.
const SEASONS := ["summer", "autumn"]

## How many pixels of art one stamp carries. Mirrors SnowStampAtlas.STAMP_SIZE
## exactly, for the same reason: real headroom above the art's own native
## resolution at this game's camera zoom, so the GPU never magnifies past it.
const STAMP_SIZE := 64

## A transparent gutter around every cell -- same bilinear-bleed reasoning as
## SnowStampAtlas.STAMP_PADDING (the shader samples this atlas with linear
## filtering, which would otherwise ghost the next cell's edge into this one).
const STAMP_PADDING := 2
const CELL_SIZE := STAMP_SIZE + STAMP_PADDING * 2

## What counts as "there is art here" when cropping to content -- same
## reasoning and same value as SnowStampAtlas.CONTENT_ALPHA_THRESHOLD.
const CONTENT_ALPHA_THRESHOLD := 0.05

static var _atlas_texture: ImageTexture = null

var _illustrated_tree := IllustratedTree.new()
var _item_sprite := ProceduralItemSprite.new()
var _stamp_cache: Dictionary = {}


## Which (species, season) pairs exist, in the fixed order cell_index below
## assigns them -- TreeSpecies.IDS x SEASONS, species-major.
static func _pairs() -> Array:
	var pairs: Array = []
	for species in TreeSpecies.IDS:
		for season in SEASONS:
			pairs.append([species, season])
	return pairs


## The fixed cell index for `species`/`season` -- stable across calls and
## across process runs (a pure function of TreeSpecies.IDS/SEASONS' own
## fixed order), so the renderer can pack it once and never need to re-ask.
func cell_index(species: String, season: String) -> int:
	var season_index := SEASONS.find(season)
	var species_index := TreeSpecies.IDS.find(species)
	if species_index < 0 or season_index < 0:
		return 0
	return species_index * SEASONS.size() + season_index


func cell_count() -> int:
	return TreeSpecies.IDS.size() * SEASONS.size()


## Whether `species`/`season` has real illustrated art (see
## IllustratedTree.has_foliage_leaf_for) rather than the generic procedural
## fallback.
func has_illustrated_art(species: String, season: String) -> bool:
	return _illustrated_tree.has_foliage_leaf_for(species, season)


## The raw source image for this pair, before any cropping/fitting -- real
## illustrated art where the artist has drawn it, the same generic
## procedural sprite DroppedItem always fell back to otherwise (see
## docs/concept/leaf_litter.md).
func _source_image(species: String, season: String) -> Image:
	if has_illustrated_art(species, season):
		return _illustrated_tree.foliage_leaf_for(species, season).get_image()
	# Same sprite_id shape EarthChunkManager.step_fruiting/DroppedItem always
	# built ("<species>_leaf_<season>") -- ProceduralItemSprite hashes this
	# string to shape/colour, so a missing pair keeps exactly the fallback
	# look it always had rather than a new, unrelated one.
	var sprite_id := "%s_leaf_%s" % [species, season]
	return _item_sprite.texture_for(sprite_id).get_image()


## The tight bounding box of the actual art inside `image` -- mirrors
## SnowStampAtlas.content_rect's identical alpha-threshold scan, applied to a
## whole standalone image instead of one cell of a larger sheet.
func _content_rect(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var max_x := -1
	var min_y := image.get_height()
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= CONTENT_ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i(0, 0, image.get_width(), image.get_height())
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## One stamp: `species`/`season`'s own art, cropped to its content and fitted
## into a STAMP_SIZE square -- mirrors SnowStampAtlas.build_stamp_image
## exactly (fitted by the smaller ratio and centred, never stretched to the
## square outright; Lanczos, since this always SHRINKS a bigger source crop
## down to STAMP_SIZE -- see that function's own doc comment for why
## Lanczos, not nearest-neighbour, is right for that direction). Cached: the
## source art never changes mid-process.
func build_stamp_image(species: String, season: String) -> Image:
	var key := "%s_%s" % [species, season]
	if _stamp_cache.has(key):
		return _stamp_cache[key]

	var source := _source_image(species, season)
	if source.get_format() != Image.FORMAT_RGBA8:
		source = source.duplicate()
		source.convert(Image.FORMAT_RGBA8)
	var content := _content_rect(source)
	var cropped := source.get_region(content)
	if cropped.get_format() != Image.FORMAT_RGBA8:
		cropped.convert(Image.FORMAT_RGBA8)

	var scale: float = minf(
		float(STAMP_SIZE) / float(content.size.x), float(STAMP_SIZE) / float(content.size.y)
	)
	var fitted_width := clampi(int(round(content.size.x * scale)), 1, STAMP_SIZE)
	var fitted_height := clampi(int(round(content.size.y * scale)), 1, STAMP_SIZE)
	cropped.resize(fitted_width, fitted_height, Image.INTERPOLATE_LANCZOS)

	var stamp := Image.create(STAMP_SIZE, STAMP_SIZE, false, Image.FORMAT_RGBA8)
	stamp.blit_rect(
		cropped, Rect2i(0, 0, fitted_width, fitted_height),
		Vector2i((STAMP_SIZE - fitted_width) / 2, (STAMP_SIZE - fitted_height) / 2)
	)
	_stamp_cache[key] = stamp
	return stamp


## The packed atlas: every (species, season) cell laid out side by side in
## one row, each surrounded by its own transparent gutter (see
## STAMP_PADDING) -- the layout cell_uv_rect's own arithmetic assumes.
func build_atlas_image() -> Image:
	var image := Image.create(cell_count() * CELL_SIZE, CELL_SIZE, false, Image.FORMAT_RGBA8)
	for pair in _pairs():
		var index := cell_index(pair[0], pair[1])
		image.blit_rect(
			build_stamp_image(pair[0], pair[1]),
			Rect2i(0, 0, STAMP_SIZE, STAMP_SIZE),
			Vector2i(index * CELL_SIZE + STAMP_PADDING, STAMP_PADDING)
		)
	return image


## The texture the renderer's shared material samples, built once for the
## whole process -- same "every instance shares it, deliberately no mipmaps"
## reasoning as SnowStampAtlas.atlas_texture (a minified mip level would
## bleed a cell's gutter into its neighbour).
func atlas_texture() -> ImageTexture:
	if _atlas_texture == null:
		_atlas_texture = ImageTexture.create_from_image(build_atlas_image())
	return _atlas_texture


## The normalized [0,1] UV rect of cell `index`'s own STAMP content (i.e.
## excluding its gutter) within the whole atlas -- what the renderer packs
## into its own instance data (see LeafLitterRenderer).
func cell_uv_rect(index: int) -> Rect2:
	var atlas_width := float(cell_count() * CELL_SIZE)
	var x0 := float(index * CELL_SIZE + STAMP_PADDING) / atlas_width
	var x1 := float(index * CELL_SIZE + STAMP_PADDING + STAMP_SIZE) / atlas_width
	var y0 := float(STAMP_PADDING) / float(CELL_SIZE)
	var y1 := float(STAMP_PADDING + STAMP_SIZE) / float(CELL_SIZE)
	return Rect2(x0, y0, x1 - x0, y1 - y0)
