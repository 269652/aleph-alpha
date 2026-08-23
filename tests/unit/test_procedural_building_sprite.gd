extends GutTest

## ProceduralBuildingSprite: tile art for the structural pieces a house is
## built from (see docs/concept/building.md#pieces). Until this existed,
## BuildingPiece described pieces that nothing could draw.

const ProceduralBuildingSprite = preload("res://src/rendering/procedural_building_sprite.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var generator: ProceduralBuildingSprite


func before_each():
	generator = ProceduralBuildingSprite.new()


func test_every_piece_renders_at_the_terrain_tile_resolution():
	for piece_id in BuildingPiece.PIECE_IDS:
		var image: Image = generator.generate_image(piece_id, 1)
		assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE, piece_id)
		assert_eq(image.get_height(), TerrainRenderer.ART_TILE_SIZE, piece_id)


func test_every_piece_is_deterministic():
	for piece_id in BuildingPiece.PIECE_IDS:
		assert_eq(
			generator.generate_image(piece_id, 7).get_data(),
			generator.generate_image(piece_id, 7).get_data(),
			piece_id
		)


## The categories must be tellable apart at a glance -- a door that looks
## like a wall is unusable.
func test_each_category_looks_different_from_the_others():
	var seen := {}
	for piece_id in ["wood_floor", "wood_wall", "wood_door", "wood_window", "wood_roof"]:
		var data := generator.generate_image(piece_id, 3).get_data()
		assert_false(seen.has(data), "%s should not look like another piece" % piece_id)
		seen[data] = true


## Materials read differently too, or a stone house looks like a wood one.
func test_stone_reads_differently_from_wood():
	assert_ne(
		generator.generate_image("wood_wall", 2).get_data(),
		generator.generate_image("stone_wall", 2).get_data()
	)


## A door needs to read as a way IN -- it carries a visibly lighter opening
## against its frame.
func test_a_door_has_a_visible_opening():
	var image: Image = generator.generate_image("wood_door", 1)
	var art := TerrainRenderer.ART_TILE_SIZE
	var middle := image.get_pixel(art / 2, art / 2)
	var edge := image.get_pixel(1, art / 2)
	assert_ne(middle, edge, "a door's opening should differ from its frame")


func test_pieces_are_fully_opaque_so_they_hide_the_ground():
	for piece_id in ["wood_floor", "wood_wall", "stone_wall"]:
		var image: Image = generator.generate_image(piece_id, 1)
		assert_eq(image.get_pixel(4, 4).a, 1.0, piece_id)


func test_an_unknown_piece_still_returns_a_tile_rather_than_crashing():
	var image: Image = generator.generate_image("not_a_piece", 1)
	assert_eq(image.get_width(), TerrainRenderer.ART_TILE_SIZE)
