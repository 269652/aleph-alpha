extends RefCounted

## Real hand/AI-illustrated sprite-sheet animation for species with actual
## art (assets/sprites/*.png -- currently horse, deer, boar; see
## SpriteSheetSlicer for how a hand-assembled reference sheet becomes clean,
## aligned frames), replacing ProceduralAnimalSprite's primitive-shape
## generation for just those species. Reported: "the procedural generated
## sprites are too bad... let's switch to illustrated ones" -- every other
## species keeps the procedural generator entirely (see CreatureMarker.
## _animation_step, which checks has_species()/has_action() first and falls
## back to ProceduralAnimalAnimation whenever this class doesn't cover the
## request).
##
## Each source sheet is a small set of action rows, hand-composited (not a
## uniform grid -- pose extents genuinely differ frame to frame, and rows
## can differ in frame count from each other) with thin divider lines
## between cells -- exactly which actions a given species' sheet covers
## varies (deer/boar: walk + eat; horse: idle + walk, no eat -- see
## _SHEETS and has_action's own doc comments). There is no swim/drink/
## attack art for any species, and no per-seed variation (unlike the
## procedural generator, every creature of a given species shows the exact
## same illustrated frames) -- both explicitly out of scope for now.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const AnimalAnatomy = preload("res://src/rendering/animal_anatomy.gd")

## Every frame, from every registered species and action, is re-composited
## onto this SAME canvas size with its ground-contact row landing on the same
## BASELINE_Y -- one shared convention, not something computed per sheet, so
## a marker's texture can swap between actions (or even -- not that any
## caller does today -- between species) without its apparent size/anchor
## jumping around. Sized with margin around the largest registered frame
## across every species/action (measured 302x293, a deer's alert head-up
## eat-cycle pose) -- too little margin overflows the canvas outright
## (Image.set_pixel errors on an out-of-bounds index, not a silent clip).
const CANVAS_SIZE := Vector2i(340, 330)
const BASELINE_Y := 310

## How wide (world pixels) a species with AnimalAnatomy.world_scale == 1.0
## should read on screen -- the same "one shared unit, scaled per species"
## convention CreatureRenderer already applies to the procedural generator
## (see AnimalAnatomy.world_scale's own doc comment), so an illustrated
## horse/deer/boar sizes up consistently with every procedural species
## around it rather than using its own disconnected fixed scale.
const BASE_WORLD_WIDTH := 24.0

