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
## creature in this codebase. A third species, honeybee_queen.png (the
## queen's own real, minimal place in the ecosystem -- see BeeColony.
## has_queen_at, BeeQueenMarker), was added and wired in a later pass.
##
## Same "hand-drawn sheet -> known fixed grid -> cached frames" shape as
## IllustratedMillipedeSprite/IllustratedWormSprite/
## IllustratedCaterpillarSprite, EXCEPT the grid: honeybee.png/bee.png/
## honeybee_queen.png are all 1536x1024 like those sheets, but are NOT
## those sheets' 4 EQUAL 256px rows -- see _ROW_BAND's own doc comment.
## Keyed by species (like IllustratedDecomposerSprite's "ant"/"bug")
## rather than one fixed sheet, since there are genuinely three different
## bees here (two foragers plus a non-foraging queen), not one.
##
## Real row semantics, corrected -- live user correction: "Rows are:
## walking, flying, foraging, building hive / nest, dying". The row
## originally shipped as "fly" (row 0, assumed by dividing the sheet into
## 4 equal 256px bands the same way worm/caterpillar/millipede's own
## sheets really do divide) is actually WALKING -- these three bee sheets
## were never independently probed for their own real grid the way THOSE
## sheets each got their own tools/probe_*_sheet.gd; the 4-equal-rows
## guess happened to land exactly on this sheet's real walk/fly boundary
## by coincidence. See _ROW_BAND below for the real, measured layout
## (tools/probe_bee_row_semantics.gd + tools/probe_bee_5rows.gd hold the
## full evidence trail: a per-row pixel-density profile plus stitched,
## despilled visual crops of every band, cross-checked against BOTH
## worker sheets agreeing pixel-for-pixel). Every bee on screen had been
## animating through its WALK cycle for its entire always-airborne
## on-screen lifecycle (BeeForagerMarker has no landed phase at all --
## see that class's own doc comment) until this fix.
const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const _SHEET_PATH_BY_SPECIES := {
	"honeybee": "res://assets/sprites/animals/honeybee.png",
	"wild_bee": "res://assets/sprites/animals/bee.png",
	"honeybee_queen": "res://assets/sprites/animals/honeybee_queen.png",
}
const _COLUMNS := 8
const _CELL_WIDTH := 192

## Real, hand-measured, NON-uniform row bands (top-y, height), shared
## identically across all three sheets (confirmed directly, not assumed
## from matching file dimensions alone -- see this file's own header
## comment). Packed edge to edge with NO blank divider row anywhere in
## the whole 1024px height (confirmed: a blank-row scan found exactly one
## band spanning all 1024 rows on every sheet) -- boundaries were only
## resolved by finding where a pose that needs the full 256px stops and a
## pose that fits a compact 128px starts:
##   walk      y[0,   256) -- ground contact: legs planted, a real drop
##             shadow beneath every frame.
##   fly       y[256, 384) -- level flight: legs tucked, no ground
##             shadow, minimal frame-to-frame variation (a steady cruise,
##             not a dynamic maneuver) -- the one band this file wires.
##   forage_a  y[384, 640) -- a taller, more dynamic reaching pose with a
##             visible orange/red mark at the mouthparts on several
##             frames (active nectar/pollen engagement).
##   forage_b  y[640, 768) -- a compact variant of forage_a, same mark.
##   dying     y[768, 1024)-- a progressive collapse across its 8 frames:
##             upright, then leaning, then legs curling inward, ending
##             lying on its side -- confirmed on all three sheets,
##             including the queen's own (her crown stays visible through
##             her own collapse).
## "Building hive/nest" (one of the five real concepts named live) has NO
## matching row on any of these three sheets at all -- a hive's own
## construction/growth is already fully represented by the separate
## beehive.png sheet (IllustratedBeehiveSprite.growth_stage_index), and
## neither BeeForagerMarker nor BeeColony/WildBeePatch has any "under
## construction" phase a bee's own body pose would need to play for. Not
## a forced match -- a real, honest "doesn't need one" finding.
const _ROW_BAND := {
	"walk": Vector2i(0, 256),
	"fly": Vector2i(256, 128),
	"forage_a": Vector2i(384, 256),
	"forage_b": Vector2i(640, 128),
	"dying": Vector2i(768, 256),
}

