extends RefCounted

## Real illustrated art for the bee forager's two real species (see
## docs/concept/bees.md) -- reported live: "bees are drawn gigantic... I
## added honeybee sprite please wire it and scale bee appropriately".
## BeeForagerMarker previously drew EITHER species via
## ProceduralButterflySprite's own "bee" silhouette with no scale applied
## to the sprite at all -- this codebase's own recurring "gigantic X"
## failure mode (see ProceduralDecomposerSprite's own doc comment for the
## precedent this has already hit for ants). Fixed by real, delivered art
## plus a real, measured world_scale, exactly like every other small
## creature in this codebase.
##
## Same "hand-drawn sheet -> known fixed grid -> cached frames" shape as
## IllustratedMillipedeSprite/IllustratedWormSprite/
## IllustratedCaterpillarSprite -- honeybee.png (BeeColony hive workers)
## and bee.png (WildBeePatch solitary foragers) are both dimension-
## identical to those sheets (1536x1024, 192x256 per cell, confirmed
## directly against the PNG header), keyed by species (like
## IllustratedDecomposerSprite's "ant"/"bug") rather than one fixed sheet,
## since there are genuinely two different bees here, not one.
##
## Only row 1 ("fly" -- a level, wings-spread flapping cycle) is wired
## this pass. Both sheets have 3 more rows of real, delivered content
## (alternate flight/banking angles, and a landed/lower-wing pose in row
## 4) with no trigger wired to them yet -- BeeForagerMarker has no landed/
## feeding PHASE at all today (arrival resolves in one instant tick, see
## that class's own _resolve_arrival_at_food), so there is no real moment
## to play a landed pose FOR yet. Available, not yet wired -- named
## explicitly, the same "not silently assumed" gap this doc's own
## caterpillar `rest`/millipede `curl` rows were before being closed
## later.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH_BY_SPECIES := {
	"honeybee": "res://assets/sprites/animals/honeybee.png",
	"wild_bee": "res://assets/sprites/animals/bee.png",
}
const _COLUMNS := 8
const _CELL_SIZE := Vector2i(192, 256)
const _FLY_ROW := 0

## The canvas every sliced frame is normalized onto, its feet (well --
## flight line) landing on the same BASELINE_Y regardless of species --
## mirrors IllustratedMillipedeSprite's own shared-canvas convention
## exactly (same source cell aspect ratio, so the same canvas/baseline
## numbers apply unchanged).
const CANVAS_SIZE := Vector2i(200, 260)
const BASELINE_Y := 250

## Chroma-keyed opaque magenta -- confirmed directly by sampling every 7th
## pixel across both sheets (not a corner sample -- see this codebase's
## own documented "reads misleadingly near-white on an antialiased edge"
## trap), same measured values as every other illustrated animal sheet
## here.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03

## Real-world size: a honeybee/wild bee is a genuinely small flying
## insect -- a real adult honeybee is roughly 12-15mm, noticeably shorter
## than the earthworm/caterpillar/millipede figure this codebase already
## settled on (WORLD_LENGTH_TILES 0.32 for a ~100mm creature), so this is
## pinned smaller rather than reused flat. Pinned by
## test_world_scale_reads_as_a_small_flying_insect, not eyeballed.
const WORLD_LENGTH_TILES := 0.18
const TILE_SIZE := 16.0

## How long the fly cycle holds each frame -- fast, tiny wingbeats read
## wrong at a slow cadence; mirrors DecomposerMarker.WALK_FRAME_DURATION_
## SECONDS's own "small, fast" reasoning for an insect rather than
## CaterpillarMarker/MillipedeMarker's slower crawl cadence.
const FRAME_DURATION_SECONDS := 0.08

var _slicer := SpriteSheetSlicer.new()

## Keyed by species, shared across instances -- every bee of the same
## species drawing the fly cycle reuses the identical sliced frames
## (mirrors IllustratedMillipedeSprite._frame_cache).
static var _frame_cache: Dictionary = {}
static var _keyed_image_cache: Dictionary = {}
static var _reference_width_cache: Dictionary = {}


func has_species(species: String) -> bool:
	return _SHEET_PATH_BY_SPECIES.has(species)


## The registered fly-cycle frames for `species`, sliced+normalized once
## and cached thereafter. Empty for anything has_species would reject.
func generate_textures(species: String) -> Array[ImageTexture]:
	if not has_species(species):
		return []
	if not _frame_cache.has(species):
		_frame_cache[species] = _build_textures(species)
	return _frame_cache[species]


func _build_textures(species: String) -> Array[ImageTexture]:
	var image := _keyed_image(species)
	var frames: Array[Rect2i] = []
	for col in _COLUMNS:
		frames.append(Rect2i(col * _CELL_SIZE.x, _FLY_ROW * _CELL_SIZE.y, _CELL_SIZE.x, _CELL_SIZE.y))
	var textures: Array[ImageTexture] = []
	for frame_image in _slicer.normalize_frames(image, frames, CANVAS_SIZE, BASELINE_Y):
		# A second, final cleanup pass over each already-cropped-and-resized
		# SMALL frame -- SpriteSheetSlicer's own crop+resize can still ring a
		# few output pixels back toward a magenta cast even once the SOURCE
		# sheet has been despilled above (same reasoning as
		# IllustratedMillipedeSprite._build_textures).
		_despill_image(frame_image)
		textures.append(ImageTexture.create_from_image(frame_image))
	return textures


func _keyed_image(species: String) -> Image:
	if not _keyed_image_cache.has(species):
		_keyed_image_cache[species] = _prepared_for_slicing(
			SpriteSheetLoader.load_image(_SHEET_PATH_BY_SPECIES[species])
		)
	return _keyed_image_cache[species]


## Makes the sheet's magenta background genuinely transparent, and
## despills the magenta cast baked into every antialiased edge around it,
## before the image ever reaches SpriteSheetSlicer -- mirrors
## IllustratedMillipedeSprite._prepared_for_slicing exactly.
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


## `color` with any magenta-direction cast removed -- identical technique
## to IllustratedMillipedeSprite._despilled. A pixel with no cast (a
## genuine dark tone) passes through completely unchanged.
static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)


## How much to scale a CANVAS_SIZE-normalized frame so it reads at
## WORLD_LENGTH_TILES on screen -- measured off the fly cycle's own first
## frame, the same "steady/level pose represents the creature's own
## resting length" reasoning IllustratedMillipedeSprite.world_scale
## already uses.
func world_scale(species: String) -> float:
	return (WORLD_LENGTH_TILES * TILE_SIZE) / _reference_width(species)


func _reference_width(species: String) -> float:
	if _reference_width_cache.has(species):
		return _reference_width_cache[species]
	var frame: Image = generate_textures(species)[0].get_image()
	var min_x := frame.get_width()
	var max_x := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var width: float = float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
	_reference_width_cache[species] = width
	return width