## species -> sheet metadata. `walk_bands`/`eat_bands` are ARRAYS of Y ranges
## (Vector2i(y0, y1)) -- almost always one band (one row = one cycle), but a
## sheet can split a single longer cycle across multiple rows (see horse's
## walk below, two near-identical gallop rows meant to play as one 28-frame
## cycle), and per-animal configuration means that's an option some species
## take and others don't -- nothing assumes every walk cycle is the same
## length. SpriteSheetSlicer.detect_frames scans each band in turn and the
## results are concatenated in list order; bands are hand-measured per
## sheet, not auto-detected, since a wrong guess here would silently slice
## garbage rather than fail loudly.
## `alpha_threshold` overrides SpriteSheetSlicer's default 0.3: some sheets
## use a soft vignette/panel-border wash around each cell (moderately
## opaque without being real artwork) rather than a crisp divider line or
## true transparency, and need a higher bar to exclude it (see
## SpriteSheetSlicer.is_content_pixel's own doc comment).
## `reference_content_width` is frame 0's own measured content width (art
## pixels), the denominator marker_scale divides BASE_WORLD_WIDTH *
## world_scale by.
const _SHEETS := {
	"horse": {
		"path": "res://assets/sprites/horse_walk.png",
		# A single-row sheet: one 8-frame walking cycle (2172x724, content
		# band measured y 232-457), the 4th horse.png supplied this project
		# and the first that is walk-only -- no idle row, no eat row. Idle
		# synthesizes from the walk cycle's own frame 0 (see has_action's
		# fallback chain) rather than regressing a standing horse to
		# procedural art.
		# This sheet is drawn facing LEFT (head/muzzle on the left, tail on
		# the right) -- unlike deer.png and boar.png, which both face RIGHT,
		# and unlike ProceduralAnimalSprite, whose _HEAD_SIDE hardcodes
		# right. Declared per sheet because it is a property of the supplied
		# ASSET, not of the species: a replacement horse.png could face
		# either way. See CreatureMarker.facing_sign -- getting this wrong
		# renders the creature mirrored, so it walks backwards in EVERY
		# direction (reported repeatedly: "the horse is still walking
		# backwards... it should only ever walk into direction it's facing").
		"faces_left": true,
		"walk_bands": [Vector2i(232, 457)],
		# Idle is its OWN file at its OWN resolution (1536x1024, animal
		# ~1110px wide against the walk sheet's ~263px). Any action may
		# override `path` with "<action>_path"; scale is measured per action
		# (see marker_scale) so a differently-sized source file cannot
		# change the creature's apparent size when it switches action.
		"idle_path": "res://assets/sprites/horse_idle.png",
		"idle_bands": [Vector2i(74, 976)],
		"eat_path": "res://assets/sprites/horse_eat.png",
		"eat_bands": [Vector2i(214, 496)],
		"alpha_threshold": 0.3,
		# Kept from the previous sheets' convention: darker dashed divider
		# grays than the 0.7 default must not survive content-masking.
		# Harmless when the sheet (like this one) has no divider marks.
		"divider_gray_min": 0.45,
		# Frame 0's own measured content width -- the same "frame 0 is the
		# reference" convention deer/boar use.
		"reference_content_width": 263.0,
	},
	# Per-action files, same shape as horse/boar. Replaces the original
	# combined deer.png (whose soft vignette needed alpha_threshold 0.85);
	# these are clean cut-outs, so the ordinary thresholds apply.
	"deer": {
		"faces_left": true,
		"path": "res://assets/sprites/deer_walk.png",
		"walk_bands": [Vector2i(281, 532)],
		"idle_path": "res://assets/sprites/deer_idle.png",
		"idle_bands": [Vector2i(78, 859)],
		"eat_path": "res://assets/sprites/deer_eat.png",
		"eat_bands": [Vector2i(207, 502)],
		"alpha_threshold": 0.3,
		"divider_gray_min": 0.45,
	},
	# Three dedicated files, one per action, at two different resolutions
	# (walk/eat are 2172x724 sheets; idle is a single 1536x1024 portrait).
	# Scale is measured per action (see marker_scale), so the differing
	# source resolutions cannot change the boar's apparent size as it
	# switches between them.
	"boar": {
		# These sheets face LEFT (snout/tusks on the left), unlike the single
		# boar.png they replaced, which faced right. Getting this wrong
		# renders the creature mirrored so it walks backwards in EVERY
		# direction -- the exact bug the horse shipped with. Verified by
		# rendering the sliced frames and looking at them, not assumed.
		"faces_left": true,
		"path": "res://assets/sprites/boar_walk.png",
		"walk_bands": [Vector2i(285, 447)],
		"idle_path": "res://assets/sprites/boar_idle.png",
		"idle_bands": [Vector2i(218, 838)],
		"eat_path": "res://assets/sprites/boar_eat.png",
		"eat_bands": [Vector2i(266, 448)],
		"alpha_threshold": 0.3,
		"divider_gray_min": 0.45,
	},
	# assets/sprites/animals/wolf.png: an AI-generated 2-row x 8-column grid
	# (walk row, then eat row) on a solid chroma-keyed magenta ground with
	# near-white divider lines between cells -- see "magenta_keyed" below.
	# Bands measured directly from the real PNG (1536x1024): a divider row
	# reads as near-uniform white across the full width; everything between
	# two divider bands is one row's own content.
	"wolf": {
		"faces_left": true,
		"path": "res://assets/sprites/animals/wolf.png",
		"walk_bands": [Vector2i(4, 511)],
		"eat_bands": [Vector2i(512, 1020)],
		"alpha_threshold": 0.3,
		"magenta_keyed": true,
	},
	# assets/sprites/animals/sheep.png: same 2-row x 8-column magenta-keyed
	# grid shape as wolf.png, at its own resolution (1774x887) and own
	# measured bands.
	"sheep": {
		"faces_left": true,
		"path": "res://assets/sprites/animals/sheep.png",
		"walk_bands": [Vector2i(3, 443)],
		"eat_bands": [Vector2i(444, 884)],
		"alpha_threshold": 0.3,
		"magenta_keyed": true,
	},
}

