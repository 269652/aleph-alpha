extends RefCounted

## Real illustrated wall/door/window/floor art (docs/concept/building.md),
## used by TerrainRenderer in place of ProceduralBuildingPieceSprite's
## generated pattern for any piece id this class knows -- the same
## has_X()-gated fallback convention IllustratedTerrainSprite already
## establishes for biome ground tiles (TerrainRenderer checks has_variants
## before calling frame_for; here it checks has_piece_art before calling
## piece_image). Reported directly: NPC buildings "look poor and basic; not
## like sophisticated architecture" -- a real user-supplied illustration
## reads as an actual built wall/door/window rather than a flat procedural
## brick/plank pattern.
##
## wood_wall.png/stone_wall.png: a 6-column x 2-row sheet -- door, window,
## wall, a second wall colour variant, and two narrower corner-post
## variants. Only column 0 (door), column 1 (window) and column 2 (wall),
## row 0, are wired here: the second wall variant, the corner posts, and
## row 1 are real, unused art held in reserve (not yet assigned a role --
## the corner posts in particular look shaped for a future sub-tile
## wall-thickness treatment, not confirmed, so nothing guesses at that
## yet). wood_floor.png is its own single full-bleed image, no grid.
##
## PROBE-BEFORE-TRUST (a naive even 6-way column split visibly straddled
## the window/wall divider when actually cropped and viewed -- the sheet's
## real columns are NOT equal width: door/window/wall run ~328px, the two
## corner posts only ~216px): columns are found LIVE via SpriteSheetSlicer.
## detect_frames within a measured row-0 content band
## (_ROW0_TOP/_ROW0_BOTTOM, safely inside both current sheets' own
## top-border and row-separator divider lines), the same "scan for real
## empty columns, don't assume even division" approach IllustratedTerrain
## Sprite already uses for its own biome sheets. `column` in _WALL_PIECES
## below is therefore an ORDINAL (the Nth frame left to right), not a pixel
## position -- robust to the small per-sheet divider-position drift already
## measured between wood_wall.png and stone_wall.png (independently
## generated, a few px apart) and to whatever the next material sheet
## measures at.
##
## Chroma key: magenta divider line ALWAYS keyed (same measured thresholds
## as IllustratedStructureSprite/IllustratedBeehiveSprite -- reused, not
## reinvented) plus the sheets' own real near-black background -- keyed to
## genuine alpha=0 BEFORE detect_frames runs, with its own gray-divider
## heuristic disabled (IllustratedTerrainSprite's identical shape: real
## alpha already carries the divider signal, and a pale stone highlight
## must not be misread as a divider column).

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SIZE := TerrainRenderer.ART_TILE_SIZE

## Same measured thresholds as IllustratedStructureSprite -- reused, not
## reinvented.
const _MAGENTA_RED_MIN := 0.85
const _MAGENTA_BLUE_MIN := 0.85
const _MAGENTA_GREEN_MAX := 0.15
const _MAGENTA_CAST_MARGIN := 0.03

## How dark a pixel must be (per channel) to read as these sheets' own
## near-black background -- same margin-above-zero rationale as
## IllustratedStructureSprite's own _BLACK_MAX.
const _BLACK_MAX := 0.05

## Row 0's real content band, measured directly against both current sheets
## (wood_wall.png/stone_wall.png, 1774x887): the top border divider ends by
## y=6, the row-separator divider starts at y=440 on both -- this stays a
## few px inside each on both sides, the same "a couple of pixels of slop"
## margin IllustratedTerrainSprite's own row_bands already accept.
const _ROW0_TOP := 8
const _ROW0_BOTTOM := 436

## Disables SpriteSheetSlicer.detect_frames' own pale-gray-divider
## heuristic -- see this file's own header doc comment for why: real alpha
## (from this file's OWN keying pass, below) is the only divider signal
## that's safe against a legitimately pale stone highlight.
const _DISABLED_DIVIDER_GRAY_MIN := 1.01

const _DOOR_COLUMN := 0
const _WINDOW_COLUMN := 1
const _WALL_COLUMN := 2

