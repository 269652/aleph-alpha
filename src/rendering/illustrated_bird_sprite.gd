extends RefCounted

## Real hand-illustrated bird sprite-sheet animation (assets/sprites/birds/
## sparrow.png, robin.png, blackbird.png, kingfisher.png), replacing
## ProceduralBirdSprite's primitive-shape generation for species with real
## art -- the bird analog of IllustratedAnimalSprite (horse/deer/boar/sheep/
## wolf), a separate sibling class rather than an extension of it: birds run
## through a completely different marker/animation system
## (AmbientFlyerMarker/PiscivoreBirdMarker, not CreatureMarker), so there is
## nothing to share beyond SpriteSheetSlicer itself, which is already
## generic.
##
## Each sheet is an 8-column x 7-row grid (kingfisher: 8 rows -- see below)
## on a solid magenta chroma-key ground, same technique as
## IllustratedAnimalSprite's sheep/wolf/world-boss sheets. Bands are
## HAND-MEASURED per sheet and stored as data (see _SHEETS), never
## auto-detected at runtime -- the same house rule those sheets already
## follow, "since a wrong guess here would silently slice garbage rather
## than fail loudly". Measured with a throwaway tool applying the same
## chroma-key + SpriteSheetSlicer.is_empty content test row-by-row to find
## real Y-bands, rather than assuming an even height/7 split (which does
## NOT hold here -- rows are unevenly spaced, same lesson
## IllustratedAnimalSprite's own sheets already teach).
##
## PHASE 1 SCOPE ONLY (see the bird-behavior-overhaul plan): idle, perched,
## flap (takeoff+glide), pecking. The sheets also carry a ground walk/hop
## row, a kingfisher dive row, a display/mating-dance row and a
## singing/tweeting row -- real bands for those are deliberately NOT wired
## here yet; they land with the phases that give them a real behavioral
## trigger (walk/dive in the animation-states phase, court/sing in the
## courtship phase). Wiring unused bands now would just be dead data with
## nothing to point at it.
##
## ONE POSE PER "PERCHED": the sheets draw exactly one standing-still row
## (row 1) -- there is no separate folded-wing rest pose the way
## ProceduralBirdSprite draws one on top of its flap cycle. perched and idle
## are therefore the SAME frame here (see generate_perched_texture);
## AmbientFlyerMarker's perched/idle split still works because it is a
## marker-side STATE (flying vs not), not a claim that the two need
## different art.
##
## FLAP IS ONE 16-FRAME CYCLE, NOT TWO SEPARATE ACTIONS: row 2 (wings
## raised, a takeoff burst) and row 3 (wings level, a glide) concatenate
## into a single array, the same "a single action can span multiple bands"
## shape IllustratedAnimalSprite's own horse-gallop entry already
## establishes. This is what makes it a drop-in replacement for
## ProceduralBirdSprite.generate_flap_textures with no change needed to
## AmbientFlyerMarker/FlapGlide, which already expect one array covering a
## full beat-then-glide cycle.
##
## KINGFISHER HAS AN EXTRA ROW (8, not 7): measured, not assumed -- see the
## row 5 comment in _SHEETS. Not used by Phase 1 either way (kingfisher's
## Phase 1 wiring is idle/flap only, via PiscivoreBirdMarker, which has no
## ground-peck state at all).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Sized for these small birds specifically (IllustratedAnimalSprite's
## 340x330 is tuned for a deer-sized quadruped) -- generous enough that
## SpriteSheetSlicer.normalize_frames' scale-to-fit never has to shrink a
## frame to an unreadable size, tight enough that a bird still reads at a
## reasonable fraction of the canvas rather than swimming in padding.
const CANVAS_SIZE := Vector2i(220, 210)
const BASELINE_Y := 195

const CHROMA_KEY := Color(0.95, 0.02, 0.96)
const CHROMA_KEY_TOLERANCE := 0.25
const ALPHA_THRESHOLD := 0.3
const DIVIDER_GRAY_MIN := 0.7

