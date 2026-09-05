extends RefCounted

## Real illustrated art for the decomposer tier (ants and carrion bugs --
## see DecomposerMarker, docs/concept/carrion.md), replacing
## ProceduralDecomposerSprite's drawn silhouettes where real art now exists.
## Same "hand-drawn sheet -> SpriteSheetSlicer -> cached frames" shape as
## IllustratedAnimalSprite, deliberately NOT built on it directly: decomposers
## are not on the CreatureMarker/AnimalAnatomy stack at all (see
## DecomposerMarker's own doc comment on why a tiny insect doesn't need that
## full roaming-wildlife AI), so this class carries none of that stack's
## per-species anatomy profile or swim/drink/attack fallback chain -- just
## the three actions a decomposer actually has: "walk" (ambient wander and
## approach), "carry" (an ant hauling cached food -- see AntForagerMarker),
## and "idle" (feeding in place).
##
## has_species()-gated, same fallback convention every optional illustrated-
## art seam in this codebase uses: a species with no entry here reports
## false and the caller falls all the way through to
## ProceduralDecomposerSprite, exactly the way DecomposerMarker/
## AntForagerMarker already need to keep working the moment a THIRD
## decomposer species is added with no art yet.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## The canvas every sliced frame is normalized onto, its feet landing on the
## same BASELINE_Y regardless of species/action -- mirrors
## IllustratedAnimalSprite.CANVAS_SIZE/BASELINE_Y exactly, sized for these
## two sheets' own largest content (measured: the ant's carry-row silhouette,
## body plus carried cargo, is the widest frame either sheet draws).
const CANVAS_SIZE := Vector2i(340, 300)
const BASELINE_Y := 280

## How wide (world pixels) an ant should read on screen -- shrunk from the
## art's own old shared width (see BUG_WORLD_WIDTH's doc comment): reported
## as oversized once ants/mounds actually had a rendered presence in play
## (docs/concept/soil_fauna.md "Ants at half their old size"), not when
## this was pure background population math with nothing to look at yet.
## A literal halving (6.0 -> 3.0) overshot the other way -- reported live
## right after relaunch as "I see no ant whatsoever": a thin, many-legged,
## low-contrast silhouette at ~3 world pixels wide against a 16px tile is
## genuinely sub-perceptual, not merely small. Corrected to a 25% reduction
## from the original instead of 50% (see that doc's own 2026-09-05
## follow-up) -- smaller than before, but not invisible.
const ANT_WORLD_WIDTH := 4.5

## How wide (world pixels) a carrion bug should read on screen -- matches
## ProceduralDecomposerSprite.SIZE (12) drawn at ArtResolution.SPRITE_SCALE
## (0.5) exactly, so switching a species over to illustrated art is a pure
## art upgrade, not a sudden size change. Unchanged from when this and
## ANT_WORLD_WIDTH were one shared constant -- a carrion beetle is a
## genuinely different, larger insect, and nothing about ants reading
## oversized in play was ever a claim about bugs too.
const BUG_WORLD_WIDTH := 6.0


## `species`'s own real-world width -- see ANT_WORLD_WIDTH/BUG_WORLD_WIDTH's
## own doc comments for why these are no longer one shared constant.
## Anything not "ant" falls back to BUG_WORLD_WIDTH rather than failing
## outright; has_species()/has_action() are what actually gate whether a
## caller may ask for a species at all; this only backstops the "no frames"
## defensive branch inside _reference_width below, which per has_action's
## own contract should never really be reachable for a species this file
## knows about.
static func _world_width_for(species: String) -> float:
	if species == "ant":
		return ANT_WORLD_WIDTH
	return BUG_WORLD_WIDTH