## ## Chroma-keyed magenta, not a plain white/transparent ground
##
## wolf.png and sheep.png (see their own _SHEETS entries, "magenta_keyed":
## true) are supplied on a solid magenta backdrop within each cell, the
## exact same AI-image-generator convention IllustratedStoneSprite already
## solved for pebbles/boulders/cobbles (see that class's own doc comment for
## the full rationale) -- transparent background was ignored by the
## generator, so this project settled on magenta instead. Kept as this
## class's OWN copy of the identical constants/logic rather than a shared
## utility -- the same "kept as this class's own copy" choice
## IllustratedTerrainSprite already made for the same reason. deer/boar/
## horse are unaffected: their sheets have no "magenta_keyed" flag, so this
## whole pass is skipped for them (see _slice_bands), not merely a no-op.
const MAGENTA_RED_MIN := 0.85
const MAGENTA_BLUE_MIN := 0.85
const MAGENTA_GREEN_MAX := 0.15

## How much red/blue may exceed green before it counts as a magenta cast
## worth despilling -- see IllustratedStoneSprite.MAGENTA_CAST_MARGIN's own
## doc comment for the full "despill, not just a binary key" rationale (a
## pure-magenta key alone leaves a visible pink halo along antialiased
## edges, since the source has no real alpha of its own to fall back on).
const MAGENTA_CAST_MARGIN := 0.03


static func _is_magenta(color: Color) -> bool:
	return color.r >= MAGENTA_RED_MIN and color.b >= MAGENTA_BLUE_MIN and color.g <= MAGENTA_GREEN_MAX


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0),
		color.g,
		clampf(color.b - removed, 0.0, 1.0),
		color.a
	)


## Makes a magenta-keyed sheet's background genuinely transparent before it
## reaches SpriteSheetSlicer, which only understands alpha and near-white/
## grey as background -- it has no concept of magenta. Mirrors
## IllustratedStoneSprite._prepared_for_slicing exactly.
static func _prepared_for_slicing(image: Image) -> Image:
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


## Second, final cleanup pass over each already-cropped-and-resized frame --
## SpriteSheetSlicer's own crop+Lanczos resize can still ring a few output
## pixels back toward a magenta cast even once the source sheet has been
## despilled. Mirrors IllustratedStoneSprite._scrub_magenta_fringe exactly.
static func _scrub_magenta_fringe(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))

var _slicer := SpriteSheetSlicer.new()

## Shared across every instance (see the class doc comment: every creature of
## a species shows the identical illustrated frames, so there's nothing to
## gain and real cost -- a disk load + full-sheet scan -- in re-slicing per
## marker, or in rewrapping the same pixels in a new ImageTexture every call).
## "species/action" -> Array[ImageTexture].
static var _frame_cache: Dictionary = {}


func has_species(species: String) -> bool:
	return _SHEETS.has(species)


## Whether this species' source sheet is drawn facing LEFT rather than the
## right-facing convention everything else in the codebase assumes (see
## ProceduralAnimalSprite._HEAD_SIDE). Per-sheet configuration, not a
## per-species fact -- see the horse entry in _SHEETS. Callers must fold
## this into which way they mirror the sprite: CreatureMarker.facing_sign.
func faces_left(species: String) -> bool:
	if not _SHEETS.has(species):
		return false
	return _SHEETS[species].get("faces_left", false)


## Data-driven on whichever "<action>_bands" keys the species' sheet
## actually defines (see _SHEETS) -- a species can register any subset
## (horse currently has idle_bands + walk_bands but no eat_bands; deer/boar
## have walk_bands + eat_bands but no idle_bands). Three actions beyond that
## have a documented FALLBACK within the illustrated art itself rather than
## dropping straight to the procedural generator, so a covered species never
## visibly swaps art STYLE mid-action just because its own sheet has no
## dedicated row for it:
##   - "idle" falls back to the eat cycle's own first frame if there's no
##     dedicated idle_bands (a neutral standing pose either way), and to the
##     WALK cycle's frame 0 as a last resort for a walk-only sheet (horse's
##     current one) -- a single held gait frame still reads as the same
##     horse standing, where dropping to procedural art would visibly swap
##     the creature's whole art style every time it stops moving.
##   - "swim" falls back to the walk cycle -- moving legs/body reads far
##     closer to swimming than a static pose would, and FAR closer than
##     switching to procedural's completely different art (reported: "when
##     swimming the procedural generated horse shape is rendered instead of
##     the illustrated one").
##   - "drink" falls back to whatever "idle" itself resolves to -- a
##     creature drinking is standing still, same as idle.
## Only "eat" and "attack" have no such fallback: eating's own head-down
## grazing pose and attack's own lunge aren't well approximated by either
## walk or idle, so a species with no dedicated art for them still falls all
## the way through to ProceduralAnimalAnimation (see has_action's caller in
## CreatureMarker).
func has_action(species: String, action: String) -> bool:
	if not _SHEETS.has(species):
		return false
	var sheet: Dictionary = _SHEETS[species]
	if sheet.has(action + "_bands"):
		return true
	if action == "idle":
		return sheet.has("eat_bands") or sheet.has("walk_bands")
	if action == "swim" or action == "attack":
		return sheet.has("walk_bands")
	if action == "drink":
		return has_action(species, "idle")
	return false


