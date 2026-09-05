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
## for any pair that lacks it. Every one of the 6 species x 3 FALLING
## seasons ("spring"/"summer"/"autumn" -- see SEASONS' own doc comment)
## this project ships today actually HAS real illustrated art (verified
## directly), so the fallback path exists for whenever a future species/
## season genuinely lacks art, not because one currently does -- though
## spring's own art quality varies by species: cherry's is a genuinely
## recognisable blossom, while acorn/hazelnut/walnut/apple land on a
## green, leaf-toned crop instead (not blank or broken, just less floral
## than hoped) and pine lands on the same winged-seed-pair crop its own
## already-known autumn imperfection uses -- named in docs/concept/
## leaf_litter.md rather than hidden, the same as that pine/autumn gap
## always has been. The fourth season, "winter" -- a settled leaf's own
## terminal DECAY stage, not a season it can fall in -- is never
## illustrated for any species and never falls to the generic fallback
## either; see build_stamp_image's own special case and
## _decayed_winter_stamp.

const IllustratedTree = preload("res://src/rendering/illustrated_tree.gd")
const IllustratedCropSprite = preload("res://src/rendering/illustrated_crop_sprite.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")

## The three seasons a leaf/blossom actually FALLS in (see
## EarthChunkManager.step_fruiting's own leaf-fall block), plus "winter"
## and "fading": neither a season anything falls in at all, but the two
## later DECAY stages every settled leaf eventually passes through (see
## LeafLitterField.DECAY_TO_FADING_SECONDS/DECAY_TO_WINTER_SECONDS).
## Included here as real cells like any other so the renderer can address
## them the same way -- see build_stamp_image's own special cases for how
## their art is produced without any actual "fading"/"winter" illustration
## existing. "spring" needs no equivalent special case: IllustratedTree.
## foliage_leaf_for already resolves real blossom art for it (see that
## function's own doc comment), so it flows through the exact same
## has_illustrated_art/generic-fallback path summer/autumn always have.
const SEASONS := ["spring", "summer", "autumn", "winter", "fading"]

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

## -- "winter": a settled leaf's derived terminal-decay recolour ------------
##
## No species has real illustrated "winter" litter art (see SEASONS' own
## doc comment), so every winter stamp is DERIVED from that same species'
## own already-built AUTUMN stamp by _decayed_winter_stamp, using the exact
## luminance-preserving recolour ProceduralFlowerSprite._paint_illustrated_
## head already established for repainting illustrated art a different
## colour without losing its own shading (see that function's own doc
## comment) -- here reading the autumn stamp's own light/shade as `shade`
## and painting WINTER_TINT at that brightness, rather than reading a
## neutral/pale source sheet.

## A dulled, desaturated brown-grey -- the common real end state of
## decomposing plant litter (leaf mould/humus), not any one species' own
## vivid autumn hue. Deliberately low-saturation (unlike any real autumn
## colour this project draws) so a decayed leaf reads as duller than a
## freshly-fallen one at a glance, pinned by test_winter_stamp_is_less_
## saturated_than_autumn in test_leaf_litter_atlas.gd.
const WINTER_TINT := Color(0.45, 0.39, 0.32)

## Same value and reasoning as ProceduralFlowerSprite.ILLUSTRATED_SHADE_
## FLOOR: without a floor the source stamp's own darkest linework multiplies
## down to near-black, which at this size reads as a hole rather than as
## shading.
const WINTER_SHADE_FLOOR := 0.35

## Same value and reasoning as ProceduralFlowerSprite.MINIMUM_PEAK_
## LUMINANCE: guards the shading division so a stamp with an unusually dark
## peak is not stretched into a blown-out result.
const WINTER_PEAK_LUMINANCE_FLOOR := 0.35

## -- "fading": the halfway stage between a leaf's own fall colour and -----
## -- "winter" --------------------------------------------------------------
##
## Reported directly: "leaf decay should be 3 seasons" (clarified: "leafs
## should take roughly 270 days to rot / decay / vanish", ~3 real seasons
## -- see LeafLitterField.LIFETIME/DECAY_TO_FADING_SECONDS' own doc
## comments). No species has real "half-decayed" litter art either (the
## same reason "winter" has none), so "fading" is derived again -- but from
## two stamps this atlas has already built rather than a fresh recolour
## pass: a straight per-pixel blend between that species' own real autumn
## stamp and its already-derived winter stamp. The winter stamp's own
## recolour (luminance-preserving, shade-floor guarded) already did the
## hard part of turning illustrated art into a believable decayed colour;
## "fading" only needs to land partway there.