## species -> sheet metadata. "<action>_bands" are ARRAYS of Y ranges
## (Vector2i(top_y, bottom_y)) into the one shared sheet -- see
## SpriteSheetSlicer.detect_frames's own top_y/bottom_y parameters. Bands
## measured directly from the real PNGs (a divider band reads as
## near-uniform chroma-key magenta across the full width; everything
## between two such bands is one row's own content) -- see
## tools/probe_decomposer_sheets.gd for the measurement this project keeps
## visible rather than eyeballed.
##
## ant.png (1698x926, 6 columns): row 1 (95-250) a plain walk cycle; row 2
## (397-550) the SAME walk cycle carrying a pale food/seed object near the
## abdomen -- AntForagerMarker's own cargo leg, not DecomposerMarker's
## ambient wander; row 3 (710-850) a shorter, legs-gathered cycle read as
## "idle" (DecomposerMarker's FEEDING phase).
##
## beetle.png (2079x756, 6 columns): row 1 (107-308) walk; row 2 (458-660)
## the same shorter legs-gathered "idle" cycle. No carry row -- a carrion
## bug doesn't cache food the way an ant's colony does (see AntColony's own
## doc comment: bugs are DecomposerMarker's carrion tier only).
const _SHEETS := {
	"ant": {
		"path": "res://assets/sprites/animals/ant.png",
		"walk_bands": [Vector2i(95, 250)],
		"carry_bands": [Vector2i(397, 550)],
		"idle_bands": [Vector2i(710, 850)],
		"faces_left": true,
	},
	"bug": {
		"path": "res://assets/sprites/animals/beetle.png",
		"walk_bands": [Vector2i(107, 308)],
		"idle_bands": [Vector2i(458, 660)],
		"faces_left": true,
	},
}

## Chroma-keyed magenta, not real alpha -- both sheets measure fully OPAQUE
## (alpha channel present but always 1.0), so the "already has real alpha"
## shortcut IllustratedStoneSprite/_prepared_for_slicing uses does not apply
## here; every pixel is checked against this key regardless of the source
## format. Measured directly from the sheets' own corners (four corners,
## both files, all read ~(0.98, 0.01, 0.99)) rather than assumed to match
## sheep.png's own (0.95, 0.02, 0.96) by coincidence. Bounds, not a single
## exact color: compression/antialiasing shifts real corner pixels slightly
## off pure magenta.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _ALPHA_THRESHOLD := 0.3

## Despill, not just a binary key (same technique and reasoning as
## IllustratedStoneSprite.MAGENTA_CAST_MARGIN, reused verbatim rather than
## reinvented): a binary "is this pure magenta" test alone left a visible
## pink halo around every ant/beetle leg -- an antialiased edge blends the
## drawing's own dark chitin against the magenta ground, baking a whole
## GRADIENT of magenta-tinted dark tones into the source, and no single
## threshold catches a gradient, only its purest end (confirmed live: this
## class's own test_no_frame_carries_leftover_magenta failed on the ant's
## carry frames before this constant existed). Red/blue are clamped down
## toward green -- the direction magenta leans away from -- rather than the
## pixel being zeroed outright, so a genuine soft shadow/outline along a
## leg survives as a shadow instead of a hard-edged hole.
const _MAGENTA_CAST_MARGIN := 0.03

var _slicer := SpriteSheetSlicer.new()

## Keyed by "species/action", shared across instances -- every ant/bug
## drawing the same action reuses the identical sliced frames (mirrors
## IllustratedAnimalSprite._frame_cache).
static var _frame_cache: Dictionary = {}
static var _marker_scale_cache: Dictionary = {}
static var _reference_width_cache: Dictionary = {}


func has_species(species: String) -> bool:
	return _SHEETS.has(species)


## Whether this species' sheet is drawn facing LEFT -- both are, today; kept
## data-driven per sheet (mirrors IllustratedAnimalSprite.faces_left) rather
## than hardcoded true, since nothing here guarantees a future third
## species' art will share that convention.
func faces_left(species: String) -> bool:
	if not _SHEETS.has(species):
		return false
	return _SHEETS[species].get("faces_left", false)


## Data-driven on whichever "<action>_bands" keys the species' sheet
## actually defines -- "bug" has no carry_bands (see _SHEETS' own doc
## comment), so has_action(_, "carry") is false for it and AntForagerMarker
## (ant-only regardless) never asks anyway.
func has_action(species: String, action: String) -> bool:
	if not _SHEETS.has(species):
		return false
	return _SHEETS[species].has(action + "_bands")


## The registered frames for `species`/`action`, sliced+normalized once and
## cached thereafter. Empty for anything has_action would reject -- callers
## must check has_action first and fall back to ProceduralDecomposerSprite
## themselves, the same "ask before you leap" shape every other optional
## illustrated-art seam in this codebase uses.
func generate_textures(species: String, action: String) -> Array[ImageTexture]:
	if not has_action(species, action):
		return []
	var key := "%s/%s" % [species, action]
	if not _frame_cache.has(key):
		_frame_cache[key] = _build_textures(species, action)
	return _frame_cache[key]


