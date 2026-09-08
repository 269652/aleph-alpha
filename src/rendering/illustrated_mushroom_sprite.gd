extends RefCounted

## Real illustrated art for MushroomMarker's identified look (see
## docs/concept/mushrooms.md, docs/art/ai_sprite_prompts.md section 12) --
## a 5x5 grid of 25 independent individual specimens per species sheet, not
## an animation. Same "hand/AI-illustrated sheet -> SpriteSheetSlicer ->
## cached frames, picked per-instance by a seeded index" shape as
## IllustratedAntMoundSprite's single mound pool -- just one pool per species
## instead of one pool total, since every species now has its own real sheet.
##
## Two real background conventions among the delivered sheets, confirmed
## by pixel-sampling each one directly rather than assumed from a preview:
## - fly_agaric.png: a genuinely transparent background already (an
##   earlier visual read of it as "solid black" was a wide low-alpha
##   antialiasing fringe composited against a dark preview canvas, not
##   real content -- confirmed by sampling interior background pixels and
##   by running the real slicer over it). No chroma_key entry:
##   SpriteSheetSlicer's own alpha_threshold handles it directly.
## - every other species (including death_cap/false_death_cap, added
##   later once real art surfaced for them -- see docs/progress.md): a
##   solid magenta background (~Color(0.98, 0.01, 0.98), sampled at
##   interior background points -- corners/edges read misleadingly pale
##   due to antialiasing feathering). Uses IllustratedAnimalSprite's
##   simpler single-pass _apply_chroma_key technique (a per-channel-
##   tolerance key-out to full transparency, applied once before slicing)
##   rather than IllustratedStoneSprite/IllustratedAntMoundSprite's
##   cast-removal despill quartet -- proven identically effective on
##   sheep/wolf/the world-boss sheets, and simpler since these are fresh
##   single-pass renders with no resize-induced magenta-cast bleed to
##   clean up afterward.
##
## Crushed/bitten counterparts (see docs/concept/mushrooms.md's "Crushed
## underfoot", docs/concept/soil_fauna.md's decomposer-bite follow-up): real
## 1:1-per-specimen sheets (same 5x5-per-1254x1254-canvas layout, same
## magenta convention as every species' normal sheet except fly_agaric's --
## and confirmed directly by pixel-sampling that even fly_agaric's OWN
## crushed/bitten sheets use magenta, unlike its normal one). Now complete
## for all 8 species on both fronts, delivered incrementally over several
## passes (see docs/progress.md) -- has_crushed_variant/has_bitten_variant
## still gate exactly like has_variants already does, so an unknown or any
## future-missing species id still falls through to a caller-chosen
## fallback rather than erroring. Most bitten sheets came as 3 INDEPENDENT
## delivered images per species rather than one -- _load_frames combines
## every one of them into a single bigger frame pool (see its own doc
## comment) rather than only ever using the first.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const PixelNoise = preload("res://src/rendering/pixel_noise.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")

const _MAGENTA := Color(0.98, 0.01, 0.98)
const _MAGENTA_TOLERANCE := 0.25

