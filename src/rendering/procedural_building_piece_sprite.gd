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
##
## Plus the interior pieces (docs/concept/housing.md): seven furniture
## tiles and the stairs, each an OBJECT drawn on the room's own floor rather
## than a ground tile of its own -- see _furniture_image.

const PixelPalette = preload("res://src/rendering/pixel_palette.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const SIZE := TerrainRenderer.ART_TILE_SIZE

## Base tones per material -- wood warm brown, stone cool grey, matching the
## existing campfire (warm)/furnace (cool) art-direction convention.
const _WOOD_BASE := Color(0.52, 0.36, 0.18)
const _STONE_BASE := Color(0.55, 0.55, 0.58)

## The timber tier (see docs/concept/timber_construction.md) is SAWN
## structural lumber -- Balken and Planken cut at a Sägewerk -- rather than
## the rough round wood the base tier uses, so it reads paler and less
## saturated: a fresh-cut face is closer to the pale inner wood than to
## weathered bark. Without its own base colour, timber_wall/timber_floor
## fell through to _WOOD_BASE and rendered pixel-identical to their wood
## equivalents (pinned by test_every_piece_is_visually_distinct_from_every_other,
## which was failing on exactly that).
const _TIMBER_BASE := Color(0.72, 0.57, 0.34)

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
	# is_stone still selects the PATTERN (brick/flagstone vs plank/log);
	# timber shares wood's pattern -- both are boards and beams -- and is
	# told apart by its own paler base colour instead.
	var base := _base_color_for(material, is_stone)

	match category:
		BuildingPiece.CATEGORY_WALL:
			return _wall_image(base, is_stone)
		BuildingPiece.CATEGORY_DOOR:
			return _door_image(base, is_stone)
		BuildingPiece.CATEGORY_WINDOW:
			return _window_image(base, is_stone)
		BuildingPiece.CATEGORY_ROOF:
			return _roof_image(is_stone)
		BuildingPiece.CATEGORY_DAM:
			return _boulder_image(base) if piece_id == "boulder" else _dam_image(base)
		BuildingPiece.CATEGORY_FURNITURE:
			return _furniture_image(piece_id, base)
		BuildingPiece.CATEGORY_STAIRS:
			return _stairs_image(base)
		_:
			return _floor_image(base, is_stone)


## The base colour a material's pieces are drawn in. Unknown materials fall
## back to wood, matching this file's existing `.get(x, default)`-style
## fail-safe convention rather than crashing on an id it has no art for.
static func _base_color_for(material: String, is_stone: bool) -> Color:
	if is_stone:
		return _STONE_BASE
	if material == BuildingPiece.MATERIAL_TIMBER:
		return _TIMBER_BASE
	return _WOOD_BASE


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


## A dry-stacked check dam: irregular boulders piled across the channel,
## deliberately NOT the wall's neat running-bond courses. The whole point is
## that this is rock a player gathered and heaped, not masonry -- so the
## "bricks" are hash-jittered in size and position, and the gaps between
## them are visible (which is also honest about the real thing: a rubble dam
## leaks through its own voids).
const _RUBBLE_CELL := 7


func _dam_image(base: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var gap := _palette.shade(_palette.shade(base))
	image.fill(gap)
	var highlight := _palette.highlight(base)
	# One rough boulder per lattice cell, jittered off-grid so the stack
	# never reads as a tiled pattern. Deterministic from the cell index --
	# no RNG, matching this file's other generators.
	for cell_y in range(-1, SIZE / _RUBBLE_CELL + 1):
		for cell_x in range(-1, SIZE / _RUBBLE_CELL + 1):
			var h := absi(hash("dam_%d_%d" % [cell_x, cell_y]))
			var jitter_x := (h % 5) - 2
			var jitter_y := ((h / 5) % 5) - 2
			var radius := 2 + (h / 25) % 2
			var centre_x := cell_x * _RUBBLE_CELL + _RUBBLE_CELL / 2 + jitter_x
			var centre_y := cell_y * _RUBBLE_CELL + _RUBBLE_CELL / 2 + jitter_y
			for y in range(centre_y - radius, centre_y + radius + 1):
				for x in range(centre_x - radius, centre_x + radius + 1):
					if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
						continue
					var dx := x - centre_x
					var dy := y - centre_y
					if dx * dx + dy * dy > radius * radius:
						continue
					# Lit from the top-left, the same convention every other
					# generator in this project uses.
					var lit := dx + dy <= -radius
					image.set_pixel(x, y, highlight if lit else base)
	return image


## One big river boulder (docs/concept/rivers.md) sitting in the dark water
## of its own cell -- a single rounded mass lit from the top-left, NOT the
## dam's heap of many small rubble stones it used to share pixels with
## (test_every_piece_is_visually_distinct_from_every_other was red on that
## pair).
func _boulder_image(base: Color) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(_palette.shade(_palette.shade(base)))
	var highlight := _palette.highlight(base)
	var shadow := _palette.shade(base)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.52)
	var radius := SIZE * 0.36
	for y in SIZE:
		for x in SIZE:
			var dx := float(x) - centre.x
			var dy := float(y) - centre.y
			if dx * dx + dy * dy * 1.3 > radius * radius:
				continue
			var lit := dx + dy <= -radius * 0.45
			var shaded := dx + dy >= radius * 0.55
			image.set_pixel(x, y, highlight if lit else (shadow if shaded else base))
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


## -- Furniture and stairs (docs/concept/housing.md "Interior furniture") --
##
## Reported directly, after NPC houses were furnished: "they are still not
## furnished." They were: every furniture id -- and wood_stairs -- fell
## through generate_image's category match to the plain wood-floor tile, so
## a bed was painted as a patch of floor over the floor (test_every_piece_
## is_visually_distinct_from_every_other was red on exactly that), and the
## stairs a player has to FIND to reach a second storey were invisible.
##
## Each piece is an OBJECT standing on the room's own wood floor -- the
## floor tile is the background and shows around it (pinned by
## test_furniture_sits_on_the_room_floor) -- with a silhouette and a colour
## a player tells apart at a glance: a table's pale top on dark legs, a
## chair's slatted backrest, a bed's white pillow and red blanket in a
## wooden frame, a rug's woven border and centre diamond, a bookshelf's
## coloured spines, a couch's cushions between two arms, a photo frame's
## gilt edge around a little landscape. Deterministic, no RNG, like every
## other generator in this file; sizes are fractions of SIZE so the art
## survives an ART_TILE_SIZE change.
const _MATTRESS := Color(0.92, 0.88, 0.78)
const _PILLOW := Color(0.98, 0.97, 0.94)
const _BLANKET := Color(0.62, 0.20, 0.18)
const _RUG := Color(0.55, 0.18, 0.20)
const _RUG_PATTERN := Color(0.90, 0.80, 0.60)
const _COUCH := Color(0.22, 0.42, 0.42)
const _GILT := Color(0.85, 0.70, 0.30)
const _PICTURE_SKY := Color(0.55, 0.75, 0.90)
const _PICTURE_HILLS := Color(0.35, 0.55, 0.25)
const _PICTURE_SUN := Color(0.98, 0.92, 0.55)
const _BOOK_SPINES: Array[Color] = [
	Color(0.60, 0.20, 0.20), Color(0.20, 0.45, 0.30), Color(0.25, 0.30, 0.60),
	Color(0.80, 0.70, 0.30), Color(0.50, 0.30, 0.50),
]


func _furniture_image(piece_id: String, base: Color) -> Image:
	var image := _floor_image(_WOOD_BASE, false)
	match piece_id:
		"wood_chair":
			_draw_chair(image, base)
		"wood_bed":
			_draw_bed(image, base)
		"wood_rug":
			_draw_rug(image)
		"wood_bookshelf":
			_draw_bookshelf(image, base)
		"couch":
			_draw_couch(image)
		"photo_frame":
			_draw_photo_frame(image)
		_:
			_draw_table(image, base)  # wood_table, and the fail-safe for a future piece with no art yet
	return image


## A whole flight of stairs down the cell: a run of treads (paler wood,
## each a step darker than the one above, so the eye reads DOWN) separated
## by dark risers, between two dark stringers, on the room's own floor.
## The same cell carries the stairs on both storeys (see docs/concept/
## housing.md), so this one tile reads as "stairs" from either.
const _STAIR_STEPS := 5


func _stairs_image(base: Color) -> Image:
	var image := _floor_image(_WOOD_BASE, false)
	var tread := _palette.highlight(base)
	var riser := _palette.shade(_palette.shade(base))
	_fill_rect(image, _px(0.10), _px(0.04), _px(0.16), _px(0.96), riser)
	_fill_rect(image, _px(0.84), _px(0.04), _px(0.90), _px(0.96), riser)
	var top := _px(0.06)
	var bottom := _px(0.94)
	var step_height := float(bottom - top) / float(_STAIR_STEPS)
	for i in _STAIR_STEPS:
		var y0 := top + int(round(step_height * i))
		var y1 := top + int(round(step_height * (i + 1)))
		var riser_from := y0 + int(round((y1 - y0) * 0.65))
		_fill_rect(image, _px(0.16), y0, _px(0.84), riser_from, _scaled(tread, 1.0 - 0.07 * i))
		_fill_rect(image, _px(0.16), riser_from, _px(0.84), y1, riser)
	_outline_box(image, _px(0.10), _px(0.04), _px(0.90), _px(0.96))
	return image


func _draw_table(image: Image, base: Color) -> void:
	var top := _palette.highlight(base)
	var legs := _palette.shade(_palette.shade(base))
	_fill_rect(image, _px(0.17), _px(0.62), _px(0.24), _px(0.80), legs)
	_fill_rect(image, _px(0.76), _px(0.62), _px(0.83), _px(0.80), legs)
	_fill_rect(image, _px(0.15), _px(0.25), _px(0.85), _px(0.62), top)
	# Plank grain across the top, the way a tabletop is boarded.
	var grain := _palette.shade(top)
	for y in range(_px(0.25) + 3, _px(0.62), 4):
		for x in range(_px(0.15) + 1, _px(0.85) - 1):
			image.set_pixel(x, y, grain)
	_outline_box(image, _px(0.15), _px(0.25), _px(0.85), _px(0.62))


func _draw_chair(image: Image, base: Color) -> void:
	var seat := _palette.highlight(base)
	var back := _palette.shade(base)
	var legs := _palette.shade(_palette.shade(base))
	_fill_rect(image, _px(0.28), _px(0.70), _px(0.35), _px(0.84), legs)
	_fill_rect(image, _px(0.65), _px(0.70), _px(0.72), _px(0.84), legs)
	_fill_rect(image, _px(0.25), _px(0.16), _px(0.75), _px(0.34), back)
	# Two slat gaps in the backrest so it reads as a chair back, not a box.
	for x in [_px(0.41), _px(0.58)]:
		for y in range(_px(0.19), _px(0.32)):
			image.set_pixel(x, y, seat)
	_fill_rect(image, _px(0.25), _px(0.36), _px(0.75), _px(0.70), seat)
	_outline_box(image, _px(0.25), _px(0.16), _px(0.75), _px(0.70))


func _draw_bed(image: Image, base: Color) -> void:
	var frame := _palette.shade(base)
	_fill_rect(image, _px(0.12), _px(0.08), _px(0.88), _px(0.92), frame)
	_fill_rect(image, _px(0.18), _px(0.13), _px(0.82), _px(0.88), _MATTRESS)
	_fill_rect(image, _px(0.24), _px(0.16), _px(0.76), _px(0.32), _PILLOW)
	_fill_rect(image, _px(0.18), _px(0.40), _px(0.82), _px(0.88), _BLANKET)
	# The turned-back fold of the blanket, one pale line across it.
	for x in range(_px(0.18), _px(0.82)):
		image.set_pixel(x, _px(0.46), _scaled(_BLANKET, 1.3))
	_outline_box(image, _px(0.12), _px(0.08), _px(0.88), _px(0.92))


func _draw_rug(image: Image) -> void:
	var x0 := _px(0.08)
	var y0 := _px(0.18)
	var x1 := _px(0.92)
	var y1 := _px(0.82)
	_fill_rect(image, x0, y0, x1, y1, _RUG)
	# A woven border: a pale band one step in from the edge.
	for x in range(x0 + 3, x1 - 3):
		image.set_pixel(x, y0 + 3, _RUG_PATTERN)
		image.set_pixel(x, y1 - 4, _RUG_PATTERN)
	for y in range(y0 + 3, y1 - 3):
		image.set_pixel(x0 + 3, y, _RUG_PATTERN)
		image.set_pixel(x1 - 4, y, _RUG_PATTERN)
	# A centre diamond, the classic medallion.
	var cx := (x0 + x1) / 2
	var cy := (y0 + y1) / 2
	var radius := _px(0.14)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var d := absi(x - cx) + absi(y - cy)
			if d <= radius and d > radius - 3:
				image.set_pixel(x, y, _RUG_PATTERN)
	# Fabric has no hard outline; a darker selvedge instead.
	_outline_box(image, x0, y0, x1, y1, _palette.shade(_RUG))


func _draw_bookshelf(image: Image, base: Color) -> void:
	var frame := _palette.shade(base)
	var back := _palette.shade(frame)
	_fill_rect(image, _px(0.15), _px(0.06), _px(0.85), _px(0.94), frame)
	_fill_rect(image, _px(0.19), _px(0.10), _px(0.81), _px(0.90), back)
	var rows := [[_px(0.12), _px(0.48)], [_px(0.52), _px(0.88)]]
	var spine := 0
	for row in rows:
		var row_top: int = row[0]
		var row_bottom: int = row[1]
		var x := _px(0.21)
		while x + 2 <= _px(0.79):
			var colour: Color = _BOOK_SPINES[spine % _BOOK_SPINES.size()]
			# Books of slightly different heights, deterministic per spine.
			var height_fraction := 0.72 + 0.28 * float((spine * 7) % 5) / 4.0
			var top := row_bottom - int(round((row_bottom - row_top) * height_fraction))
			_fill_rect(image, x, top, x + 2, row_bottom, colour)
			spine += 1
			x += 3
		# The shelf plank under each row.
		for sx in range(_px(0.19), _px(0.81)):
			image.set_pixel(sx, row_bottom, base)
	_outline_box(image, _px(0.15), _px(0.06), _px(0.85), _px(0.94))


func _draw_couch(image: Image) -> void:
	var arm := _palette.shade(_COUCH)
	_fill_rect(image, _px(0.06), _px(0.24), _px(0.16), _px(0.80), arm)
	_fill_rect(image, _px(0.84), _px(0.24), _px(0.94), _px(0.80), arm)
	_fill_rect(image, _px(0.16), _px(0.20), _px(0.84), _px(0.36), _scaled(_COUCH, 0.85))
	_fill_rect(image, _px(0.16), _px(0.36), _px(0.84), _px(0.80), _COUCH)
	# Two seat cushions: a seam between them and a lit front edge.
	for y in range(_px(0.36), _px(0.80)):
		image.set_pixel(_px(0.50), y, arm)
	for x in range(_px(0.16), _px(0.84)):
		image.set_pixel(x, _px(0.37), _palette.highlight(_COUCH))
	_outline_box(image, _px(0.06), _px(0.20), _px(0.94), _px(0.80))


func _draw_photo_frame(image: Image) -> void:
	_fill_rect(image, _px(0.22), _px(0.22), _px(0.78), _px(0.78), _GILT)
	_fill_rect(image, _px(0.30), _px(0.30), _px(0.70), _px(0.52), _PICTURE_SKY)
	_fill_rect(image, _px(0.30), _px(0.52), _px(0.70), _px(0.70), _PICTURE_HILLS)
	_fill_rect(image, _px(0.58), _px(0.36), _px(0.64), _px(0.42), _PICTURE_SUN)
	_outline_box(image, _px(0.22), _px(0.22), _px(0.78), _px(0.78))


## A pixel coordinate at fraction `f` of the tile, so every drawing above is
## written once for any ART_TILE_SIZE.
static func _px(f: float) -> int:
	return int(round(f * SIZE))


## Fills [x0, x1) x [y0, y1), clamped to the tile.
static func _fill_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		for x in range(maxi(x0, 0), mini(x1, SIZE)):
			image.set_pixel(x, y, color)


## A one-pixel outline just inside [x0, x1) x [y0, y1) -- the same outline
## colour _outline_rect uses for a door leaf or a window pane, unless a
## caller wants its own (a rug's selvedge).
func _outline_box(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color = Color(0, 0, 0, 0)) -> void:
	var outline := color if color.a > 0.0 else _palette.outline_color()
	for x in range(maxi(x0, 0), mini(x1, SIZE)):
		image.set_pixel(x, y0, outline)
		image.set_pixel(x, y1 - 1, outline)
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		image.set_pixel(x0, y, outline)
		image.set_pixel(x1 - 1, y, outline)