## piece_id -> {sheet path, column ordinal (the Nth detected frame, left to
## right -- see this file's header doc comment for why an ordinal, not a
## pixel position)}. Every entry reads row 0 of its sheet.
const _WALL_PIECES := {
	"wood_wall": {"path": "res://assets/sprites/buildings/wood_wall.png", "column": _WALL_COLUMN},
	"wood_door": {"path": "res://assets/sprites/buildings/wood_wall.png", "column": _DOOR_COLUMN},
	"wood_window": {"path": "res://assets/sprites/buildings/wood_wall.png", "column": _WINDOW_COLUMN},
	"stone_wall": {"path": "res://assets/sprites/buildings/stone_wall.png", "column": _WALL_COLUMN},
	"stone_door": {"path": "res://assets/sprites/buildings/stone_wall.png", "column": _DOOR_COLUMN},
	"stone_window": {"path": "res://assets/sprites/buildings/stone_wall.png", "column": _WINDOW_COLUMN},
}

## piece_id -> sheet path, one full-bleed image each, no grid.
const _FLOOR_PIECES := {
	"wood_floor": "res://assets/sprites/buildings/wood_floor.png",
}

## Furniture art (docs/concept/building.md "Asset contract"): one square
## image per CATEGORY_FURNITURE piece id at `<furniture_dir>/<piece_id>.png`
## -- top-down, the object centred, background transparent or the sheets'
## own black/magenta (keyed by the same pass the wall sheets use) --
## composited over the wood floor and resized to ART_TILE_SIZE so the
## atlas tile stays opaque. No registry to edit: dropping the file in is
## what lights it up (after an ATLAS_VERSION bump, like every sheet). The
## directory is an instance var so a test can point it at a fixture.
const DEFAULT_FURNITURE_DIR := "res://assets/sprites/furniture"
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
## A plain wood fill for the floor under a furniture piece when the
## illustrated wood_floor sheet itself is missing -- the tile must never be
## left with a transparent hole in the atlas.
const _FALLBACK_FLOOR := Color(0.62, 0.45, 0.28)

var furniture_dir: String = DEFAULT_FURNITURE_DIR

var _slicer := SpriteSheetSlicer.new()

## piece_id -> the final, cached ART_TILE_SIZE Image.
static var _cache: Dictionary = {}
## sheet path -> the raw loaded, chroma-keyed (NOT yet cropped) Image,
## shared across every piece that crops from the same sheet.
static var _keyed_sheet_cache: Dictionary = {}
## sheet path -> the row-0 frame Rect2i array detect_frames found, shared
## across every piece cropping a column from that sheet.
static var _row0_frames_cache: Dictionary = {}
## furniture PNG path -> whether it exists, so has_piece_art (asked once
## per piece per atlas build, and by every paint) never hits the disk twice
## for the same file in one process.
static var _furniture_exists_cache: Dictionary = {}


func has_piece_art(piece_id: String) -> bool:
	if _WALL_PIECES.has(piece_id) or _FLOOR_PIECES.has(piece_id):
		return true
	return _has_furniture_png(piece_id)


## The real illustrated art for `piece_id`, keyed/despilled/cropped/resized
## to exactly ART_TILE_SIZE, or null when has_piece_art would answer false
## -- callers must check that first and fall back to the procedural
## generator themselves, the same contract IllustratedTerrainSprite.
## frame_for already establishes.
func piece_image(piece_id: String) -> Image:
	if _cache.has(piece_id):
		return _cache[piece_id]
	var image: Image = null
	if _WALL_PIECES.has(piece_id):
		image = _wall_piece_image(_WALL_PIECES[piece_id])
	elif _FLOOR_PIECES.has(piece_id):
		image = _floor_piece_image(_FLOOR_PIECES[piece_id])
	elif _has_furniture_png(piece_id):
		image = _furniture_piece_image(_furniture_png_path(piece_id))
	if image != null:
		_cache[piece_id] = image
	return image


## Drops every cached answer for `piece_id` -- a test that writes or
## removes a fixture PNG mid-process needs the next has_piece_art/
## piece_image to look again rather than trust the cache.
static func forget_cached(piece_id: String) -> void:
	_cache.erase(piece_id)
	for path in _furniture_exists_cache.keys().duplicate():
		if path.ends_with("/%s.png" % piece_id):
			_furniture_exists_cache.erase(path)
			_keyed_sheet_cache.erase(path)


func _furniture_png_path(piece_id: String) -> String:
	return "%s/%s.png" % [furniture_dir, piece_id]