func _build_textures(species: String, action: String) -> Array[ImageTexture]:
	var sheet: Dictionary = _SHEETS[species]
	var image := _prepared_for_slicing(SpriteSheetLoader.load_image(sheet["path"]))
	var textures: Array[ImageTexture] = []
	for band in sheet[action + "_bands"]:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(
			image, rect.x, rect.y, 60, 1, _ALPHA_THRESHOLD
		)
		for frame_image in _slicer.normalize_frames(
			image, frames, CANVAS_SIZE, BASELINE_Y, _ALPHA_THRESHOLD
		):
			# A second, final cleanup pass over each already-cropped-and-
			# resized SMALL frame -- SpriteSheetSlicer's own crop+Lanczos
			# resize can still ring a few output pixels back toward a
			# magenta cast even once the SOURCE sheet has been despilled
			# above, since resizing blends a transparent background pixel
			# with an adjacent opaque one and can overshoot (same
			# reasoning as IllustratedStoneSprite._scrub_magenta_fringe).
			_despill_image(frame_image)
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## Makes the sheet's magenta background genuinely transparent, and despills
## the magenta cast baked into every antialiased edge around it, before the
## image ever reaches SpriteSheetSlicer -- mirrors
## IllustratedStoneSprite._prepared_for_slicing, minus its "already has
## real alpha" shortcut (see _MAGENTA_RED_MIN's own doc comment on why that
## shortcut does not apply to these two sheets).
func _prepared_for_slicing(image: Image) -> Image:
	var prepared := image.duplicate() as Image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared.convert(Image.FORMAT_RGBA8)
	for y in prepared.get_height():
		for x in prepared.get_width():
			var pixel := prepared.get_pixel(x, y)
			if _is_magenta(pixel):
				prepared.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
			else:
				prepared.set_pixel(x, y, _despilled(pixel))
	return prepared


## Two passes over an already-cropped-and-resized frame, in place: pixels
## close enough to PURE magenta are treated as background outright (a one-
## pixel transparent gap at pixel-art scale is invisible, where an opaque
## magenta pixel is not); anything left with a softer cast is despilled
## rather than deleted, so a genuine soft shadow/outline survives as a
## shadow instead of being punched into a hard-edged hole.
func _despill_image(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


## `color` with any magenta-direction cast removed (see
## _MAGENTA_CAST_MARGIN's own doc comment) -- identical technique to
## IllustratedStoneSprite._despilled. A pixel with no cast (a genuine dark
## chitin tone) passes through completely unchanged.
static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)


## How much to scale a CANVAS_SIZE-normalized frame so it reads at this
## species' own real-world width (see ANT_WORLD_WIDTH/BUG_WORLD_WIDTH) on
## screen -- mirrors IllustratedAnimalSprite.marker_scale exactly, minus
## the AnimalAnatomy.world_scale factor (decomposers have no anatomy
## profile). Measured per species/action, not one flat constant, for the
## same reason IllustratedAnimalSprite measures per action: normalize_frames
## fits EACH band's own widest frame to the canvas independently, so a
## wider drawing (the ant's carry pose, body plus cargo) would otherwise
## read as a BIGGER creature than its own walk cycle purely from being
## normalized separately -- measuring and compensating per action is what
## keeps a species reading as one consistent size across every action it
## has.
func marker_scale(species: String, action: String = "walk") -> float:
	if not _SHEETS.has(species):
		return 1.0
	var key := "%s/%s" % [species, action]
	if _marker_scale_cache.has(key):
		return _marker_scale_cache[key]
	var scale_value := _world_width_for(species) / _reference_width(species, action)
	_marker_scale_cache[key] = scale_value
	return scale_value


## Frame 0's own opaque-pixel width for this species/action, measured once
## and cached -- mirrors IllustratedAnimalSprite._reference_width.
func _reference_width(species: String, action: String) -> float:
	var key := "%s/%s" % [species, action]
	if _reference_width_cache.has(key):
		return _reference_width_cache[key]
	var frames := generate_textures(species, action)
	var width := _world_width_for(species)
	if not frames.is_empty():
		var image: Image = frames[0].get_image()
		var min_x := image.get_width()
		var max_x := -1
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.0:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
		if max_x >= min_x:
			width = float(max_x - min_x + 1)
	_reference_width_cache[key] = width
	return width