## The registered frames for `species`/`action` as ready-to-assign textures,
## sliced+normalized once and cached thereafter (see _frame_cache). Returns
## an empty Array for anything has_action would reject -- callers must check
## has_action first and fall back to ProceduralAnimalAnimation themselves,
## the same "ask before you leap" shape as every other optional-capability
## check in this codebase.
func generate_textures(species: String, action: String) -> Array[ImageTexture]:
	if not has_action(species, action):
		return []
	var key := "%s/%s" % [species, action]
	if not _frame_cache.has(key):
		var textures: Array[ImageTexture] = []
		for frame in _load_frames(species, action):
			textures.append(ImageTexture.create_from_image(frame))
		_frame_cache[key] = textures
	return _frame_cache[key]


func _load_frames(species: String, action: String) -> Array[Image]:
	var sheet: Dictionary = _SHEETS[species]

	if sheet.has(action + "_bands"):
		return _slice_bands(sheet, sheet[action + "_bands"], sheet.get(action + "_path", ""))

	# No dedicated band for this action -- see has_action's own doc comment
	# for the exact fallback chain (only idle/swim/drink ever reach here;
	# everything else is rejected by has_action before generate_textures
	# ever calls in).
	if action == "swim" or action == "attack":
		return _slice_bands(sheet, sheet["walk_bands"])
	if action == "drink":
		return _load_frames(species, "idle")

	# "idle" with no dedicated idle_bands: the eat cycle's own frame 0 is a
	# head-up, alert standing pose, exactly a neutral "not doing anything in
	# particular" idle, with no dedicated art of its own needed (mirrors
	# ProceduralAnimalAnimation's "idle" precedent: a single static pose,
	# not a cycle). A walk-only sheet holds the walk cycle's frame 0 instead
	# -- see has_action's fallback-chain doc comment.
	var source_bands: Array = sheet["eat_bands"] if sheet.has("eat_bands") else sheet["walk_bands"]
	var frames := _slice_bands(sheet, source_bands)
	return [frames[0]] as Array[Image]


## Slices+normalizes every band in `bands` from `sheet`'s own source image,
## concatenating them in list order (see _SHEETS' own doc comment on why a
## single action can span multiple bands).
func _slice_bands(sheet: Dictionary, bands: Array, path: String = "") -> Array[Image]:
	var image := Image.load_from_file(path if path != "" else sheet["path"])
	# Magenta-keyed sheets (wolf, sheep -- see "magenta_keyed" in _SHEETS)
	# need their chroma-keyed background converted to real alpha=0 BEFORE it
	# reaches the slicer, or the whole sheet reads as one continuous content
	# blob. Skipped entirely for every other sheet, not merely a no-op.
	var magenta_keyed: bool = sheet.get("magenta_keyed", false)
	if magenta_keyed:
		image = _prepared_for_slicing(image)
	var alpha_threshold: float = sheet["alpha_threshold"]
	# Most sheets use a near-white divider line, comfortably above
	# SpriteSheetSlicer's own default bound -- only sheets that measure
	# darker (see horse's own comment above) need to override this.
	var divider_gray_min: float = sheet.get("divider_gray_min", 0.7)
	var normalized: Array[Image] = []
	for band in bands:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 60, 1, alpha_threshold, divider_gray_min)
		var sliced := _slicer.normalize_frames(
			image, frames, CANVAS_SIZE, BASELINE_Y, alpha_threshold, divider_gray_min
		)
		if magenta_keyed:
			# A second, final cleanup pass over each already-cropped-and-
			# resized frame -- see _scrub_magenta_fringe's own doc comment.
			for frame_image in sliced:
				_scrub_magenta_fringe(frame_image)
		normalized.append_array(sliced)
	return normalized


