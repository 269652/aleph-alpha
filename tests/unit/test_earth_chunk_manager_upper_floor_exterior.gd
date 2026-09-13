extends GutTest

## How a two-story house reads from above (docs/concept/building.md's "How
## a house reads from above", point 5; docs/concept/housing.md's "Two-story
## houses"). Reported directly after the two-story batch went live: "there
## are still no 2 story houses and the houses are also still not furnished
## ... also now most houses don't even have a door." Root cause, confirmed by
## reading the layer stack: the upper storey shares the ground floor's exact
## footprint and was painted in place, on a layer above everything, with the
## same wall/window art -- so from a bird's-eye view a two-story house looked
## exactly like a one-story house, and the upper storey's own front wall/
## window sat squarely over the ground floor's door.
##
## The contract these tests pin, per house, driven by where the player is:
##
##   EXTERIOR (not inside this house)   -> only the upper storey's FACADE band
##       is drawn, one row UP (over the roof's own front row), so the house
##       reads as roof-above-facade-above-facade and the ground door stays
##       legible. Nothing else of the upper storey is drawn from outside.
##   GROUND INTERIOR (inside, floor 0)  -> nothing of the upper storey is
##       drawn at all; the ground room is what you see.
##   UPPER INTERIOR (inside, floor 1)   -> the whole upper storey, and its
##       furniture, is drawn in place.
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note).

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
const BuildingPiece = preload("res://src/gameplay/building_piece.gd")
const ProceduralBuildingPieceSprite = preload("res://src/rendering/procedural_building_piece_sprite.gd")

const SHAPE := "tower_keep"  # 5x5, the smallest real two-story catalog shape
const SEED := 7

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var upper_layer: TileMapLayer
var upper_furniture_layer: TileMapLayer
var roof_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _blueprint := HouseBlueprint.new()
var _chunk_coord := Vector2i(0, 0)
var _origin := Vector2i(4, 4)
var _far_away := Vector2i(28, 28)  # still inside chunk (0, 0), nowhere near a house


