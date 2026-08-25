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
	# Deliberately NOT rim-shaded -- see _rim_shade's own doc comment: a
	# floor is a continuous surface, and rimming each cell drew a grid over
	# every room.
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
	# Deliberately NOT rim-shaded -- see _rim_shade's own doc comment. A run
	# of wall cells is one wall; rimming each of them is what made a house's
	# visible facade read as a row of separate panels. Door and window still
	# outline their own leaf/pane (see _outline_rect), so they stay legible
	# against the unbroken wall around them.
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


## ## Pitched roof variants (docs/concept/building.md "How a house reads
## from above")
##
## A roof tiled from ONE flat shingle image reads, from above, as a brick
## patio -- a large part of why village houses were reported as "randomly
## placed stones and wood panels". Two things fix that, and both are
## per-cell CONTEXT rather than per-cell art, so they arrive here as a
## (band, mask) pair computed by RoofShape:
##
## - `band`: where this cell sits on the pitch. Brightest at the ridge,
##   falling toward the eaves, with the light-facing slope a clear step
##   brighter than the shaded one (see shade_factor_for_band).
## - `mask`: which of the cell's sides face OUT of the building (see
##   RoofShape's EDGE_* bits). Only those get a rim, so a run of roof cells
##   reads as one continuous surface with a crisp outline around the whole
##   building, instead of every tile outlining itself.
const RoofShape = preload("res://src/rendering/roof_shape.gd")

## The lit slope's brightness range, ridge -> eave, as a multiplier on the
## roof's base colour. Starts above 1.0 so the ridge genuinely catches the
## light rather than merely being "less dark".
const ROOF_LIT_RIDGE_FACTOR := 1.22
const ROOF_LIT_EAVE_FACTOR := 1.00

## The shaded slope's range. The GAP between ROOF_LIT_EAVE_FACTOR and
## ROOF_SHADED_RIDGE_FACTOR is deliberately the largest step in the whole
## ramp: that hard contrast line, where the two slopes meet, is what reads
## as the ridge beam -- so no separate ridge tile is needed (pinned by
## test_the_step_across_the_ridge_is_larger_than_any_step_within_one_slope).
const ROOF_SHADED_RIDGE_FACTOR := 0.86
const ROOF_SHADED_EAVE_FACTOR := 0.70

## How deep the building's outline is drawn on an outward-facing side, and
## how far its base colour is darkened there -- a roof overhangs its walls
## and casts a shadow under that overhang, which is what gives a house a
## crisp silhouette against the ground rather than fading into it.
const ROOF_RIM_THICKNESS := 2
const ROOF_RIM_DARKEN := 0.55


## The brightness multiplier for one shade band (see RoofShape's band
## numbering: [0, FIRST_SHADED_BAND) is the lit slope, the rest is shaded,
## and within each slope a higher index is further down toward the eave).
## Out-of-range bands clamp rather than extrapolate into absurd values.
static func shade_factor_for_band(band: int) -> float:
	var steps := float(maxi(RoofShape.SHADE_BANDS_PER_SLOPE - 1, 1))
	if band < RoofShape.FIRST_SHADED_BAND:
		var lit_t := clampf(float(band) / steps, 0.0, 1.0)
		return lerpf(ROOF_LIT_RIDGE_FACTOR, ROOF_LIT_EAVE_FACTOR, lit_t)
	var shaded_t := clampf(float(band - RoofShape.FIRST_SHADED_BAND) / steps, 0.0, 1.0)
	return lerpf(ROOF_SHADED_RIDGE_FACTOR, ROOF_SHADED_EAVE_FACTOR, shaded_t)


## One roof cell at a given pitch band and outward-edge mask.
func generate_roof_variant_image(material: String, band: int, mask: int) -> Image:
	var is_stone := material == BuildingPiece.MATERIAL_STONE
	var base := _ROOF_STONE if is_stone else _ROOF_WOOD
	var image := _shingle_image(_scaled(base, shade_factor_for_band(band)))
	_rim_edges(image, mask)
	return image


## The tile/slate COURSE pattern at an arbitrary base colour.
##
## Deliberately not the same weighting as the flat _roof_image below: given
## equal emphasis, horizontal seams plus staggered vertical joints is a
## running-bond BRICK course, which is exactly what made a roof read as a
## patio from above. A real tiled roof is a stack of overlapping horizontal
## courses, so the course lines are drawn hard and the vertical joints
## between individual tiles only faintly -- the eye reads rows of roof tiles
## rather than a brick wall lying on its back.
const _COURSE_LINE_FACTOR := 0.74
const _TILE_JOINT_FACTOR := 0.90


func _shingle_image(base: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(base)
	var course := _scaled(base, _COURSE_LINE_FACTOR)
	var joint := _scaled(base, _TILE_JOINT_FACTOR)
	for y in SIZE:
		if y % _SHINGLE_ROW_HEIGHT == 0:
			for x in SIZE:
				image.set_pixel(x, y, course)
			continue
		var row_index := y / _SHINGLE_ROW_HEIGHT
		var offset := (row_index % 2) * _SHINGLE_STAGGER
		for x in SIZE:
			if (x + offset) % (_SHINGLE_ROW_HEIGHT * 2) == 0:
				image.set_pixel(x, y, joint)
	return image


## Darkens ONLY the sides named by `mask` -- the building's own silhouette.
## An interior cell (mask 0) is left completely untouched, which is the
## whole point: rimming every tile is what made a wall ring read as twenty
## separate outlined boxes.
func _rim_edges(image: Image, mask: int) -> void:
	if mask & RoofShape.EDGE_NORTH:
		for y in ROOF_RIM_THICKNESS:
			for x in SIZE:
				image.set_pixel(x, y, _scaled(image.get_pixel(x, y), ROOF_RIM_DARKEN))
	if mask & RoofShape.EDGE_SOUTH:
		for y in ROOF_RIM_THICKNESS:
			for x in SIZE:
				image.set_pixel(x, SIZE - 1 - y, _scaled(image.get_pixel(x, SIZE - 1 - y), ROOF_RIM_DARKEN))
	if mask & RoofShape.EDGE_WEST:
		for x in ROOF_RIM_THICKNESS:
			for y in SIZE:
				image.set_pixel(x, y, _scaled(image.get_pixel(x, y), ROOF_RIM_DARKEN))
	if mask & RoofShape.EDGE_EAST:
		for x in ROOF_RIM_THICKNESS:
			for y in SIZE:
				image.set_pixel(SIZE - 1 - x, y, _scaled(image.get_pixel(SIZE - 1 - x, y), ROOF_RIM_DARKEN))


static func _scaled(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a
	)


## Lighten the top-left rim, darken the bottom-right -- the same convention
## ProceduralStructureSprite's furnace tile uses.
##
## No longer applied to floor or wall pieces (see docs/concept/building.md
## "How a house reads from above"): those tile out in RUNS, and a per-tile
## rim on a run draws a bright/dark line at every internal seam, so twenty
## wall cells rendered as twenty individually-outlined boxes -- reported as
## houses that look like "randomly placed stones and wood panels". A rim
## belongs on the STRUCTURE's outer boundary, which for roofs is now the
## edge mask (see _rim_edges) and for the facade is simply the contrast
## against the ground and the roof's own overhang shadow above it.
##
## Still used by the flat fallback roof tile, which is a single standalone
## catalog swatch (see atlas_coords_for_modification) rather than something
## that tiles against copies of itself.
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