## Local-space Y offset (from the marker's own origin, i.e. canvas center) to
## where this species' feet actually meet the ground -- mirrors
## CreatureRenderer._shadow_foot_offset_y's procedural equivalent, but every
## illustrated species shares the one fixed canvas/baseline convention above
## instead of AnimalAnatomy's per-species canvas-fraction fields, so there's
## nothing to compute per species.
func ground_offset_y() -> float:
	return float(BASELINE_Y) - float(CANVAS_SIZE.y) * 0.5


## Local-space Y offset (from the marker's own origin) where the water
## surface should sit for a swimming creature of this species -- the DRAWN
## body's own vertical CENTRE, so "half submerged" falls straight out of the
## art itself rather than needing a hand-tuned fraction. Same reasoning as
## the player's own waterline (see CharacterView, which puts it at the
## torso sprite's own centre). Measured per species rather than shared,
## since the shared canvas is baseline-aligned (see BASELINE_Y): a tall
## horse and a low boar sit at very different heights on the same canvas,
## so one fixed offset would half-drown one and barely wet the other.
func waterline_offset_y(species: String) -> float:
	# Memoized: this scans a full frame's pixels, and CreatureMarker asks on
	# EVERY animation step while a creature swims -- rescanning per frame per
	# swimmer is measurable work for an answer that never changes.
	if _waterline_cache.has(species):
		return _waterline_cache[species]
	var offset := _measure_waterline_offset_y(species)
	_waterline_cache[species] = offset
	return offset


static var _waterline_cache: Dictionary = {}


func _measure_waterline_offset_y(species: String) -> float:
	var frames := generate_textures(species, "idle")
	if frames.is_empty():
		return 0.0
	var image: Image = frames[0].get_image()
	var top := -1
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				if top < 0:
					top = y
				bottom = y
				break
	if top < 0:
		return 0.0
	return (float(top) + float(bottom)) * 0.5 - float(CANVAS_SIZE.y) * 0.5


## How much to scale this species' marker so it reads at the right relative
## size next to every procedurally-drawn species around it -- see
## BASE_WORLD_WIDTH's own doc comment. Falls back to AnimalAnatomy's generic
## herbivore profile (world_scale 1.0) for an unregistered species rather
## than dividing by a missing reference_content_width.
## Scale is measured PER ACTION, not per species: an action may come from
## its own file at its own resolution (horse's idle art is a separate sprite
## whose animal is ~4x the pixel width of the walk sheet's), and a single
## per-species scale would visibly balloon the creature the instant it
## stopped moving. Each action's own frame-0 content width is measured from
## the art and normalized to the same world width, so every action of a
## species renders at the same apparent size by construction -- no
## hand-declared per-sheet reference width to keep in sync when art is
## swapped (this project's horse art has been replaced four times).
## Cached per species/action: CreatureMarker asks EVERY frame for EVERY
## creature (see _apply_action_scale), and the answer never changes for given
## art. Recomputing it cost ~9.6us per creature per frame -- roughly half of
## that inside AnimalAnatomy.profile_for, which returns `.duplicate()` and so
## allocated a fresh ~25-key Dictionary per creature per frame. Measured at
## 4.31 ms/frame for 40 creatures before this (a quarter of the 60fps budget,
## headless, with nothing rendering).
static var _marker_scale_cache: Dictionary = {}


func marker_scale(species: String, action: String = "walk") -> float:
	if not _SHEETS.has(species):
		return 1.0
	var key := "%s/%s" % [species, action]
	if _marker_scale_cache.has(key):
		return _marker_scale_cache[key]
	var world_scale: float = AnimalAnatomy.profile_for(species).world_scale
	var scale_value := BASE_WORLD_WIDTH * world_scale / _reference_width(species, action)
	_marker_scale_cache[key] = scale_value
	return scale_value


static var _reference_width_cache: Dictionary = {}


## Frame 0's own opaque-pixel width for this species/action, measured once
## and cached (it never changes for given art).
func _reference_width(species: String, action: String) -> float:
	var key := "%s/%s" % [species, action]
	if _reference_width_cache.has(key):
		return _reference_width_cache[key]
	var frames := generate_textures(species, action)
	if frames.is_empty():
		return BASE_WORLD_WIDTH
	var image: Image = frames[0].get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var width := maxf(float(max_x - min_x + 1), 1.0)
	_reference_width_cache[key] = width
	return width
