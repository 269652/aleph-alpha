extends GutTest

const BuildingBlueprint = preload("res://src/gameplay/building_blueprint.gd")

var blueprint: BuildingBlueprint


func before_each():
	blueprint = BuildingBlueprint.new()


func test_footprint_tiles_offsets_known_blueprint_at_non_zero_anchor():
	var tiles: Array = blueprint.footprint_tiles("small_house", Vector2i(5, 3))
	assert_eq(tiles.size(), 4)
	assert_true(tiles.has(Vector2i(5, 3)))
	assert_true(tiles.has(Vector2i(6, 3)))
	assert_true(tiles.has(Vector2i(5, 4)))
	assert_true(tiles.has(Vector2i(6, 4)))


func test_footprint_tiles_empty_for_unknown_blueprint():
	var tiles: Array = blueprint.footprint_tiles("does_not_exist", Vector2i(0, 0))
	assert_eq(tiles.size(), 0)


func test_footprint_tiles_at_zero_anchor_matches_raw_offsets():
	var tiles: Array = blueprint.footprint_tiles("wall_segment", Vector2i.ZERO)
	assert_eq(tiles, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])


func test_can_place_true_when_no_overlap_with_occupied_tiles():
	var occupied: Array = [Vector2i(50, 50), Vector2i(-2, -2)]
	assert_true(blueprint.can_place("small_house", Vector2i(0, 0), occupied))


func test_can_place_false_when_single_tile_collides_among_several_occupied():
	var occupied: Array = [Vector2i(100, 100), Vector2i(1, 0), Vector2i(-5, -5)]
	assert_false(blueprint.can_place("small_house", Vector2i(0, 0), occupied))


func test_can_place_false_for_unknown_blueprint_id():
	assert_false(blueprint.can_place("does_not_exist", Vector2i(0, 0), []))


func test_can_place_true_against_completely_empty_occupied_tiles():
	assert_true(blueprint.can_place("small_house", Vector2i(10, 10), []))


func test_blueprint_ids_lists_every_defined_blueprint():
	var ids: Array = blueprint.blueprint_ids()
	assert_true(ids.has("small_house"))
	assert_true(ids.has("wall_segment"))
	assert_gte(ids.size(), 3)


func test_two_blueprints_have_genuinely_different_shapes():
	var ids: Array = blueprint.blueprint_ids()
	var shapes: Dictionary = {}
	for id in ids:
		var tiles: Array = blueprint.footprint_tiles(id, Vector2i.ZERO)
		shapes[tiles.size()] = true
	assert_gt(shapes.size(), 1)


func test_can_place_false_when_full_overlap_with_occupied_tiles():
	var occupied: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	assert_false(blueprint.can_place("small_house", Vector2i.ZERO, occupied))


func test_footprint_tiles_for_l_shape_blueprint_has_distinct_tile_count():
	var tiles: Array = blueprint.footprint_tiles("l_shape_workshop", Vector2i.ZERO)
	assert_gt(tiles.size(), 0)
	assert_ne(tiles.size(), blueprint.footprint_tiles("wall_segment", Vector2i.ZERO).size())
