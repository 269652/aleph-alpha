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
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

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
## The sheet's own two narrow corner-post columns -- a real wall TRIM
## strip, confirmed by the user as art for the 1/4-thick wall treatment
## (see thin_wall_variant_image below). Only the first is wired; the
## second stays real, unused art held in reserve, matching the second wall
## colour variant (_WALL_COLUMN's own sibling) directly beside it.
const _THIN_WALL_COLUMN := 4

## A wall trim strip is drawn this thick against whichever edge(s) of the
## tile are outward (BuildingPiece.outward_wall_mask) -- one quarter of the
## tile, matching EarthChunkManager's own collision thickness for the same
## cells exactly (see WALL_THICKNESS_FRACTION there), so what's SEEN lines
## up with what's actually solid.
const THIN_WALL_THICKNESS := SIZE / 4

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

var _slicer := SpriteSheetSlicer.new()

## piece_id -> the final, cached ART_TILE_SIZE Image.
static var _cache: Dictionary = {}
## sheet path -> the raw loaded, chroma-keyed (NOT yet cropped) Image,
## shared across every piece that crops from the same sheet.
static var _keyed_sheet_cache: Dictionary = {}
## sheet path -> the row-0 frame Rect2i array detect_frames found, shared
## across every piece cropping a column from that sheet.
static var _row0_frames_cache: Dictionary = {}


func has_piece_art(piece_id: String) -> bool:
	return _WALL_PIECES.has(piece_id) or _FLOOR_PIECES.has(piece_id)


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
	if image != null:
		_cache[piece_id] = image
	return image


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


# -- thin wall art (docs/concept/building.md "How a house reads from
# above", point 8): "walls are now 1 Tile thick... they should be 1/4 tile
# wide the rest of the 3/4 wall should be made walkable floor". The
# sheet's own narrow corner-post column IS the trim strip, confirmed by
# the user; the room's own floor tile (whatever TerrainRenderer already
# resolved for that material -- illustrated if available, else procedural)
# is the base most of the tile shows through as.

## Whether `material` has a real wall sheet to draw a thin-wall trim strip
## from -- callers must check this before calling thin_wall_strip_image/
## thin_wall_variant_image and keep the plain full-tile wall otherwise.
func has_thin_wall_art(material: String) -> bool:
	return _WALL_PIECES.has("%s_wall" % material)


## The narrow corner-post column for `material`, resized to
## THIN_WALL_THICKNESS wide x SIZE tall -- the one reusable strip every
## outward edge composites onto a floor base, rotated for a horizontal
## (north/south) edge by the caller. Null when has_thin_wall_art would
## answer false.
func thin_wall_strip_image(material: String) -> Image:
	if not has_thin_wall_art(material):
		return null
	var cache_key := "%s_thin_wall_strip" % material
	if _cache.has(cache_key):
		return _cache[cache_key]
	var path: String = _WALL_PIECES["%s_wall" % material]["path"]
	var sheet := _keyed_sheet(path)
	var frames := _row0_frames(path, sheet)
	if _THIN_WALL_COLUMN >= frames.size():
		return null
	var cropped := sheet.get_region(frames[_THIN_WALL_COLUMN])
	var strip := cropped.duplicate() as Image
	strip.resize(THIN_WALL_THICKNESS, SIZE, Image.INTERPOLATE_LANCZOS)
	_cache[cache_key] = strip
	return strip


## `floor_base` (ART_TILE_SIZE, whatever TerrainRenderer already resolved
## for this material's floor) with `material`'s own trim strip composited
## flush against every outward side `outward_mask` (BuildingPiece.EDGE_*
## bits) sets -- a straight wall run gets one side, a building's own
## corner gets two (an L, drawn as two overlapping strips). `outward_mask
## == 0` (a wall cell bordering only its own building on every side --
## shouldn't happen for a real wall, but defensively) returns floor_base
## untouched, and a material with no thin-wall art returns floor_base
## untouched too (the plain full-tile wall wins for that material).
func thin_wall_variant_image(material: String, outward_mask: int, floor_base: Image) -> Image:
	var image := floor_base.duplicate() as Image
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != SIZE or image.get_height() != SIZE:
		image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var vertical := thin_wall_strip_image(material)
	if vertical == null:
		return image
	var full_rect := Rect2i(Vector2i.ZERO, vertical.get_size())
	if outward_mask & BuildingPiece.EDGE_WEST != 0:
		image.blend_rect(vertical, full_rect, Vector2i(0, 0))
	if outward_mask & BuildingPiece.EDGE_EAST != 0:
		image.blend_rect(vertical, full_rect, Vector2i(SIZE - vertical.get_width(), 0))
	if outward_mask & (BuildingPiece.EDGE_NORTH | BuildingPiece.EDGE_SOUTH) != 0:
		var horizontal := _rotated_90(vertical)
		var horizontal_rect := Rect2i(Vector2i.ZERO, horizontal.get_size())
		if outward_mask & BuildingPiece.EDGE_NORTH != 0:
			image.blend_rect(horizontal, horizontal_rect, Vector2i(0, 0))
		if outward_mask & BuildingPiece.EDGE_SOUTH != 0:
			image.blend_rect(horizontal, horizontal_rect, Vector2i(0, SIZE - horizontal.get_height()))
	return image


## A 90-degree clockwise pixel rotation -- Image carries no rotate() of its
## own. Turns the vertical strip's long axis (its own wood/stone grain
## direction) horizontal, which is what a strip along the tile's top/bottom
## edge needs; a symmetric plank/block pattern reads correctly either
## rotation direction, so CW-vs-CCW is not a meaningful choice here.
static func _rotated_90(image: Image) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var rotated := Image.create(h, w, false, image.get_format())
	for y in h:
		for x in w:
			rotated.set_pixel(y, w - 1 - x, image.get_pixel(x, y))
	return rotated
