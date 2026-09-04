extends RefCounted

## Real illustrated combat art for items that have a composite sheet under
## assets/sprites/items/ -- currently just `wooden_club`, the pilot
## docs/concept/item_illustrations.md ("Combat sheets: attack, defense,
## condition") specs before iron_sword/crude_blade or the rest of the
## catalog follow. Every other item keeps ProceduralItemSprite's generated
## icon and WeaponSwing's procedural rotation; callers check has_item()/
## has_action()/has_condition() first and fall back themselves, the same
## "ask before you leap" shape CreatureMarker uses with
## IllustratedAnimalSprite.
##
## One sheet, two rows, per docs/art/ai_sprite_prompts.md section 11:
##   row 1 -- the attack swing, 8 frames (wind-up 1-3, release 4-5,
##            recovery 6-8), the club ALONE around a fixed grip pivot;
##   row 2 -- three static cells at FIXED indices: defense (a held guard
##            pose -- blocking is a level, not a swing), worn, broken.
## Registered the same `_SHEETS`/"<action>_bands" shape
## IllustratedAnimalSprite uses, with `condition_bands` as the second row's
## key and CONDITION_INDEX as the fixed-position read.
##
## Deliberately NOT IllustratedAnimalSprite's slicing: that one crops every
## frame to its drawing and stands it on a shared baseline, which is right
## for feet on the ground and wrong for a swing -- a club rotating around
## its grip has to keep the grip in the same place, and a content crop moves
## it every frame. So frames are detected as whole CELLS (the columns
## between divider lines, found BEFORE chroma-keying while the ground is
## still opaque) and returned at cell size with the ground keyed out, no
## content crop, no rescale. Whatever is drawn at a cell pixel stays at
## that pixel. Frames from one row therefore share a size when the sheet's
## cells do (every generated sheet's do); nothing here assumes they must.
##
## The current sheet is the SAMPLE WoodenClubSheetPainter paints (see
## tools/generate_wooden_club_sheet.gd) -- a stand-in in the prompt's exact
## format, not image-model output. Replacing it with real art is a file
## swap plus re-measured bands below; test_illustrated_item_sprite.gd pins
## these bands to the painter's layout so a regenerated sample cannot
## silently drift from them.

const SpriteSheetSlicer = preload("res://src/rendering/sprite_sheet_slicer.gd")
const SpriteSheetLoader = preload("res://src/rendering/sprite_sheet_loader.gd")

## Row 2's fixed cell order. A pristine item has no cell of its own: it is
## simply the attack cycle's own neutral final frame.
const CONDITION_INDEX := {"defense": 0, "worn": 1, "broken": 2}

## The narrowest run of columns that can be a cell; a stray anti-aliased
## column beside a divider is not one.
const MIN_CELL_WIDTH := 60

const _SHEETS := {
	"wooden_club": {
		"path": "res://assets/sprites/items/wooden_club_combat.png",
		# 2898x606: two 300px rows of 360px cells boxed by a 2px near-white
		# grid (WoodenClubSheetPainter.CELL_SIZE / DIVIDER). Bands are the
		# rows between the horizontal rules, divider lines excluded.
		"attack_bands": [Vector2i(2, 302)],
		"condition_bands": [Vector2i(304, 604)],
		"alpha_threshold": 0.3,
		# Solid pure magenta ground, the same key and tolerance the boss
		# sheets use; the sample's ground is exact, the tolerance is for the
		# generated art that will replace it.
		"chroma_key": Color(1.0, 0.0, 1.0),
		"chroma_key_tolerance": 0.25,
	},
}

var _slicer := SpriteSheetSlicer.new()

## "item/action" -> Array[ImageTexture], shared across instances: every
## club shows the identical frames, and a full-sheet scan per caller would
## be a real stall for no gain.
static var _frame_cache: Dictionary = {}


func has_item(item_id: String) -> bool:
	return _SHEETS.has(item_id)


## Only actions with a registered "<action>_bands" row -- no fallback
## chain: an item with no attack art keeps its procedural swing outright,
## rather than borrowing another action's frames.
func has_action(item_id: String, action: String) -> bool:
	if not _SHEETS.has(item_id):
		return false
	return _SHEETS[item_id].has(action + "_bands")


func has_condition(item_id: String, condition: String) -> bool:
	if not CONDITION_INDEX.has(condition):
		return false
	return has_action(item_id, "condition")


func attack_bands(item_id: String) -> Array:
	return _bands(item_id, "attack")


func condition_bands(item_id: String) -> Array:
	return _bands(item_id, "condition")


func _bands(item_id: String, action: String) -> Array:
	if not has_action(item_id, action):
		return []
	return _SHEETS[item_id][action + "_bands"]


## The frames of `item_id`'s `action` row, each a whole keyed-out cell (see
## the class comment), sliced once and cached. Empty for anything
## has_action rejects.
func generate_textures(item_id: String, action: String) -> Array[ImageTexture]:
	if not has_action(item_id, action):
		return []
	var key := "%s/%s" % [item_id, action]
	if not _frame_cache.has(key):
		var textures: Array[ImageTexture] = []
		for cell in _slice_cells(_SHEETS[item_id], _SHEETS[item_id][action + "_bands"]):
			textures.append(ImageTexture.create_from_image(cell))
		_frame_cache[key] = textures
	return _frame_cache[key]


## The single static cell for `condition` ("defense"/"worn"/"broken"), or
## null when the item has no condition row or the row is short a cell.
func condition_texture(item_id: String, condition: String) -> ImageTexture:
	if not has_condition(item_id, condition):
		return null
	var cells := generate_textures(item_id, "condition")
	var index: int = CONDITION_INDEX[condition]
	if index >= cells.size():
		return null
	return cells[index]


## Every cell in `bands`, in list order: cells are the runs of columns
## between near-white divider lines, found on the UNKEYED sheet (the
## opaque ground keeps a cell's empty columns from reading as dividers),
## then cut out whole and keyed.
func _slice_cells(sheet: Dictionary, bands: Array) -> Array[Image]:
	var image := SpriteSheetLoader.load_image(sheet["path"])
	var cells: Array[Image] = []
	if image == null:
		return cells
	var alpha_threshold: float = sheet["alpha_threshold"]
	var divider_gray_min: float = sheet.get("divider_gray_min", SpriteSheetSlicer.DEFAULT_DIVIDER_GRAY_MIN)
	for band in bands:
		var rows: Vector2i = band
		var rects := _slicer.detect_frames(
			image, rows.x, rows.y, MIN_CELL_WIDTH, 1, alpha_threshold, divider_gray_min
		)
		for rect in rects:
			cells.append(_cut_cell(image.get_region(rect), sheet, alpha_threshold, divider_gray_min))
	return cells


func _cut_cell(cell: Image, sheet: Dictionary, alpha_threshold: float, divider_gray_min: float) -> Image:
	if cell.get_format() != Image.FORMAT_RGBA8:
		cell.convert(Image.FORMAT_RGBA8)
	if sheet.has("chroma_key"):
		cell = SpriteSheetSlicer.chroma_keyed(
			cell, sheet["chroma_key"], sheet.get("chroma_key_tolerance", 0.1)
		)
	# Anything the slicer would call background -- a divider's anti-aliased
	# edge that leaked into the cell, a keyed pixel's faint remainder --
	# goes fully transparent, so the texture composites clean.
	for y in cell.get_height():
		for x in cell.get_width():
			if SpriteSheetSlicer.is_empty(cell.get_pixel(x, y), alpha_threshold, divider_gray_min):
				cell.set_pixel(x, y, Color(0, 0, 0, 0))
	return cell