## The only band actually wired to an animated cycle this pass.
## BeeForagerMarker is airborne its ENTIRE lifecycle (SCOUTING ->
## APPROACHING -> RETURNING, see that class's own doc comment on why it
## deliberately has no landed phase) -- "fly" is the one real match, not
## "forage_a"/"forage_b": those carry a visible feeding mark that would
## read as wrong during SCOUTING/RETURNING, when nothing has been (or is
## still being) fed on. "walk"/"forage_a"/"forage_b"/"dying" remain real,
## delivered, and correctly left unwired for the same reason as before
## this fix -- BeeForagerMarker has no landed/feeding/death phase to
## trigger them from yet, named explicitly rather than silently dropped.
const _FLY_BAND := "fly"

## The queen's own real static pose -- see generate_queen_texture's own
## doc comment for why she uses "walk", never "fly".
const _QUEEN_SPECIES := "honeybee_queen"
const _QUEEN_BAND := "walk"

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
static var _queen_texture_cache: ImageTexture = null
static var _queen_reference_width_cache: float = -1.0


func has_species(species: String) -> bool:
	return _SHEET_PATH_BY_SPECIES.has(species)


## The registered fly-cycle frames for `species`, sliced+normalized once
## and cached thereafter. Empty for anything has_species would reject.
func generate_textures(species: String) -> Array[ImageTexture]:
	if not has_species(species):
		return []
	if not _frame_cache.has(species):
		_frame_cache[species] = _build_frames(species, _FLY_BAND)
	return _frame_cache[species]


## The queen's one real static pose -- see docs/concept/bees.md's real
## queen biology: unlike a worker, she never forages and never leaves the
## hive, so she has no animated CYCLE to play at all. Frame 0 of the real
## "walk" band (a calm, legs-planted stance -- every sheet's walk cycle
## already opens on essentially the same resting pose), not "fly": she
## does not fly either. Reuses the exact same sheet/despill/normalize
## pipeline generate_textures does -- only the species and source band
## differ. Null if the sheet is ever missing entirely (the same
## defensive "narrows, doesn't break" contract every optional-art seam in
## this codebase already has).
func generate_queen_texture() -> ImageTexture:
	if _queen_texture_cache == null:
		var frames := _build_frames(_QUEEN_SPECIES, _QUEEN_BAND)
		_queen_texture_cache = frames[0] if not frames.is_empty() else null
	return _queen_texture_cache


func _build_frames(species: String, band_name: String) -> Array[ImageTexture]:
	var image := _keyed_image(species)
	var band: Vector2i = _ROW_BAND[band_name]
	var frames: Array[Rect2i] = []
	for col in _COLUMNS:
		frames.append(Rect2i(col * _CELL_WIDTH, band.x, _CELL_WIDTH, band.y))
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
	var width := _measure_reference_width(generate_textures(species)[0])
	_reference_width_cache[species] = width
	return width


## Real-world size: a queen honeybee is genuinely larger than a worker,
## with a notably longer, egg-filled abdomen -- a real queen commonly
## runs around 18-22mm body length against a worker's ~12-15mm
## (WORLD_LENGTH_TILES above), roughly 1.5x -- confirmed directly against
## the delivered art too (see docs/concept/bees.md's own real render
## verification of this pass): she reads visibly bigger with a longer
## abdomen on the actual sheet, not just larger by citation alone. Same
## mm-per-tile ratio WORLD_LENGTH_TILES already established (0.18 tiles
## for ~13.5mm), scaled to ~20mm.
const WORLD_LENGTH_TILES_QUEEN := 0.27


## How much to scale generate_queen_texture()'s own frame so it reads at
## WORLD_LENGTH_TILES_QUEEN -- mirrors world_scale exactly, against the
## queen's own static "walk" frame rather than a forager's fly cycle.
func queen_world_scale() -> float:
	if _queen_reference_width_cache < 0.0:
		var texture := generate_queen_texture()
		_queen_reference_width_cache = (
			_measure_reference_width(texture) if texture != null else float(CANVAS_SIZE.x)
		)
	return (WORLD_LENGTH_TILES_QUEEN * TILE_SIZE) / _queen_reference_width_cache


## The real opaque-pixel width of `texture`'s own image -- shared measure
## behind both world_scale (a forager's fly cycle) and queen_world_scale
## (the queen's static pose): how wide the ACTUAL drawing is once
## normalized onto CANVAS_SIZE, not the canvas's own fixed width.
static func _measure_reference_width(texture: ImageTexture) -> float:
	var frame: Image = texture.get_image()
	var min_x := frame.get_width()
	var max_x := -1
	for y in frame.get_height():
		for x in frame.get_width():
			if frame.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return float(max_x - min_x + 1) if max_x >= min_x else float(CANVAS_SIZE.x)