## Exactly halfway -- not an independently-tuned number. The report's own
## "3 seasons" framing already fixes the TIMING at an even three-way split
## (LeafLitterField.DECAY_TO_FADING_SECONDS/DECAY_TO_WINTER_SECONDS), and
## colour is the one thing this atlas controls to match that: a leaf
## spends its middle third exactly as far from "just fell" as it is from
## "fully decayed", so the colour should sit at the same midpoint the
## timing already does, pinned by test_fading_stamp_is_the_pinned_blend_
## of_autumn_and_winter in test_leaf_litter_atlas.gd.
const FADING_BLEND := 0.5

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

	if season == "winter":
		# Derived, not authored -- see this file's own "winter" section doc
		# comment. Intercepted here, before _source_image, so this never
		# falls through to has_illustrated_art/the generic procedural
		# fallback the way a genuinely-missing species/season pair would.
		var winter_stamp := _decayed_winter_stamp(build_stamp_image(species, "autumn"))
		_stamp_cache[key] = winter_stamp
		return winter_stamp

	if season == "fading":
		# Derived from two ALREADY-BUILT stamps -- see this file's own
		# "fading" section doc comment. Building "winter" first (if not
		# already cached) means this never duplicates its recolour work.
		var fading_stamp := _fading_stamp(
			build_stamp_image(species, "autumn"), build_stamp_image(species, "winter")
		)
		_stamp_cache[key] = fading_stamp
		return fading_stamp

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


## Recolours `autumn_stamp` (species' own real illustrated art, already
## cropped/fitted to STAMP_SIZE) into a decayed "winter" stamp of the exact
## same silhouette -- see this file's own "winter" section doc comment for
## why this is a recolour rather than real art. Reads each opaque pixel's
## own Rec. 709 luminance as `shade` (relative to the stamp's own peak, so
## the brightest highlight still reads as fully lit WINTER_TINT rather than
## a dimmed version of it) and paints WINTER_TINT at that same brightness --
## identical technique to ProceduralFlowerSprite._paint_illustrated_head,
## just reading an already-coloured stamp's luminance as the shade signal
## instead of a neutral/pale source sheet's.
func _decayed_winter_stamp(autumn_stamp: Image) -> Image:
	var winter := autumn_stamp.duplicate()
	var peak := 0.0
	for y in autumn_stamp.get_height():
		for x in autumn_stamp.get_width():
			var pixel := autumn_stamp.get_pixel(x, y)
			if pixel.a <= CONTENT_ALPHA_THRESHOLD:
				continue
			peak = maxf(peak, _luminance(pixel))
	peak = maxf(peak, WINTER_PEAK_LUMINANCE_FLOOR)
	for y in autumn_stamp.get_height():
		for x in autumn_stamp.get_width():
			var pixel := autumn_stamp.get_pixel(x, y)
			if pixel.a <= CONTENT_ALPHA_THRESHOLD:
				continue
			var shade := _luminance(pixel) / peak
			var lit := WINTER_SHADE_FLOOR + (1.0 - WINTER_SHADE_FLOOR) * shade
			winter.set_pixel(
				x, y,
				Color(WINTER_TINT.r * lit, WINTER_TINT.g * lit, WINTER_TINT.b * lit, pixel.a)
			)
	return winter


## Rec. 709 luminance: a pixel's light and shade, none of its colour. Same
## formula and reasoning as ProceduralFlowerSprite._luminance.
func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## Blends `autumn_stamp` and `winter_stamp` (the same species' own stamps,
## same silhouette by construction -- see this file's own "fading" section
## doc comment) at FADING_BLEND, per pixel. A straight Color.lerp rather
## than a fresh luminance-preserving recolour: both source stamps already
## carry real, correctly-shaded content, so the midpoint of two believable
## colours at the same brightness is itself a believable colour at that
## brightness -- no new shading logic needed. Alpha lerps identically
## (both sources share the same silhouette), so the shape never drifts.
func _fading_stamp(autumn_stamp: Image, winter_stamp: Image) -> Image:
	var fading := autumn_stamp.duplicate()
	for y in autumn_stamp.get_height():
		for x in autumn_stamp.get_width():
			var autumn_pixel := autumn_stamp.get_pixel(x, y)
			if autumn_pixel.a <= CONTENT_ALPHA_THRESHOLD:
				continue
			var winter_pixel := winter_stamp.get_pixel(x, y)
			fading.set_pixel(x, y, autumn_pixel.lerp(winter_pixel, FADING_BLEND))
	return fading


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
