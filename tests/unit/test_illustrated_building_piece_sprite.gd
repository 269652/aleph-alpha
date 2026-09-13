extends GutTest

## Real illustrated wall/door/window/floor art (docs/concept/building.md),
## replacing ProceduralBuildingPieceSprite's generated pattern per piece id
## where a real user-supplied sheet exists -- the same has_X()-gated
## fallback convention IllustratedTerrainSprite already establishes
## (TerrainRenderer checks has_variants before calling frame_for; here it
## checks has_piece_art before calling piece_image). Reported directly: NPC
## buildings "look poor and basic; not like sophisticated architecture".
##
## wood_wall.png/stone_wall.png: a 6-column x 2-row sheet (door, window,
## wall, a second wall variant, two narrow corner-post variants -- the last
## three columns/the second row are real, unused art held in reserve, not
## wired to anything yet). wood_floor.png: a single full-bleed image, no
## grid. Chroma key: magenta divider line ALWAYS keyed (measured thresholds
## reused from IllustratedStructureSprite, not reinvented) plus the sheets'
## own near-black background.

const IllustratedBuildingPieceSprite = preload("res://src/rendering/illustrated_building_piece_sprite.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")

const _KNOWN_PIECES := [
	"wood_wall", "wood_door", "wood_window", "wood_floor",
	"stone_wall", "stone_door", "stone_window",
]
const _NOT_YET_ILLUSTRATED_PIECES := [
	"stone_floor", "timber_wall", "timber_floor", "wood_roof", "stone_roof",
	"stone_dam", "boulder", "wood_bed", "not_a_real_piece", "",
]

var sprite: IllustratedBuildingPieceSprite


func before_each():
	sprite = IllustratedBuildingPieceSprite.new()


func test_knows_every_piece_with_real_art():
	for piece_id in _KNOWN_PIECES:
		assert_true(sprite.has_piece_art(piece_id), "%s should have real illustrated art" % piece_id)


func test_does_not_know_a_piece_with_no_real_art_yet():
	for piece_id in _NOT_YET_ILLUSTRATED_PIECES:
		assert_false(sprite.has_piece_art(piece_id), "%s should still fall back to the procedural generator" % piece_id)


func test_piece_image_is_null_for_a_piece_with_no_real_art():
	assert_null(sprite.piece_image("stone_floor"))
	assert_null(sprite.piece_image("not_a_real_piece"))


func test_piece_image_is_the_real_baked_tile_size_for_every_known_piece():
	for piece_id in _KNOWN_PIECES:
		var image := sprite.piece_image(piece_id)
		assert_not_null(image, piece_id)
		assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE, piece_id)
		assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE, piece_id)
		assert_eq(image.get_format(), Image.FORMAT_RGBA8, piece_id)


## Chroma-keyed: the background must be gone, not just recolored -- the same
## "actually transparent, not still opaque magenta/black" contract every
## other illustrated-art class in this codebase already guarantees.
func test_piece_image_background_is_transparent_not_opaque():
	for piece_id in _KNOWN_PIECES:
		var image := sprite.piece_image(piece_id)
		var transparent := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a <= 0.01:
					transparent += 1
		assert_gt(transparent, 0, "%s should have a real transparent background" % piece_id)


## The real drawn content must survive keying -- a wall/door/window/floor
## piece is mostly opaque, not an all-transparent blank tile.
func test_piece_image_keeps_real_opaque_content():
	for piece_id in _KNOWN_PIECES:
		var image := sprite.piece_image(piece_id)
		var opaque := 0
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a >= 0.99:
					opaque += 1
		assert_gt(opaque, 100, "%s should keep real drawn content after keying" % piece_id)


## Each of door/window/wall for the SAME material must be visually distinct
## from the others -- otherwise two crop columns silently collapsed onto the
## same sheet region.
func test_door_window_and_wall_are_visually_distinct_per_material():
	for material in ["wood", "stone"]:
		var door := sprite.piece_image("%s_door" % material)
		var window := sprite.piece_image("%s_window" % material)
		var wall := sprite.piece_image("%s_wall" % material)
		assert_ne(door.get_data(), window.get_data(), "%s: door vs window" % material)
		assert_ne(door.get_data(), wall.get_data(), "%s: door vs wall" % material)
		assert_ne(window.get_data(), wall.get_data(), "%s: window vs wall" % material)


func test_wood_and_stone_are_visually_distinct_per_category():
	for category in ["wall", "door", "window"]:
		var wood := sprite.piece_image("wood_%s" % category)
		var stone := sprite.piece_image("stone_%s" % category)
		assert_ne(wood.get_data(), stone.get_data(), category)


func test_piece_image_is_deterministic():
	for piece_id in _KNOWN_PIECES:
		assert_eq(
			sprite.piece_image(piece_id).get_data(), sprite.piece_image(piece_id).get_data(), piece_id
		)


# -- thin wall art (docs/concept/building.md "How a house reads from
# above", point 8): "walls are now 1 Tile thick... they should be 1/4 tile
# wide the rest of the 3/4 wall should be made walkable floor" -- the
# sheet's two narrow corner-post columns are a real, purpose-shaped wall
# TRIM strip for exactly this, per the user's own confirmation.

