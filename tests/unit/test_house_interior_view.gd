extends GutTest

## HouseInteriorView (docs/concept/building.md "Entering"): the real scene
## an Enter prompt swaps the player into -- an opaque backdrop, a
## TileMapLayer sharing the terrain tile set, and real StaticBody2D
## collision on every wall AND every "blocking" furniture piece (bed,
## table, bookshelf, couch -- chair/rug/photo_frame stay walkable),
## positioned so the template's own door cell lands exactly on the
## house's real world doorstep -- walking out the door must put the
## player back exactly where they entered.

const HouseInteriorView = preload("res://src/rendering/house_interior_view.gd")
const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")

const TILE_SIZE := 16

var view: HouseInteriorView
var _tile_set: TileSet
var _terrain_renderer := TerrainRenderer.new()


func before_each():
	view = HouseInteriorView.new()
	add_child(view)
	_tile_set = _terrain_renderer.build_tile_set()


func after_each():
	view.free()


func _empty_atlas() -> Vector2i:
	return Vector2i(-1, -1)


func test_build_positions_the_template_door_cell_exactly_on_the_real_doorstep():
	var doorstep := Vector2(3200.0, 1600.0)
	view.build("cottage", "farmer", 5, doorstep, _tile_set, TILE_SIZE, _terrain_renderer)
	var door_world: Vector2 = view.position + Vector2(view.door_cell) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	assert_almost_eq(door_world.x, doorstep.x, 0.01)
	assert_almost_eq(door_world.y, doorstep.y, 0.01)


func test_build_matches_interior_templates_own_furnish_output():
	var expected := InteriorTemplates.furnish("house", "merchant", 9)
	view.build("house", "merchant", 9, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	assert_eq(view.size, expected["size"])
	assert_eq(view.door_cell, expected["door_cell"])


func test_every_grid_cell_is_painted_with_a_real_atlas_tile():
	view.build("cottage", "guard", 2, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	for y in view.size.y:
		for x in view.size.x:
			var atlas := view.tile_map_layer().get_cell_atlas_coords(Vector2i(x, y))
			assert_ne(atlas, _empty_atlas(), "(%d,%d) was never painted" % [x, y])


func test_every_wall_cell_has_real_collision_on_the_interior_layer():
	view.build("cottage", "guard", 2, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("cottage", "guard", 2)
	var cells: Dictionary = expected["cells"]
	var wall_count := 0
	for local in cells:
		if cells[local] != "wall":
			continue
		wall_count += 1
		var body := view.collision_body_at(local)
		assert_not_null(body, str(local))
		assert_eq(body.collision_layer, HouseInteriorView.INTERIOR_COLLISION_LAYER, str(local))
	assert_gt(wall_count, 0, "precondition: this template has real walls")


func test_blocking_furniture_has_collision_non_blocking_furniture_does_not():
	# merchant's own set (couch, wood_bookshelf, photo_frame) has both a
	# blocking piece (couch) and a non-blocking one (photo_frame) -- a
	# real, direct case rather than a synthetic one.
	view.build("manor", "merchant", 3, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("manor", "merchant", 3)
	var cells: Dictionary = expected["cells"]
	var checked_blocking := false
	var checked_open := false
	for local in cells:
		var value: String = cells[local]
		if value == "couch":
			assert_not_null(view.collision_body_at(local), "couch should block")
			checked_blocking = true
		elif value == "photo_frame":
			assert_null(view.collision_body_at(local), "photo_frame should not block")
			checked_open = true
	assert_true(checked_blocking, "precondition: a couch was actually placed")
	assert_true(checked_open, "precondition: a photo_frame was actually placed")


func test_floor_and_door_cells_have_no_collision():
	view.build("cottage", "farmer", 5, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("cottage", "farmer", 5)
	var cells: Dictionary = expected["cells"]
	for local in cells:
		if cells[local] == "floor" or cells[local] == "door":
			assert_null(view.collision_body_at(local), str(local))


func test_exit_world_position_is_the_real_doorstep_passed_in():
	var doorstep := Vector2(800.0, 400.0)
	view.build("house", "nurse", 4, doorstep, _tile_set, TILE_SIZE, _terrain_renderer)
	assert_eq(view.exit_world_position, doorstep)


func test_is_on_exit_true_near_the_door_false_far_from_it():
	var doorstep := Vector2(800.0, 400.0)
	view.build("house", "nurse", 4, doorstep, _tile_set, TILE_SIZE, _terrain_renderer)
	assert_true(view.is_on_exit(doorstep))
	assert_true(view.is_on_exit(doorstep + Vector2(2, 2)))
	assert_false(view.is_on_exit(doorstep + Vector2(500, 500)))


## A backdrop merely as big as the room's own grid (the old assertion here)
## is nowhere near enough: the camera is 4x-zoomed and follows the player
## anywhere in the room, so it frames DisplayScaling's own design-resolution
## span (1280x720 / 4x zoom = 320x180 world px -- see EarthChunkManager's
## FRUITING_DETAIL_RADIUS comment for the same figure) around wherever the
## player stands -- bigger than even the largest room (manor, 176x144px).
## Reported live: standing in a "small_house" interior still showed the
## real outside world (grass, NPCs, the exterior building) filling most of
## the screen around a small patch of floor. The real guarantee is
## geometric: the backdrop must cover the camera's full view from EVERY
## point the player can stand, i.e. every corner of the room (the camera-
## view rectangles swept over the room's interior are bounded by the ones
## swept from its four corners, since both the room and the camera's own
## view are axis-aligned rectangles).
func test_a_backdrop_covers_the_full_camera_view_from_every_corner_of_the_room():
	view.build("manor", "hunter", 6, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	var backdrop := view.backdrop()
	assert_not_null(backdrop)
	var backdrop_rect := Rect2(backdrop.position, backdrop.size)
	var visible := HouseInteriorView.visible_world_size_px(TILE_SIZE)
	var half := visible * 0.5
	var room_size_px := Vector2(view.size) * TILE_SIZE
	var corners := [
		Vector2.ZERO, Vector2(room_size_px.x, 0), Vector2(0, room_size_px.y), room_size_px,
	]
	for corner in corners:
		var camera_view := Rect2(corner - half, visible)
		assert_true(
			backdrop_rect.encloses(camera_view),
			"camera view centered at room corner %s (%s) must be fully inside the backdrop (%s)" % [corner, camera_view, backdrop_rect]
		)


func test_z_index_is_above_every_world_layer():
	view.build("cottage", "fisher", 1, Vector2.ZERO, _tile_set, TILE_SIZE, _terrain_renderer)
	# UPPER_FLOOR_OCCUPANT_Z_INDEX (the highest world-layer z-index today)
	# is 4 -- see EarthChunkManager. Real number pinned there, not
	# re-declared here; this just asserts the real ordering property.
	assert_gt(view.z_index, 4)