func before_each():
	tile_map_layer = TileMapLayer.new()
	upper_layer = TileMapLayer.new()
	upper_furniture_layer = TileMapLayer.new()
	roof_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(upper_layer)
	add_child(upper_furniture_layer)
	add_child(roof_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager.set_roof_layer(roof_layer)
	manager.set_upper_floor_layer(upper_layer)
	manager.set_upper_floor_furniture_layer(upper_furniture_layer)
	manager._load_chunk(_chunk_coord)


func after_each():
	tile_map_layer.free()
	upper_layer.free()
	upper_furniture_layer.free()
	roof_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Stamps one real two-story catalog house at `origin` through the SAME
## public entry points the village generator and the player's own blueprint
## build use, and returns its footprint-local ground/upper pieces.
func _stamp_two_story_house(origin: Vector2i) -> Dictionary:
	var ground := _blueprint.build(SHAPE, SEED)
	var roofs := _blueprint.build_roofs(SHAPE, SEED)
	var upper := _blueprint.build_upper_floor(SHAPE, SEED)
	manager.stamp_structure_at_global(_chunk_coord, origin, ground, roofs)
	manager.stamp_upper_floor_at_global(_chunk_coord, origin, upper)
	return {"ground": ground, "upper": upper}


func _door_cell(ground: Dictionary) -> Vector2i:
	for cell in ground:
		if BuildingPiece.category_of(ground[cell]) == BuildingPiece.CATEGORY_DOOR:
			return cell
	fail_test("the fixture house has no door")
	return Vector2i.ZERO


func _an_interior_floor_cell(ground: Dictionary) -> Vector2i:
	for cell in ground:
		if BuildingPiece.category_of(ground[cell]) == BuildingPiece.CATEGORY_FLOOR:
			return cell
	fail_test("the fixture house has no floor cell")
	return Vector2i.ZERO


func _atlas_for(piece_id: String) -> Vector2i:
	return manager._terrain_renderer.atlas_coords_for_modification(piece_id)


## The tile the exterior band draws a facade cell with: the facade family's
## UPPER storey (docs/concept/building.md "How a house reads from above",
## point 6), never the plain interior wall tile.
func _upper_facade_atlas_for(piece_id: String) -> Vector2i:
	return manager._terrain_renderer.atlas_coords_for_facade_variant(
		BuildingPiece.material_of(piece_id), BuildingPiece.category_of(piece_id),
		ProceduralBuildingPieceSprite.FACADE_UPPER
	)


func _painted(layer: TileMapLayer, global_cell: Vector2i) -> bool:
	return layer.get_cell_source_id(global_cell) != -1


func _go_outside() -> void:
	manager.set_current_player_floor(0)
	manager._update_upper_floor_visibility(_far_away)


func _go_inside(origin: Vector2i, ground: Dictionary, floor_number: int) -> void:
	manager.set_current_player_floor(floor_number)
	manager._update_upper_floor_visibility(origin + _an_interior_floor_cell(ground))


# -- layer stack contract ----------------------------------------------------

func test_the_upper_floor_layers_sit_above_the_roof_layer():
	assert_eq(roof_layer.z_index, EarthChunkManager.ROOF_LAYER_Z_INDEX)
	assert_eq(upper_layer.z_index, EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX)
	assert_eq(upper_furniture_layer.z_index, EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX)
	assert_gt(
		EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX, EarthChunkManager.ROOF_LAYER_Z_INDEX,
		"the upper facade band has to paint OVER the roof's front row to read as a second storey"
	)
	assert_gt(
		EarthChunkManager.UPPER_FLOOR_OCCUPANT_Z_INDEX, EarthChunkManager.UPPER_FLOOR_LAYER_Z_INDEX,
		"whoever stands upstairs has to draw above the floor they stand on"
	)


# -- exterior view -----------------------------------------------------------

func test_from_outside_the_upper_facade_band_is_drawn_one_row_up():
	var house := _stamp_two_story_house(_origin)
	_go_outside()

	var facade: Dictionary = _blueprint._facade_cells(house.upper)
	assert_false(facade.is_empty(), "precondition: a real shape has a facade")
	for cell in facade:
		var shifted: Vector2i = _origin + cell + Vector2i(0, -1)
		assert_true(_painted(upper_layer, shifted), "facade cell %s should be drawn one row up at %s" % [str(cell), str(shifted)])
		assert_eq(
			upper_layer.get_cell_atlas_coords(shifted), _upper_facade_atlas_for(house.upper[cell]),
			"what is drawn one row up is the FACADE piece itself, as the upper-storey facade variant, not whatever natively sits at that upper cell"
		)
		assert_ne(
			upper_layer.get_cell_atlas_coords(shifted), _atlas_for(house.upper[cell]),
			"...and never the plain interior wall tile the street should not see"
		)


## The actual reported regression: the ground floor's own door must never be
## painted over from outside.
func test_from_outside_the_ground_floors_door_stays_uncovered():
	var house := _stamp_two_story_house(_origin)
	_go_outside()

	var door_global: Vector2i = _origin + _door_cell(house.ground)
	assert_false(_painted(upper_layer, door_global), "the upper storey must not paint over the ground floor's door")
	assert_eq(manager.modification_at_global(door_global.x, door_global.y), house.ground[_door_cell(house.ground)],
		"precondition: the real door is still there on the ground layer")


func test_from_outside_nothing_but_the_facade_band_is_drawn():
	var house := _stamp_two_story_house(_origin)
	_go_outside()

	var facade: Dictionary = _blueprint._facade_cells(house.upper)
	assert_eq(
		upper_layer.get_used_cells().size(), facade.size(),
		"the upper storey's interior/side/back cells are under the roof from outside -- only its facade band shows"
	)
	assert_true(upper_furniture_layer.get_used_cells().is_empty(), "no upper furniture is visible from outside")


# -- interior views ----------------------------------------------------------

func test_standing_inside_on_the_ground_floor_draws_no_upper_storey_at_all():
	var house := _stamp_two_story_house(_origin)
	_go_inside(_origin, house.ground, 0)

	assert_true(
		upper_layer.get_used_cells().is_empty(),
		"downstairs, the ground room is what you see -- no facade band floating one row above the door either"
	)


func test_standing_upstairs_draws_the_whole_upper_storey_in_place():
	var house := _stamp_two_story_house(_origin)
	_go_inside(_origin, house.ground, 1)

	assert_eq(upper_layer.get_used_cells().size(), house.upper.size())
	for cell in house.upper:
		var global_cell: Vector2i = _origin + cell
		assert_true(_painted(upper_layer, global_cell), "upper cell %s should be drawn in place" % str(cell))
		assert_eq(upper_layer.get_cell_atlas_coords(global_cell), _atlas_for(house.upper[cell]))


func test_upper_furniture_is_only_drawn_while_standing_upstairs():
	var house := _stamp_two_story_house(_origin)
	var placed: int = manager.furnish_upper_floor_at_global(_chunk_coord, _origin, house.upper, ["wood_bed"])
	assert_gt(placed, 0, "precondition: the real upper room takes a real bed")

	_go_outside()
	assert_true(upper_furniture_layer.get_used_cells().is_empty(), "not from outside")
	_go_inside(_origin, house.ground, 0)
	assert_true(upper_furniture_layer.get_used_cells().is_empty(), "not from the ground floor")
	_go_inside(_origin, house.ground, 1)
	assert_eq(upper_furniture_layer.get_used_cells().size(), placed, "in place, once actually upstairs")


func test_leaving_the_house_restores_the_exterior_facade_band():
	var house := _stamp_two_story_house(_origin)
	_go_inside(_origin, house.ground, 1)
	_go_outside()

	var facade: Dictionary = _blueprint._facade_cells(house.upper)
	assert_eq(upper_layer.get_used_cells().size(), facade.size())
	for cell in facade:
		assert_true(_painted(upper_layer, _origin + cell + Vector2i(0, -1)))


func test_a_neighbouring_house_keeps_its_exterior_look_while_the_player_is_upstairs_next_door():
	var home := _stamp_two_story_house(_origin)
	var neighbour_origin := _origin + Vector2i(10, 0)
	var neighbour := _stamp_two_story_house(neighbour_origin)
	_go_inside(_origin, home.ground, 1)

	var facade: Dictionary = _blueprint._facade_cells(neighbour.upper)
	for cell in facade:
		assert_true(
			_painted(upper_layer, neighbour_origin + cell + Vector2i(0, -1)),
			"the neighbour's facade band should still be drawn one row up"
		)
	var neighbour_door: Vector2i = neighbour_origin + _door_cell(neighbour.ground)
	assert_false(_painted(upper_layer, neighbour_door), "the neighbour's door should still be uncovered")
	assert_eq(
		upper_layer.get_used_cells().size(), home.upper.size() + facade.size(),
		"exactly: the home storey in place, plus only the neighbour's facade band"
	)
