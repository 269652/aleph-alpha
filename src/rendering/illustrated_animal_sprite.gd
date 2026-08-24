extends RefCounted

## Real hand/AI-illustrated sprite-sheet animation for species with actual
## art (assets/sprites/*.png -- currently horse, deer, boar, sheep; see
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
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
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
	# A single sheet, 8-column x 2-row grid (walk row, then an eat/graze
	# row), cut out on a solid MAGENTA ground rather than real transparency
	# or a pale divider -- see "chroma_key"/_apply_chroma_key. The gridlines
	# between cells are an ordinary near-white divider, same as every other
	# sheet, so no divider_gray_min override is needed; only the background
	# itself needed new handling.
	"sheep": {
		"path": "res://assets/sprites/animals/sheep.png",
		"walk_bands": [Vector2i(3, 442)],
		"eat_bands": [Vector2i(445, 883)],
		"alpha_threshold": 0.3,
		# Measured background samples clustered around (0.95, 0.02, 0.96);
		# a generous per-channel tolerance also swallows the anti-aliased
		# blend right at the wool's silhouette edge without reaching into
		# the cream wool itself (high on every channel, not just R/B).
		"chroma_key": Color(0.95, 0.02, 0.96),
		"chroma_key_tolerance": 0.25,
	},
}

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
##
## Every FALLBACK action (swim/attack -> walk, drink -> idle, idle-without-
## its-own-art -> eat/walk's frame 0 -- see has_action's fallback-chain doc
## comment) is resolved by calling back into THIS function for the target
## action, not by re-slicing the source sheet -- a fallback action's result
## is always identical to its target's, so it reuses that target's own
## cache entry (and warms it, for whichever of the two is requested first)
## instead of paying a full re-slice (a multi-million-pixel scan per call --
## see _slice_bands/SpriteSheetSlicer) again for the exact same pixels. This
## used to redundantly re-slice once per distinct fallback action ever
## requested for a species -- with 3 fallback actions per species and
## several illustrated species, that's a real multi-second stall the first
## time a populated world's creatures start needing them, easy to mistake
## for the game having hung entirely.
func generate_textures(species: String, action: String) -> Array[ImageTexture]:
	if not has_action(species, action):
		return []
	var key := "%s/%s" % [species, action]
	if not _frame_cache.has(key):
		_frame_cache[key] = _build_textures(species, action)
	return _frame_cache[key]


func _build_textures(species: String, action: String) -> Array[ImageTexture]:
	var sheet: Dictionary = _SHEETS[species]

	if sheet.has(action + "_bands"):
		var textures: Array[ImageTexture] = []
		for frame in _slice_bands(sheet, sheet[action + "_bands"], sheet.get(action + "_path", "")):
			textures.append(ImageTexture.create_from_image(frame))
		return textures

	# No dedicated band for this action -- see has_action's own doc comment
	# for the exact fallback chain (only idle/swim/drink ever reach here;
	# everything else is rejected by has_action before generate_textures
	# ever calls in). Each branch calls generate_textures (cached), never
	# _slice_bands (a fresh re-slice) -- see this function's own doc comment.
	if action == "swim" or action == "attack":
		return generate_textures(species, "walk")
	if action == "drink":
		return generate_textures(species, "idle")

	# "idle" with no dedicated idle_bands: the eat cycle's own frame 0 is a
	# head-up, alert standing pose, exactly a neutral "not doing anything in
	# particular" idle, with no dedicated art of its own needed (mirrors
	# ProceduralAnimalAnimation's "idle" precedent: a single static pose,
	# not a cycle). A walk-only sheet holds the walk cycle's frame 0 instead
	# -- see has_action's fallback-chain doc comment.
	var source_action := "eat" if sheet.has("eat_bands") else "walk"
	var source_frames := generate_textures(species, source_action)
	return [source_frames[0]] as Array[ImageTexture]


## Slices+normalizes every band in `bands` from `sheet`'s own source image,
## concatenating them in list order (see _SHEETS' own doc comment on why a
## single action can span multiple bands).
func _slice_bands(sheet: Dictionary, bands: Array, path: String = "") -> Array[Image]:
	var image := SpriteSheetLoader.load_image(path if path != "" else sheet["path"])
	# Sheets cut out on a solid chroma-key colour (e.g. magenta) rather than
	# real transparency or a pale divider: everything below (detect_frames/
	# normalize_frames, via SpriteSheetSlicer.is_empty) already treats
	# LOW-ALPHA pixels as background, so turning the chroma-keyed pixels
	# transparent up front lets the exact same downstream logic handle them
	# with no separate "or matches this color" branch needed anywhere else.
	if sheet.has("chroma_key"):
		image = _apply_chroma_key(
			image, sheet["chroma_key"], sheet.get("chroma_key_tolerance", 0.1)
		)
	var alpha_threshold: float = sheet["alpha_threshold"]
	# Most sheets use a near-white divider line, comfortably above
	# SpriteSheetSlicer's own default bound -- only sheets that measure
	# darker (see horse's own comment above) need to override this.
	var divider_gray_min: float = sheet.get("divider_gray_min", 0.7)
	var normalized: Array[Image] = []
	for band in bands:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(image, rect.x, rect.y, 60, 1, alpha_threshold, divider_gray_min)
		normalized.append_array(
			_slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y, alpha_threshold, divider_gray_min)
		)
	return normalized


## A copy of `image` with every pixel within `tolerance` of `key` (each of
## R/G/B independently, ignoring alpha) turned fully transparent -- per-
## channel rather than a single combined distance so a saturated key color
## (e.g. magenta) can use a generous tolerance for anti-aliased edge blending
## without also swallowing a pale, low-saturation drawing color that happens
## to sit at a similar overall brightness.
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