## Only a real CATEGORY_FURNITURE piece ever consults the furniture
## directory -- a stray file named after a wall piece changes nothing.
func _has_furniture_png(piece_id: String) -> bool:
	if BuildingPiece.category_of(piece_id) != BuildingPiece.CATEGORY_FURNITURE:
		return false
	var path := _furniture_png_path(piece_id)
	if not _furniture_exists_cache.has(path):
		_furniture_exists_cache[path] = ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return _furniture_exists_cache[path]


## The furniture PNG keyed (background punched to alpha 0), resized to the
## tile, and composited over the wood floor so the finished tile is opaque
## -- the illustrated wood_floor when it exists, a plain wood fill if not.
func _furniture_piece_image(path: String) -> Image:
	var sheet := _keyed_sheet(path)
	if sheet == null:
		return null
	# Plain fill first, the illustrated floor over it, the furniture on top:
	# whatever the keying pass punched out of either sheet, nothing shows
	# through as a hole.
	var tile := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	tile.fill(_FALLBACK_FLOOR)
	var floor := piece_image("wood_floor") if _FLOOR_PIECES.has("wood_floor") else null
	if floor != null:
		tile.blend_rect(floor, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	tile.blend_rect(_resized(sheet), Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	return tile


func _wall_piece_image(entry: Dictionary) -> Image:
	var path: String = entry["path"]
	var sheet := _keyed_sheet(path)
	if sheet == null:
		return null
	var frames := _row0_frames(path, sheet)
	var column: int = entry["column"]
	if column >= frames.size():
		return null
	return _resized(sheet.get_region(frames[column]))


func _floor_piece_image(path: String) -> Image:
	var sheet := _keyed_sheet(path)
	if sheet == null:
		return null
	return _resized(sheet)


## The row-0 frame rects (door, window, wall, ...) for the sheet at `path`,
## found LIVE via SpriteSheetSlicer.detect_frames -- see this file's header
## doc comment for why not a naive even division. Cached by path.
func _row0_frames(path: String, keyed_sheet: Image) -> Array:
	if _row0_frames_cache.has(path):
		return _row0_frames_cache[path]
	var frames := _slicer.detect_frames(
		keyed_sheet, _ROW0_TOP, _ROW0_BOTTOM,
		SpriteSheetSlicer.DEFAULT_MIN_FRAME_WIDTH, SpriteSheetSlicer.DEFAULT_MIN_DIVIDER_WIDTH,
		SpriteSheetSlicer.DEFAULT_ALPHA_THRESHOLD, _DISABLED_DIVIDER_GRAY_MIN
	)
	_row0_frames_cache[path] = frames
	return frames


## The raw sheet at `path`, loaded once, converted to RGBA8 and chroma-keyed
## (magenta divider line + real near-black background both punched to
## alpha=0, every other pixel despilled) -- cached by path so every piece
## cropping from the same sheet keys it exactly once.
func _keyed_sheet(path: String) -> Image:
	if _keyed_sheet_cache.has(path):
		return _keyed_sheet_cache[path]
	var raw := SpriteSheetLoader.load_image(path)
	if raw == null:
		return null
	var image := raw.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	_key_and_despill(image)
	_keyed_sheet_cache[path] = image
	return image


static func _resized(image: Image) -> Image:
	var resized := image.duplicate() as Image
	resized.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return resized


static func _key_and_despill(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if _is_magenta(pixel) or _is_black(pixel):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, _despilled(pixel))


static func _is_magenta(color: Color) -> bool:
	return color.r >= _MAGENTA_RED_MIN and color.b >= _MAGENTA_BLUE_MIN and color.g <= _MAGENTA_GREEN_MAX


static func _is_black(color: Color) -> bool:
	return color.r <= _BLACK_MAX and color.g <= _BLACK_MAX and color.b <= _BLACK_MAX


static func _despilled(color: Color) -> Color:
	var cast: float = minf(color.r - color.g, color.b - color.g)
	if cast <= _MAGENTA_CAST_MARGIN:
		return color
	var removed := cast - _MAGENTA_CAST_MARGIN
	return Color(
		clampf(color.r - removed, 0.0, 1.0), color.g,
		clampf(color.b - removed, 0.0, 1.0), color.a
	)