func test_has_thin_wall_art_for_every_material_with_a_wall_sheet():
	assert_true(sprite.has_thin_wall_art("wood"))
	assert_true(sprite.has_thin_wall_art("stone"))
	assert_false(sprite.has_thin_wall_art("timber"))
	assert_false(sprite.has_thin_wall_art("not_a_real_material"))


func test_thin_wall_strip_image_is_a_real_narrow_vertical_strip():
	for material in ["wood", "stone"]:
		var strip := sprite.thin_wall_strip_image(material)
		assert_not_null(strip, material)
		assert_eq(strip.get_height(), TerrainRenderer.ART_TILE_SIZE, material)
		assert_lt(strip.get_width(), TerrainRenderer.ART_TILE_SIZE / 2, "%s: a strip should be well under half the tile wide" % material)
		var opaque := 0
		for y in strip.get_height():
			for x in strip.get_width():
				if strip.get_pixel(x, y).a >= 0.99:
					opaque += 1
		assert_gt(opaque, 20, "%s: the strip should keep real drawn content" % material)


func test_thin_wall_strip_is_null_for_a_material_with_no_wall_sheet():
	assert_null(sprite.thin_wall_strip_image("timber"))


## A single outward side: the tile is mostly the floor base, with the trim
## strip flush against exactly that edge and nowhere else.
func test_thin_wall_variant_flush_against_a_single_outward_edge():
	var floor_base := Image.create(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_base.fill(Color(0.5, 0.5, 0.5, 1.0))
	var west := sprite.thin_wall_variant_image("wood", BuildingPiece.EDGE_WEST, floor_base)
	assert_eq(west.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(west.get_height(), TerrainRenderer.ART_TILE_SIZE)
	# The far (east) edge is untouched floor base.
	assert_eq(west.get_pixel(TerrainRenderer.ART_TILE_SIZE - 1, TerrainRenderer.ART_TILE_SIZE / 2), floor_base.get_pixel(TerrainRenderer.ART_TILE_SIZE - 1, TerrainRenderer.ART_TILE_SIZE / 2))
	# The near (west) edge should differ from plain floor -- the strip is there.
	assert_ne(west.get_pixel(0, TerrainRenderer.ART_TILE_SIZE / 2), floor_base.get_pixel(0, TerrainRenderer.ART_TILE_SIZE / 2))


func test_thin_wall_variant_differs_per_outward_direction():
	var floor_base := Image.create(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_base.fill(Color(0.5, 0.5, 0.5, 1.0))
	var west := sprite.thin_wall_variant_image("wood", BuildingPiece.EDGE_WEST, floor_base)
	var north := sprite.thin_wall_variant_image("wood", BuildingPiece.EDGE_NORTH, floor_base)
	var corner := sprite.thin_wall_variant_image("wood", BuildingPiece.EDGE_NORTH | BuildingPiece.EDGE_WEST, floor_base)
	assert_ne(west.get_data(), north.get_data())
	assert_ne(west.get_data(), corner.get_data())
	assert_ne(north.get_data(), corner.get_data())


## A corner cell (two outward sides at once) carries the strip on BOTH of
## them, not just one -- the actual reported shape ("the rest of the wall
## should be made walkable floor" applies to every outward side a cell
## has, including a building's own corner).
func test_thin_wall_variant_at_a_corner_marks_both_outward_edges():
	var floor_base := Image.create(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_base.fill(Color(0.5, 0.5, 0.5, 1.0))
	var corner := sprite.thin_wall_variant_image("wood", BuildingPiece.EDGE_NORTH | BuildingPiece.EDGE_WEST, floor_base)
	assert_ne(corner.get_pixel(0, TerrainRenderer.ART_TILE_SIZE / 2), floor_base.get_pixel(0, TerrainRenderer.ART_TILE_SIZE / 2), "west edge should carry the strip")
	assert_ne(corner.get_pixel(TerrainRenderer.ART_TILE_SIZE / 2, 0), floor_base.get_pixel(TerrainRenderer.ART_TILE_SIZE / 2, 0), "north edge should carry the strip")
	# The far corner (south-east) stays untouched floor.
	assert_eq(
		corner.get_pixel(TerrainRenderer.ART_TILE_SIZE - 1, TerrainRenderer.ART_TILE_SIZE - 1),
		floor_base.get_pixel(TerrainRenderer.ART_TILE_SIZE - 1, TerrainRenderer.ART_TILE_SIZE - 1)
	)


func test_thin_wall_variant_with_no_outward_side_is_just_the_floor_base():
	var floor_base := Image.create(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_base.fill(Color(0.3, 0.6, 0.2, 1.0))
	var image := sprite.thin_wall_variant_image("wood", 0, floor_base)
	assert_eq(image.get_data(), floor_base.get_data())


func test_thin_wall_variant_is_deterministic():
	var floor_base := Image.create(TerrainRenderer.ART_TILE_SIZE, TerrainRenderer.ART_TILE_SIZE, false, Image.FORMAT_RGBA8)
	floor_base.fill(Color(0.5, 0.5, 0.5, 1.0))
	var a := sprite.thin_wall_variant_image("stone", BuildingPiece.EDGE_SOUTH, floor_base)
	var b := sprite.thin_wall_variant_image("stone", BuildingPiece.EDGE_SOUTH, floor_base)
	assert_eq(a.get_data(), b.get_data())