## species -> {"idle": Vector2i(y0, y1), "flap": [Vector2i, Vector2i], "peck": Vector2i}.
## Every sheet is assets/sprites/birds/<species>.png, 1536x1024. Bands were
## re-measured against real full-width horizontal divider lines (a thin
## non-white, non-magenta rule the row-density scan alone missed at first --
## it reads as "content" under the ordinary is_empty test, not as a
## divider), then confirmed by eye against the actual sliced pixels, not
## assumed from a template row list.
##
## `flap` is an ARRAY of two bands (takeoff, then glide), concatenated in
## that order -- see the class doc comment.
##
## THE FOUR SHEETS ARE NOT ROW-FOR-ROW IDENTICAL, confirmed by looking at
## the actual pixels, not assumed: sparrow's sheet genuinely has a dedicated
## head-down, seed-crumb pecking row. Robin's and blackbird's sheets do NOT
## -- the row at the position a shared template would put "peck" is
## actually the tail-fanned DISPLAY pose instead (confirmed by eye: no
## dip, no crumbs, wings/tail spread), and no other row on either sheet
## shows a peck pose -- real divider lines bound every row on both sheets
## with no gap left over for one. `peck` is simply absent from their
## entries; generate_pecking_texture falls back to idle for any species
## without one, the same "never hand a caller nothing" shape
## IllustratedAnimalSprite's own fallback chain already uses. Kingfisher
## has no peck entry either, for an unrelated reason: it doesn't eat seeds
## at all (see PiscivoreBirdBehavior) -- its own row 5 is a calm,
## beak-closed standing pose, closer to PiscivoreAppetite.ACTIVITY_PERCH
## than to a strike, and is not wired to anything in Phase 1.
const _SHEETS := {
	"sparrow": {
		"path": "res://assets/sprites/birds/sparrow.png",
		"idle": Vector2i(27, 141),
		"flap": [Vector2i(165, 317), Vector2i(356, 463)],
		"peck": Vector2i(633, 730),
	},
	"robin": {
		"path": "res://assets/sprites/birds/robin.png",
		"idle": Vector2i(40, 173),
		"flap": [Vector2i(197, 351), Vector2i(397, 522)],
	},
	"blackbird": {
		"path": "res://assets/sprites/birds/blackbird.png",
		"idle": Vector2i(24, 145),
		"flap": [Vector2i(166, 320), Vector2i(375, 474)],
	},
	# Kingfisher's 8 real content rows (measured): idle, takeoff, glide,
	# DIVE (Phase 3), an extra calm perched/resting pose, a second perched
	# variant, display (Phase 4), sing (Phase 3/4). Only idle/flap are used
	# in Phase 1.
	"kingfisher": {
		"path": "res://assets/sprites/birds/kingfisher.png",
		"idle": Vector2i(23, 126),
		"flap": [Vector2i(147, 266), Vector2i(303, 380)],
	},
}

## The on-screen world width (px) a sparrow -- the FLYER_WORLD_SCALE
## reference species, ratio 1.0 -- read as under ProceduralBirdSprite,
## before this class existed: measured content width (24px of its 32px
## canvas) times the renderers' shared marker.scale chain (ArtResolution.
## SPRITE_SCALE * FishRenderer.FISH_WORLD_SCALE * FLYER_WORLD_SCALE). Kept
## as this class's own calibration anchor -- see marker_scale -- rather
## than switching the game's whole existing bird-to-world size balance
## just because the ART got better.
const BASE_WORLD_WIDTH := 6.6

## Per-species target world width (px), TARGET = BASE_WORLD_WIDTH *
## AmbientFlyerRenderer.FLYER_WORLD_SCALE[species] -- duplicated as literal
## numbers rather than preloading that file to read it live: AmbientFlyer
## Renderer already preloads THIS class (to pick it over ProceduralBird
## Sprite), and a preload back the other way is circular. Kept from
## silently drifting apart by test_flyer_world_scale_proportions_match_
## illustrated_bird_sprite in test_ambient_flyer_renderer.gd, which
## imports both and checks the ratios agree -- not exact pixel parity
## with FLYER_WORLD_SCALE (real illustrated art has its own proportions a
## hand-authored multiplier cannot predict exactly), just the same
## ordering. Blackbird has no ProceduralBirdSprite sibling to calibrate
## against (see the class doc comment's fallback note) -- sized like
## kingfisher's, a real blackbird being one of the larger common garden
## birds (~24cm) alongside a kingfisher (~17cm bill included), both well
## above a robin/sparrow (~14-15cm).
const _TARGET_WORLD_WIDTH := {
	"sparrow": BASE_WORLD_WIDTH,       # FLYER_WORLD_SCALE 1.0
	"robin": BASE_WORLD_WIDTH * 1.5,   # FLYER_WORLD_SCALE 1.5
	"kingfisher": BASE_WORLD_WIDTH * 1.7,  # FLYER_WORLD_SCALE 1.7
	"blackbird": BASE_WORLD_WIDTH * 1.7,
}

static var _content_width_cache: Dictionary = {}


## How much to scale this species' marker so it reads at its real target
## world width (see _TARGET_WORLD_WIDTH) instead of the flat, procedural-
## canvas-tuned scale AmbientFlyerRenderer/PiscivoreBirdRenderer otherwise
## apply -- the bird analog of IllustratedAnimalSprite.marker_scale, and
## the actual fix for "robins and sparrows are now gigantic": the flat
## scale drew this class's ~6-9x-wider real content at ProceduralBird
## Sprite's own tiny-canvas size, unshrunk. Callers must use THIS instead
## of the flat chain whenever this generator (not ProceduralBirdSprite) is
## the one actually in use -- see AmbientFlyerRenderer._build_marker /
## PiscivoreBirdRenderer.spawn_piscivore_birds, which now branch on which
## generator has_species(species) selected, mirroring exactly how
## CreatureMarker._apply_action_scale branches between
## IllustratedAnimalSprite.marker_scale and the procedural per-species
## scale.
func marker_scale(species: String) -> float:
	var target: float = _TARGET_WORLD_WIDTH.get(species, BASE_WORLD_WIDTH)
	return target / _content_width(species)


