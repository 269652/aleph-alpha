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


# -- furniture PNGs: the asset contract (docs/concept/building.md) ---------
#
# One square image per furniture piece id at <furniture_dir>/<piece_id>.png
# (top-down, the object centred, background transparent or black/magenta
# -- keyed by the same pass the wall sheets use), composited over the wood
# floor and resized to ART_TILE_SIZE so the tile stays opaque. Until a file
# exists, has_piece_art answers false and the procedural placeholder draws,
# exactly the has_X()-gated seam every illustrated-art class here uses.

const _FURNITURE_FIXTURE_DIR := "user://test_furniture_art_fixture"


func _write_fixture_png(piece_id: String) -> void:
	DirAccess.make_dir_recursive_absolute(_FURNITURE_FIXTURE_DIR)
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))  # the sheets' own near-black background
	for y in range(16, 48):
		for x in range(16, 48):
			image.set_pixel(x, y, Color(0.8, 0.2, 0.2, 1))  # a red object in the middle
	image.save_png("%s/%s.png" % [_FURNITURE_FIXTURE_DIR, piece_id])


func _remove_fixture_png(piece_id: String) -> void:
	DirAccess.remove_absolute("%s/%s.png" % [_FURNITURE_FIXTURE_DIR, piece_id])
	IllustratedBuildingPieceSprite.forget_cached("hearth")


func test_a_furniture_piece_with_no_png_yet_falls_back_to_the_procedural_placeholder():
	sprite.furniture_dir = _FURNITURE_FIXTURE_DIR
	_remove_fixture_png("hearth")
	assert_false(sprite.has_piece_art("hearth"))
	assert_null(sprite.piece_image("hearth"))


func test_a_furniture_png_dropped_in_lights_up_as_an_opaque_floor_composited_tile():
	sprite.furniture_dir = _FURNITURE_FIXTURE_DIR
	_write_fixture_png("hearth")
	IllustratedBuildingPieceSprite.forget_cached("hearth")

	assert_true(sprite.has_piece_art("hearth"))
	var image := sprite.piece_image("hearth")
	assert_not_null(image)
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE)
	# The keyed-away background is FILLED by the floor, never left as a hole
	# in the atlas: every pixel opaque.
	for y in image.get_height():
		for x in image.get_width():
			assert_almost_eq(image.get_pixel(x, y).a, 1.0, 0.001, "pixel (%d,%d) must be opaque" % [x, y])
	# ...and the object itself survives keying: the centre is red, not floor.
	var centre := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert_gt(centre.r, 0.5)
	assert_lt(centre.g, 0.4)
	_remove_fixture_png("hearth")


## A non-furniture piece never picks up a stray PNG from the furniture
## directory: the contract is per furniture id only.
func test_the_furniture_directory_is_only_consulted_for_furniture_pieces():
	sprite.furniture_dir = _FURNITURE_FIXTURE_DIR
	_write_fixture_png("stone_floor")
	IllustratedBuildingPieceSprite.forget_cached("stone_floor")
	assert_false(sprite.has_piece_art("stone_floor"))
	DirAccess.remove_absolute("%s/stone_floor.png" % _FURNITURE_FIXTURE_DIR)
