extends RefCounted

## Deterministic offline pixel-art for BuildingPiece.PIECE_IDS (see
## docs/concept/building.md#pieces and TerrainRenderer.atlas_coords_for_
## modification). Same shape as ProceduralStructureSprite: one full opaque
## ART_TILE_SIZE ground-plane tile per id -- these ARE the ground/wall cell,
## not a sprite layered over one -- shaded/outlined via PixelPalette, no
## RandomNumberGenerator. Unlike biome tiles there is exactly one image per
## id (no per-position variant): every "wood_wall" cell in the world shares
## the same atlas tile, matching how campfire/furnace already work.
##
## Five categories x two materials = 10 tiles, each visually distinct so a
## player can tell floor from wall from door from window from roof at a
## glance, and wood from stone at a glance:
##   floor  -- plank/flagstone pattern, walkable ground
##   wall   -- log/brick pattern, the structural backbone
##   door   -- a door-shaped panel set into the wall's own material
##   window -- a wall with a pale glass pane inset
##   roof   -- a shingle/thatch pattern, distinct from floor's plank look

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SIZE := TerrainRenderer.ART_TILE_SIZE

## Base tones per material -- wood warm brown, stone cool grey, matching the
## existing campfire (warm)/furnace (cool) art-direction convention.
const _WOOD_BASE := Color(0.52, 0.36, 0.18)
const _STONE_BASE := Color(0.55, 0.55, 0.58)

## Door leaf and window pane read the same across both materials -- a door
## is a door regardless of what the wall around it is made of.
const _DOOR_COLOR := Color(0.36, 0.22, 0.08)
const _DOOR_HANDLE_COLOR := Color(0.85, 0.75, 0.35)
const _PANE_COLOR := Color(0.62, 0.78, 0.85)
const _ROOF_WOOD := Color(0.58, 0.28, 0.14)
const _ROOF_STONE := Color(0.32, 0.32, 0.36)

var _palette := PixelPalette.new()


func generate_texture(piece_id: String) -> ImageTexture:
	return ImageTexture.create_from_image(generate_image(piece_id))


## Unknown ids fall back to a plain wood floor (fail-safe default, matching
## this codebase's `.get(x, default)` convention) rather than crashing --
## TerrainRenderer.atlas_coords_for_modification is what actually decides
## whether an id gets a dedicated atlas slot at all.
func generate_image(piece_id: String) -> Image:
	var category := BuildingPiece.category_of(piece_id)
	var material := BuildingPiece.material_of(piece_id)
	var is_stone := material == BuildingPiece.MATERIAL_STONE
	var base := _STONE_BASE if is_stone else _WOOD_BASE

	match category:
		BuildingPiece.CATEGORY_WALL:
			return _wall_image(base, is_stone)
		BuildingPiece.CATEGORY_DOOR:
			return _door_image(base, is_stone)
		BuildingPiece.CATEGORY_WINDOW:
			return _window_image(base, is_stone)
		BuildingPiece.CATEGORY_ROOF:
			return _roof_image(is_stone)
		_:
			return _floor_image(base, is_stone)


## Plank rows (wood) or flagstone blocks (stone), horizontal seams so it
## reads as ground you walk ACROSS, distinct from the wall's vertical grain.
const _PLANK_ROW_HEIGHT := 8
const _FLAGSTONE_SIZE := 10


func _floor_image(base: Color, is_stone: bool) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(base)
	var seam := _palette.shade(base)
	if is_stone:
		for y in SIZE:
			for x in SIZE:
				if x % _FLAGSTONE_SIZE == 0 or y % _FLAGSTONE_SIZE == 0:
					image.set_pixel(x, y, seam)
	else:
		for y in SIZE:
			if y % _PLANK_ROW_HEIGHT == 0:
				for x in SIZE:
					image.set_pixel(x, y, seam)
	_rim_shade(image)
	return image


## Vertical log grain (wood) or a running-bond brick course (stone) -- the
## structural backbone, reading as something you CAN'T walk through.
const _LOG_WIDTH := 8
const _BRICK_ROW_HEIGHT := 8
const _BRICK_JOINT_SPACING := 12
const _BRICK_JOINT_OFFSET := 6


func _wall_image(base: Color, is_stone: bool) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(base)
	var seam := _palette.shade(base)
	if is_stone:
		for y in SIZE:
			if y % _BRICK_ROW_HEIGHT == 0:
				for x in SIZE:
					image.set_pixel(x, y, seam)
				continue
			var row_index := y / _BRICK_ROW_HEIGHT
			var offset := 0 if row_index % 2 == 0 else _BRICK_JOINT_OFFSET
			for x in SIZE:
				if (x + offset) % _BRICK_JOINT_SPACING == 0:
					image.set_pixel(x, y, seam)
	else:
		for y in SIZE:
			for x in SIZE:
				if x % _LOG_WIDTH == 0:
					image.set_pixel(x, y, seam)
	_rim_shade(image)
	return image