## Frame 0's own opaque-pixel content width (art px), measured once and
## cached -- mirrors IllustratedAnimalSprite._reference_width exactly,
## down to the reason: this scans a full frame's pixels, and every spawn
## call asks for it.
func _content_width(species: String) -> float:
	if _content_width_cache.has(species):
		return _content_width_cache[species]
	var texture := generate_texture(species)
	if texture == null:
		return BASE_WORLD_WIDTH
	var image: Image = texture.get_image()
	var min_x := image.get_width()
	var max_x := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var width := maxf(float(max_x - min_x + 1), 1.0)
	_content_width_cache[species] = width
	return width


## "species/action" -> Array[ImageTexture]. Shared across every instance,
## same reasoning as IllustratedAnimalSprite._frame_cache: every bird of a
## species shows the identical illustrated frames, so there is nothing to
## gain and real cost (a disk load + full-sheet scan) in re-slicing per
## marker.
static var _frame_cache: Dictionary = {}
static var _image_cache: Dictionary = {}

var _slicer := SpriteSheetSlicer.new()


func has_species(species: String) -> bool:
	return _SHEETS.has(species)


## generate_texture/generate_perched_texture/generate_flap_textures/
## generate_pecking_texture below all share this method surface with
## ProceduralBirdSprite by design -- see AmbientFlyerRenderer._build_marker,
## which duck-types its `sprite_generator` argument rather than branching on
## a type. `seed_value` is accepted and ignored (no per-seed art variation,
## same explicitly-scoped limitation IllustratedAnimalSprite already has),
## kept only so this class is interchangeable with the procedural one
## without touching every call site's argument list.

func generate_texture(species: String, _seed_value: int = 0) -> ImageTexture:
	return _frames_for(species, "idle")[0] if has_species(species) else null


func generate_perched_texture(species: String, _seed_value: int = 0) -> ImageTexture:
	# Same pose as idle -- see the class doc comment.
	return generate_texture(species, _seed_value)


func generate_flap_textures(species: String, _seed_value: int = 0) -> Array:
	return _frames_for(species, "flap")


func generate_pecking_texture(species: String, _seed_value: int = 0) -> ImageTexture:
	var frames := _frames_for(species, "peck")
	if not frames.is_empty():
		return frames[0]
	# No dedicated peck art for this species (see the class doc comment) --
	# idle over nothing, the same fallback shape IllustratedAnimalSprite's
	# has_action chain already uses for a species missing a given row.
	return generate_texture(species, _seed_value)


func _frames_for(species: String, action: String) -> Array:
	if not _SHEETS.has(species):
		return []
	var sheet: Dictionary = _SHEETS[species]
	if not sheet.has(action):
		return []
	var key := "%s/%s" % [species, action]
	if not _frame_cache.has(key):
		var bands: Array = sheet[action] if sheet[action] is Array else [sheet[action]]
		_frame_cache[key] = _build_textures(sheet["path"], bands)
	return _frame_cache[key]


func _build_textures(path: String, bands: Array) -> Array:
	var image := _keyed_image(path)
	var normalized: Array[Image] = []
	for band in bands:
		var rect: Vector2i = band
		var frames := _slicer.detect_frames(
			image, rect.x, rect.y, 20, 1, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN
		)
		normalized.append_array(
			_slicer.normalize_frames(
				image, frames, CANVAS_SIZE, BASELINE_Y, ALPHA_THRESHOLD, DIVIDER_GRAY_MIN
			)
		)
	var textures: Array[ImageTexture] = []
	for frame in normalized:
		textures.append(ImageTexture.create_from_image(frame))
	return textures


## The source sheet with its magenta ground made fully transparent, cached
## per path (the same multi-megapixel chroma-key pass every action's bands
## would otherwise each re-run against the same file).
func _keyed_image(path: String) -> Image:
	if _image_cache.has(path):
		return _image_cache[path]
	var raw := SpriteSheetLoader.load_image(path)
	var keyed: Image = raw.duplicate()
	if keyed.get_format() != Image.FORMAT_RGBA8:
		keyed.convert(Image.FORMAT_RGBA8)
	for y in keyed.get_height():
		for x in keyed.get_width():
			var c: Color = keyed.get_pixel(x, y)
			if (
				absf(c.r - CHROMA_KEY.r) <= CHROMA_KEY_TOLERANCE
				and absf(c.g - CHROMA_KEY.g) <= CHROMA_KEY_TOLERANCE
				and absf(c.b - CHROMA_KEY.b) <= CHROMA_KEY_TOLERANCE
			):
				keyed.set_pixel(x, y, Color(0, 0, 0, 0))
	_image_cache[path] = keyed
	return keyed