## species_id -> {"path": String, "chroma_key": Color, "chroma_key_tolerance": float}.
## chroma_key/chroma_key_tolerance absent for fly_agaric (see class doc
## comment above); present for every other species.
const _SHEETS := {
	"fly_agaric": {"path": "res://assets/sprites/mushrooms/fly_agaric.png"},
	"psylo": {
		"path": "res://assets/sprites/mushrooms/psylo.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"black_trumpet": {
		"path": "res://assets/sprites/mushrooms/black_trumpet.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"champignon": {
		"path": "res://assets/sprites/mushrooms/champignon.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	# Species id is the correctly-spelled "chanterelle" (see
	# MushroomSpecies.SPECIES) -- the delivered sheet's own filename is
	# misspelled "chantarelle.png". Pointed at as-delivered rather than
	# renamed on disk; see docs/art/ai_sprite_prompts.md section 12.
	"chanterelle": {
		"path": "res://assets/sprites/mushrooms/chantarelle.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"parasol": {
		"path": "res://assets/sprites/mushrooms/parasol.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	# Added once real art surfaced for both (see docs/progress.md's
	# mushrooms section) -- same 1254x1254/5-row-band grid, same magenta
	# background convention as every non-fly_agaric sheet above (confirmed
	# by direct pixel-sampling, not assumed).
	"death_cap": {
		"path": "res://assets/sprites/mushrooms/death_cap.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"false_death_cap": {
		"path": "res://assets/sprites/mushrooms/false_death_cap.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
}

## Crushed-underfoot counterparts -- deliberately incomplete (see class doc
## comment): now complete -- all 8 species have a real delivered crushed
## sheet (fly_agaric/psylo/parasol were the last 3, added once real art
## surfaced for them -- see docs/progress.md). Filenames are as-delivered,
## including "champigon" (missing an "n") matching the real file on disk
## -- not renamed, same reasoning as "chantarelle" above.
const _CRUSHED_SHEETS := {
	# Despite fly_agaric.png (the normal look) needing no chroma_key at all
	## (see class doc comment), its crushed/bitten counterparts DO use the
	## standard magenta convention -- confirmed directly by sampling each
	## image's own most-common pixel color, not assumed from the normal
	## sheet's own different convention (a corner-only sample here reads
	## misleadingly near-white, the exact "antialiasing feathering" trap
	## the class doc comment already warns about).
	"fly_agaric": {
		"path": "res://assets/sprites/mushrooms/fly_agaric_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"psylo": {
		"path": "res://assets/sprites/mushrooms/psylo_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"black_trumpet": {
		"path": "res://assets/sprites/mushrooms/black_trumpet_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"champignon": {
		"path": "res://assets/sprites/mushrooms/champignon_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"chanterelle": {
		"path": "res://assets/sprites/mushrooms/chantarelle_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"parasol": {
		"path": "res://assets/sprites/mushrooms/parasol_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"death_cap": {
		"path": "res://assets/sprites/mushrooms/death_cap_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"false_death_cap": {
		"path": "res://assets/sprites/mushrooms/false_death_cap_crushed.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
}

## One-bite-taken counterparts -- now complete for all 8 species (see
## _CRUSHED_SHEETS' own doc comment for the same "now complete" update).
## Most species had 3 INDEPENDENT bitten sheets delivered, not just one --
## "path" is an Array for those, combined into one bigger frame pool by
## _load_frames rather than only ever using the first and leaving the rest
## of the delivered art unused (see that function's own doc comment).
## death_cap has only 1 delivered bitten sheet so far, same shape as every
## _CRUSHED_SHEETS entry -- an honest reflection of what's actually been
## delivered, not a uniform assumption either way. Filenames are
## as-delivered, including "champigon" (missing an "n") and "chantarelle"
## (matching the base sheet's own misspelling) -- not renamed, same
## reasoning as _SHEETS/_CRUSHED_SHEETS above. More bite STAGES (as opposed
## to these same-stage variety frames) are planned later (see
## docs/concept/soil_fauna.md); only one stage exists today.
const _BITTEN_SHEETS := {
	# Same fly_agaric-specific note as _CRUSHED_SHEETS above: these DO need
	# the standard magenta key, confirmed the same way (most-common-pixel
	# sampling, not a misleading corner sample).
	"fly_agaric": {
		"path": [
			"res://assets/sprites/mushrooms/fly_agaric_bitten_1.png",
			"res://assets/sprites/mushrooms/fly_agaric_bitten_2.png",
			"res://assets/sprites/mushrooms/fly_agaric_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"psylo": {
		"path": [
			"res://assets/sprites/mushrooms/psylo_bitten_1.png",
			"res://assets/sprites/mushrooms/psylo_bitten_2.png",
			"res://assets/sprites/mushrooms/psylo_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"black_trumpet": {
		"path": [
			"res://assets/sprites/mushrooms/black_trumpet_bitten_1.png",
			"res://assets/sprites/mushrooms/black_trumpet_bitten_2.png",
			"res://assets/sprites/mushrooms/black_trumpet_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"champignon": {
		"path": [
			"res://assets/sprites/mushrooms/champigon_bitten_1.png",
			"res://assets/sprites/mushrooms/champigon_bitten_2.png",
			"res://assets/sprites/mushrooms/champigon_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"chanterelle": {
		"path": [
			"res://assets/sprites/mushrooms/chantarelle_bitten_1.png",
			"res://assets/sprites/mushrooms/chantarelle_bitten_2.png",
			"res://assets/sprites/mushrooms/chantarelle_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"parasol": {
		"path": [
			"res://assets/sprites/mushrooms/parasol_bitten_1.png",
			"res://assets/sprites/mushrooms/parasol_bitten_2.png",
			"res://assets/sprites/mushrooms/parasol_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	# Only 1 delivered so far (see class doc comment) -- was previously
	# wired to a "death_cap_eaten.png" that no longer exists on disk
	# (replaced by this real, delivered file); fixed as part of the same
	# pass that wired in the rest of the missing bitten art.
	"death_cap": {
		"path": "res://assets/sprites/mushrooms/death_cap_bitten_1.png",
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
	"false_death_cap": {
		"path": [
			"res://assets/sprites/mushrooms/false_death_cap_bitten_1.png",
			"res://assets/sprites/mushrooms/false_death_cap_bitten_2.png",
			"res://assets/sprites/mushrooms/false_death_cap_bitten_3.png",
		],
		"chroma_key": _MAGENTA,
		"chroma_key_tolerance": _MAGENTA_TOLERANCE,
	},
}

## Five content rows, identical across every sheet -- all six are the same
## 1254x1254 canvas divided into 5 equal bands (measured directly, not
## assumed). Confirmed identical for the crushed/bitten sheets too.
const _ROW_BANDS := [
	Vector2i(0, 251), Vector2i(251, 502), Vector2i(502, 752), Vector2i(752, 1003), Vector2i(1003, 1254)
]

## A mushroom has no walk cycle to bob -- like IllustratedAntMoundSprite's
## mound, BASELINE_Y is simply the canvas bottom, standing every specimen's
## own base on the same line with no wasted ground margin.
const CANVAS_SIZE := Vector2i(64, 64)
const BASELINE_Y := 64

var _slicer := SpriteSheetSlicer.new()

static var _frames_cache: Dictionary = {}
static var _crushed_frames_cache: Dictionary = {}
## species_id -> Array of per-stage Array[ImageTexture] (one inner array per
## real delivered bitten sheet, in stage order -- see bitten_frame_for's own
## doc comment). Replaced 2026-09-07's flat, stage-blind pool (every
## delivered sheet combined into one same-stage variety pool) -- see
## docs/concept/soil_fauna.md's "Progressive, mass-scaled bites, and real
## toxic effects": those 3 delivered sheets per species are real progressive
## STAGES now, not interchangeable variety.
static var _bitten_stage_frames_cache: Dictionary = {}
static var _marker_scale_cache: Dictionary = {}


## Whether there is a real illustrated sheet registered for `species_id`.
## True for every roster species today -- kept as an explicit gate anyway,
## the same has_X()-before-frame_for() convention every other optional
## illustrated-art seam in this codebase uses.
func has_variants(species_id: String) -> bool:
	return _SHEETS.has(species_id)


func frame_count(species_id: String) -> int:
	return _frames_from(_SHEETS, _frames_cache, species_id).size()


## One deterministically-picked variant for `seed_value`, or null if
## `species_id` has no registered sheet. Every marker with the same seed
## always picks the same variant, and different seeds spread across the
## sheet's full variant count via PixelNoise.range_index's bucket-avoidance
## (mirrors IllustratedAntMoundSprite.frame_for exactly).
func frame_for(species_id: String, seed_value: int) -> ImageTexture:
	return _pick_frame(_frames_from(_SHEETS, _frames_cache, species_id), seed_value)


## Whether `species_id` has a real crushed-underfoot sheet yet (see class
## doc comment -- delivered incrementally, not every species has one).
func has_crushed_variant(species_id: String) -> bool:
	return _CRUSHED_SHEETS.has(species_id)


## The crushed counterpart of the specimen `seed_value` would otherwise pick
## via frame_for -- same seed, same index-selection shape, so a crushed
## mushroom reads as the SAME specimen once both sheets share the normal
## 25-frame count (see class doc comment for the "not complete yet"
## caveat). Null if `species_id` has no crushed sheet at all.
func crushed_frame_for(species_id: String, seed_value: int) -> ImageTexture:
	return _pick_frame(_frames_from(_CRUSHED_SHEETS, _crushed_frames_cache, species_id), seed_value)


func crushed_frame_count(species_id: String) -> int:
	return _frames_from(_CRUSHED_SHEETS, _crushed_frames_cache, species_id).size()


## Whether there is real bitten-mushroom art registered for `species_id` --
## see _BITTEN_SHEETS' own doc comment for which species have it so far.
func has_bitten_variant(species_id: String) -> bool:
	return _BITTEN_SHEETS.has(species_id)


## How many real frames exist at bite `stage` (1-based, matching
## MushroomBiting.MAX_BITE_STAGES) for `species_id` -- always 25 for a
## known species regardless of stage (a stage past what was really
## delivered clamps to the last real one, see _bitten_frames_for_stage), 0
## for an unknown/undelivered species, the same "0, not an error" contract
## frame_count already has.
func bitten_frame_count(species_id: String, stage: int = 1) -> int:
	return _bitten_frames_for_stage(species_id, stage).size()


## The counterpart of the specimen `seed_value` would otherwise pick via
## frame_for, once it has been bitten `stage` times (1-based) -- see
## crushed_frame_for's own doc comment for the identical seed-driven
## per-specimen-consistency reasoning, now also varying by stage so a
## mushroom's own look genuinely advances as it is bitten further (see
## docs/concept/soil_fauna.md's "Progressive, mass-scaled bites, and real
## toxic effects"). `stage` clamps into whatever range is real for this
## species -- below 1 clamps to 1, past the real delivered stage count
## clamps to the last one (death_cap's own single delivered sheet, e.g.,
## answers every stage identically -- the same has-art-or-doesn't
## convention every optional illustrated-art seam in this codebase already
## uses). Null if `species_id` has no bitten sheet at all.
func bitten_frame_for(species_id: String, seed_value: int, stage: int = 1) -> ImageTexture:
	return _pick_frame(_bitten_frames_for_stage(species_id, stage), seed_value)


## `stage`'s own real frame pool for `species_id`, clamped into range --
## see bitten_frame_for's own doc comment. Empty for an unknown species.
func _bitten_frames_for_stage(species_id: String, stage: int) -> Array:
	var stages := _bitten_stages_from(species_id)
	if stages.is_empty():
		return []
	var clamped_index: int = clampi(stage, 1, stages.size()) - 1
	return stages[clamped_index]


func _bitten_stages_from(species_id: String) -> Array:
	if not _BITTEN_SHEETS.has(species_id):
		return []
	if not _bitten_stage_frames_cache.has(species_id):
		_bitten_stage_frames_cache[species_id] = _load_bitten_stages(_BITTEN_SHEETS[species_id])
	return _bitten_stage_frames_cache[species_id]


## Eagerly loads every registered species' normal/crushed/bitten frame
## cache, instead of leaving each to fill lazily on whichever call happens
## to ask for it first. Real bug found live: DecomposerMarker._step_feeding
## eating a not-yet-bitten mushroom is exactly such a first ask -- a real
## sprite sheet load + whole-image chroma-key pass (bitten sheets combine
## up to 3 separate full-resolution images, see _load_frames), measured
## live on this session's own machine at up to ~1.6s for a SINGLE bite on
## a species nothing had rendered a bitten look for yet (see
## docs/concept/soil_fauna.md's fps round 6 write-up). That cost was
## always going to be paid once per species per process -- the bug was
## only ever WHEN: a random live gameplay frame, unpredictably, rather
## than once here, before anything can possibly ask. Idempotent (routes
## through the exact same _frames_from cache-check every ordinary call
## already uses), so calling this more than once -- or a species some
## earlier lazy call already warmed -- is a cheap no-op, not a reload.
##
## A SECOND real bug found live, later: this whole pass used to run as one
## uninterrupted synchronous loop, which measured at ~52 real seconds on
## this session's own machine -- 8 species x up to 3 real sheet loads
## each, none of them yielding. Long enough that Windows marks the whole
## boot window "Not Responding" and paints it grey for the entire stretch,
## regardless of anything World._ready() shows before or after it
## (reported directly, a third time, about the boot logo intro that plays
## right after: "it hangs for a minute or two when starting and just
## shows a grey window"). Now yields via `await Engine.get_main_loop().
## process_frame` after every real sheet load -- the same "one real unit
## of work, then give the engine a frame back" shape EarthChunkManager.
## update_with_progress already established for the equally-long cold
## chunk load, right down to the optional `on_progress` callback (unused
## by any caller yet, wired for the same reason update_with_progress's
## is: a future boot-time loading readout, not invented here). The bitten
## stages are unrolled into their own per-sheet loop rather than calling
## bitten_frame_for()/_load_bitten_stages() as one opaque call -- a single
## species can deliver up to 3 full-resolution bitten sheets, which would
## otherwise still be one uninterrupted multi-second block even with a
## yield on either side of it. frame_for()/crushed_frame_for() stay single
## calls: each is already exactly one sheet load, as fine-grained as this
## can usefully get without touching _load_one_sheet itself (which live
## gameplay calls synchronously and must keep returning a real texture
## immediately, not a coroutine).
func warm_cache(on_progress: Callable = Callable()) -> void:
	var species_ids: Array = _SHEETS.keys()
	var total := species_ids.size()
	var done := 0
	if on_progress.is_valid():
		on_progress.call(0, total)
	for species_id in species_ids:
		if has_variants(species_id):
			frame_for(species_id, 0)
			await Engine.get_main_loop().process_frame
		if has_crushed_variant(species_id):
			crushed_frame_for(species_id, 0)
			await Engine.get_main_loop().process_frame
		if has_bitten_variant(species_id) and not _bitten_stage_frames_cache.has(species_id):
			var sheet: Dictionary = _BITTEN_SHEETS[species_id]
			var stages: Array = []
			for path in _stage_paths_for(sheet):
				stages.append(_load_one_sheet(path, sheet))
				await Engine.get_main_loop().process_frame
			_bitten_stage_frames_cache[species_id] = stages
		done += 1
		if on_progress.is_valid():
			on_progress.call(done, total)


func _pick_frame(frames: Array, seed_value: int) -> ImageTexture:
	if frames.is_empty():
		return null
	var index: int = PixelNoise.range_index(seed_value, 0, 0, frames.size())
	return frames[index]


func _frames_from(sheets: Dictionary, cache: Dictionary, species_id: String) -> Array:
	if not sheets.has(species_id):
		return []
	if not cache.has(species_id):
		cache[species_id] = _load_frames(sheets[species_id])
	return cache[species_id]


## `sheet["path"]` for _SHEETS/_CRUSHED_SHEETS is always a single path --
## one real delivered sheet, sliced into its 25-frame pool. (_BITTEN_SHEETS
## entries can carry an Array of several delivered sheets instead -- see
## _load_bitten_stages below, which loads each one as its own separate
## STAGE rather than flattening them together the way an earlier version of
## this function once did.)
func _load_frames(sheet: Dictionary) -> Array[ImageTexture]:
	return _load_one_sheet(sheet["path"], sheet)


## Every real frame in ONE delivered sheet at `path`, sliced and (if
## `sheet` names a chroma_key) despilled -- the actual per-sheet work
## _load_frames/_load_bitten_stages both need, factored out so neither has
## to duplicate the chroma-key/band-slicing sequence.
func _load_one_sheet(path: String, sheet: Dictionary) -> Array[ImageTexture]:
	var image := SpriteSheetLoader.load_image(path)
	# Turning the chroma-keyed background transparent up front lets the
	# exact same downstream detect_frames/normalize_frames (via
	# SpriteSheetSlicer.is_empty's alpha check) handle it with no
	# separate "or matches this color" branch -- same reasoning as
	# IllustratedAnimalSprite._slice_bands.
	if sheet.has("chroma_key"):
		image = _apply_chroma_key(image, sheet["chroma_key"], sheet["chroma_key_tolerance"])
	var textures: Array[ImageTexture] = []
	for band in _ROW_BANDS:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 60, 1)
		for frame_image in _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y):
			textures.append(ImageTexture.create_from_image(frame_image))
	return textures


## `sheet["path"]` is either a single path (a species with only one
## delivered bitten sheet so far, e.g. death_cap) or an Array of paths, in
## real stage order (most species: 3 independently-delivered sheets, one
## per bite stage -- see docs/concept/soil_fauna.md's "Progressive,
## mass-scaled bites, and real toxic effects"). Returns one real 25-frame
## pool PER delivered sheet, kept separate by stage -- unlike _load_frames,
## this does NOT flatten them together, since each one is now a genuinely
## different look, not interchangeable variety on the same look.
func _load_bitten_stages(sheet: Dictionary) -> Array:
	var stages: Array = []
	for path in _stage_paths_for(sheet):
		stages.append(_load_one_sheet(path, sheet))
	return stages


## Shared with warm_cache(), which needs the same per-stage path list but
## loads each one across its own yielded frame instead of in one
## uninterrupted loop -- see that function's own doc comment for why.
func _stage_paths_for(sheet: Dictionary) -> Array:
	return sheet["path"] if sheet["path"] is Array else [sheet["path"]]


## A copy of `image` with every pixel within `tolerance` of `key` (each of
## R/G/B independently, ignoring alpha) turned fully transparent --
## IllustratedAnimalSprite's own technique (see its doc comment there), not
## IllustratedAntMoundSprite's cast-removal despill quartet: these are
## fresh single-pass renders with no resize-induced magenta-cast bleed to
## clean up afterward, so one pass before slicing is enough.
func _apply_chroma_key(image: Image, key: Color, tolerance: float) -> Image:
	var keyed := image.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	for y in keyed.get_height():
		for x in keyed.get_width():
			var c: Color = keyed.get_pixel(x, y)
			if (
				absf(c.r - key.r) <= tolerance
				and absf(c.g - key.g) <= tolerance
				and absf(c.b - key.b) <= tolerance
			):
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
	return keyed


## How much to scale a CANVAS_SIZE-normalized frame so it reads at
## ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH on screen -- the same
## real-world width the procedural fallback already uses, measured from
## the real art's own opaque width per species rather than assumed to
## match the canvas proportions (mirrors IllustratedAntMoundSprite/
## IllustratedAnimalSprite marker_scale). Cached per species: art doesn't
## change once loaded. Reused as-is for the crushed/bitten look of the
## same species -- a simplification (see class doc comment): a squashed or
## bitten specimen's own opaque-pixel spread is not measured separately, on
## the assumption it reads close enough to the same real specimen's own
## normal-frame size.
func marker_scale(species_id: String) -> float:
	if not _SHEETS.has(species_id):
		return 1.0
	if _marker_scale_cache.has(species_id):
		return _marker_scale_cache[species_id]
	var frames := _frames_from(_SHEETS, _frames_cache, species_id)
	if frames.is_empty():
		return 1.0
	var image: Image = frames[0].get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var reference_width := float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	var scale_value: float = ProceduralMushroomSprite.MUSHROOM_WORLD_WIDTH / reference_width
	_marker_scale_cache[species_id] = scale_value
	return scale_value
