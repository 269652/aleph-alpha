extends RefCounted

## Reads the glass_bottle composite sheet's fixed 3x2 grid (docs/concept/
## capture_dsl.md's "Rendering a bottled catch"): three condition columns
## (pristine/worn/broken, reusing item_durability.md's existing
## ItemWear.condition_for vocabulary rather than inventing a second one) by
## two rows -- row 0 uncorked (the back layer, what sits behind whatever the
## bottle holds), row 1 corked (the front layer, the near glass and its
## seal).
##
## A FIXED-position read, not composite_sheet_slicer.gd's blob detection --
## that tool exists because tree sheets lay their drawings out irregularly,
## at varying sizes, with strays bridging the gaps between them. This grid
## is regular and its shape is known in advance (measured: 1536x1024, six
## 512x512 cells), so it's cut the same simple "fixed Y/X bands" way
## item_illustrations.md's wooden_club sheet already is.

const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

const SHEET_PATH := "res://assets/sprites/items/glass_bottle.png"
const GRID_COLUMNS := 3
const GRID_ROWS := 2
const BACK_ROW := 0
const FRONT_ROW := 1

## Column order, left to right on the sheet -- the same three states
## ItemWear.condition_for already reports.
const CONDITIONS := ["pristine", "worn", "broken"]
const DEFAULT_CONDITION := "pristine"

static var _sheet: Image = null
static var _sheet_loaded := false
static var _frame_cache: Dictionary = {}


static func _sheet_image() -> Image:
	if not _sheet_loaded:
		_sheet = SpriteSheetLoader.load_image(SHEET_PATH)
		_sheet_loaded = true
	return _sheet


func is_available() -> bool:
	return _sheet_image() != null


func back_texture_for(condition: String) -> ImageTexture:
	return _cell(BACK_ROW, condition)


func front_texture_for(condition: String) -> ImageTexture:
	return _cell(FRONT_ROW, condition)


func _cell(row: int, condition: String) -> ImageTexture:
	var sheet := _sheet_image()
	if sheet == null:
		return null
	var resolved_condition := condition if CONDITIONS.has(condition) else DEFAULT_CONDITION
	var key := "%d_%s" % [row, resolved_condition]
	if not _frame_cache.has(key):
		var cell_width := sheet.get_width() / GRID_COLUMNS
		var cell_height := sheet.get_height() / GRID_ROWS
		var column := CONDITIONS.find(resolved_condition)
		var region := Rect2i(column * cell_width, row * cell_height, cell_width, cell_height)
		_frame_cache[key] = ImageTexture.create_from_image(sheet.get_region(region))
	return _frame_cache[key]
