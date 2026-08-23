extends GutTest

## Tile art for BuildingPiece.PIECE_IDS -- see docs/concept/building.md.
## Mirrors test_procedural_structure_sprite.gd's shape: one generator, one
## opaque ART_TILE_SIZE tile per known id, deterministic, real texture (not
## a flat fill), category/material visually distinguishable from each other.

const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var generator: ProceduralBuildingPieceSprite


func before_each():
	generator = ProceduralBuildingPieceSprite.new()


func _pixel_diff_count(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count


func test_generated_image_has_the_expected_size():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE, piece_id)
		assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE, piece_id)


## Every piece tile is fully opaque -- these render as full ground-plane
## tiles like plain earth/campfire/furnace, not a sprite over transparent
## background.
func test_generated_image_is_fully_opaque():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		for y in image.get_height():
			for x in image.get_width():
				assert_eq(image.get_pixel(x, y).a, 1.0, "%s (%d,%d)" % [piece_id, x, y])


func test_generated_image_is_not_a_flat_color_fill():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id)
		var first_pixel := image.get_pixel(0, 0)
		var all_same := true
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y) != first_pixel:
					all_same = false
		assert_false(all_same, "%s tile should use real procedural texture, not a flat fill" % piece_id)


func test_generated_image_is_deterministic():
	for piece_id in BuildingPiece.PIECE_IDS:
		var first: Image = generator.generate_image(piece_id)
		var second: Image = generator.generate_image(piece_id)
		assert_eq(_pixel_diff_count(first, second), 0, piece_id)


## Every piece must be visually distinguishable from every other -- a floor
## must not look like a wall, a door must stand out from the wall it's set
## into, and wood must read differently from stone.
func test_every_piece_is_visually_distinct_from_every_other():
	var images := {}
	for piece_id in BuildingPiece.PIECE_IDS:
		images[piece_id] = generator.generate_image(piece_id)
	for i in BuildingPiece.PIECE_IDS.size():
		for j in range(i + 1, BuildingPiece.PIECE_IDS.size()):
			var a: String = BuildingPiece.PIECE_IDS[i]
			var b: String = BuildingPiece.PIECE_IDS[j]
			assert_gt(
				_pixel_diff_count(images[a], images[b]), TerrainRenderer.ART_TILE_SIZE,
				"%s and %s should look clearly different" % [a, b]
			)


## Wood pieces should read warmer (more saturated toward red/brown) than
## their stone counterpart, mirroring campfire/furnace's warm-vs-cool
## distinction.
func test_wood_and_stone_of_the_same_category_are_distinct_materials():
	for category in [
		BuildingPiece.CATEGORY_FLOOR, BuildingPiece.CATEGORY_WALL,
		BuildingPiece.CATEGORY_DOOR, BuildingPiece.CATEGORY_WINDOW, BuildingPiece.CATEGORY_ROOF,
	]:
		var wood: Image = generator.generate_image("wood_%s" % category)
		var stone: Image = generator.generate_image("stone_%s" % category)
		assert_gt(_pixel_diff_count(wood, stone), TerrainRenderer.ART_TILE_SIZE, category)


func test_generate_texture_returns_an_image_texture_of_matching_size():
	var texture: ImageTexture = generator.generate_texture("wood_wall")
	assert_eq(texture.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(texture.get_height(), TerrainRenderer.ART_TILE_SIZE)


## Fail-safe default -- an unrecognized id still returns a well-formed tile
## instead of crashing.
func test_unknown_piece_id_falls_back_without_crashing():
	var image: Image = generator.generate_image("mystery_piece")
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
	assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE)