## A door leaf set into the wall's own material frame -- the frame keeps a
## door reading as "belongs in this wall" while the leaf + handle make it
## unmistakably a door rather than a plain wall tile.
const _DOOR_FRAME_MARGIN := 3
const _DOOR_HANDLE_POS := Vector2i(SIZE - 9, SIZE / 2)


func _door_image(base: Color, is_stone: bool) -> Image:
	var image := _wall_image(base, is_stone)
	for y in range(_DOOR_FRAME_MARGIN, SIZE - _DOOR_FRAME_MARGIN):
		for x in range(_DOOR_FRAME_MARGIN, SIZE - _DOOR_FRAME_MARGIN):
			image.set_pixel(x, y, _DOOR_COLOR)
	# A couple of plank seams on the leaf itself, so it doesn't read as a
	# flat rectangle.
	for x in [_DOOR_FRAME_MARGIN + SIZE / 3, _DOOR_FRAME_MARGIN + 2 * SIZE / 3]:
		for y in range(_DOOR_FRAME_MARGIN, SIZE - _DOOR_FRAME_MARGIN):
			image.set_pixel(x, y, _palette.shade(_DOOR_COLOR))
	image.set_pixel(_DOOR_HANDLE_POS.x, _DOOR_HANDLE_POS.y, _DOOR_HANDLE_COLOR)
	_outline_rect(image, Vector2i(_DOOR_FRAME_MARGIN, _DOOR_FRAME_MARGIN), SIZE - _DOOR_FRAME_MARGIN * 2)
	return image


## A wall with a pale glass pane inset, mullion cross included.
const _PANE_MARGIN := 6


func _window_image(base: Color, is_stone: bool) -> Image:
	var image := _wall_image(base, is_stone)
	for y in range(_PANE_MARGIN, SIZE - _PANE_MARGIN):
		for x in range(_PANE_MARGIN, SIZE - _PANE_MARGIN):
			image.set_pixel(x, y, _PANE_COLOR)
	var mid := SIZE / 2
	for y in range(_PANE_MARGIN, SIZE - _PANE_MARGIN):
		image.set_pixel(mid, y, base)
	for x in range(_PANE_MARGIN, SIZE - _PANE_MARGIN):
		image.set_pixel(x, mid, base)
	_outline_rect(image, Vector2i(_PANE_MARGIN, _PANE_MARGIN), SIZE - _PANE_MARGIN * 2)
	return image


## Overlapping shingle rows (wood) or flatter slate rows (stone) -- a
## diagonal stagger so it reads as roofing, not another floor/wall pattern.
const _SHINGLE_ROW_HEIGHT := 6
const _SHINGLE_STAGGER := 4


func _roof_image(is_stone: bool) -> Image:
	var base := _ROOF_STONE if is_stone else _ROOF_WOOD
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(base)
	var seam := _palette.shade(base)
	for y in SIZE:
		if y % _SHINGLE_ROW_HEIGHT == 0:
			for x in SIZE:
				image.set_pixel(x, y, seam)
			continue
		var row_index := y / _SHINGLE_ROW_HEIGHT
		var offset := (row_index % 2) * _SHINGLE_STAGGER
		for x in SIZE:
			if (x + offset) % (_SHINGLE_ROW_HEIGHT * 2) == 0:
				image.set_pixel(x, y, seam)
	_rim_shade(image)
	return image


## Lighten the top-left rim, darken the bottom-right -- the same convention
## ProceduralStructureSprite's furnace tile uses, applied to every piece so
## the whole roster reads as one consistent lighting model.
func _rim_shade(image: Image) -> void:
	for x in SIZE:
		image.set_pixel(x, 0, _palette.highlight(image.get_pixel(x, 0)))
		image.set_pixel(x, SIZE - 1, _palette.shade(image.get_pixel(x, SIZE - 1)))
	for y in SIZE:
		image.set_pixel(0, y, _palette.highlight(image.get_pixel(0, y)))
		image.set_pixel(SIZE - 1, y, _palette.shade(image.get_pixel(SIZE - 1, y)))


func _outline_rect(image: Image, top_left: Vector2i, size: int) -> void:
	var outline := _palette.outline_color()
	for x in range(top_left.x, top_left.x + size):
		image.set_pixel(x, top_left.y, outline)
		image.set_pixel(x, top_left.y + size - 1, outline)
	for y in range(top_left.y, top_left.y + size):
		image.set_pixel(top_left.x, y, outline)
		image.set_pixel(top_left.x + size - 1, y, outline)
