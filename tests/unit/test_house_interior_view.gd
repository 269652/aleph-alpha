extends GutTest

## HouseInteriorView (docs/concept/building.md "Entering"): the real scene
## an Enter prompt swaps the player into, built as the content of an
## ISOLATED SubViewport (see World._build_interior_view) -- a TileMapLayer
## sharing the terrain tile set, real StaticBody2D collision on every wall
## AND every "blocking" furniture piece (bed, table, bookshelf, couch --
## chair/rug/photo_frame stay walkable), a real threshold body one cell
## past the door so nothing but the Leave action gets you out, and this
## view's own Camera2D fit to the room's own size. No longer positioned at
## the house's real world doorstep at all -- that's the whole point (see
## the file's own doc comment): the real world never shows through because
## this view isn't drawn among it any more.

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


func test_build_matches_interior_templates_own_furnish_output():
	var expected := InteriorTemplates.furnish("house", "merchant", 9)
	view.build("house", "merchant", 9, _tile_set, TILE_SIZE, _terrain_renderer)
	assert_eq(view.size, expected["size"])
	assert_eq(view.door_cell, expected["door_cell"])


func test_every_grid_cell_is_painted_with_a_real_atlas_tile():
	view.build("cottage", "guard", 2, _tile_set, TILE_SIZE, _terrain_renderer)
	for y in view.size.y:
		for x in view.size.x:
			var atlas := view.tile_map_layer().get_cell_atlas_coords(Vector2i(x, y))
			assert_ne(atlas, _empty_atlas(), "(%d,%d) was never painted" % [x, y])


func test_every_wall_cell_has_real_collision_on_the_interior_layer():
	view.build("cottage", "guard", 2, _tile_set, TILE_SIZE, _terrain_renderer)
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
	view.build("manor", "merchant", 3, _tile_set, TILE_SIZE, _terrain_renderer)
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
	view.build("cottage", "farmer", 5, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("cottage", "farmer", 5)
	var cells: Dictionary = expected["cells"]
	for local in cells:
		if cells[local] == "floor" or cells[local] == "door":
			assert_null(view.collision_body_at(local), str(local))


## Reported live: without a real physical stop, a player could just walk
## through the door and on past it -- the door cell itself is deliberately
## walkable (see test_floor_and_door_cells_have_no_collision above), so it
## alone was never a boundary. This cell is NOT part of InteriorTemplates'
## own grid (every template's grid ends AT the door row), so it can only
## ever come from HouseInteriorView itself.
func test_a_real_threshold_blocks_movement_one_cell_past_the_door():
	view.build("cottage", "farmer", 5, _tile_set, TILE_SIZE, _terrain_renderer)
	var threshold := view.door_cell + Vector2i(0, 1)
	var body := view.collision_body_at(threshold)
	assert_not_null(body, "no collision one cell past the door (%s)" % threshold)
	assert_eq(body.collision_layer, HouseInteriorView.INTERIOR_COLLISION_LAYER)


func test_is_on_exit_true_near_the_door_cell_false_far_from_it():
	view.build("house", "nurse", 4, _tile_set, TILE_SIZE, _terrain_renderer)
	var door_center := (Vector2(view.door_cell) + Vector2(0.5, 0.5)) * TILE_SIZE
	assert_true(view.is_on_exit(door_center))
	assert_true(view.is_on_exit(door_center + Vector2(2, 2)))
	assert_false(view.is_on_exit(door_center + Vector2(500, 500)))


## Merely as big as the room's own grid would leave the walls touching the
## screen edge; the old world-space version of this backdrop had to be
## enormous to out-cover a fixed outdoor camera (see git history) -- that
## reasoning is gone now that this view is isolated in its own SubViewport
## (nothing outdoor to out-cover), so the backdrop should go back to being
## modest. Bounded on BOTH sides so a regression toward either the old
## "too small" bug or the old "huge margin" bug gets caught.
func test_a_backdrop_covers_the_room_with_a_modest_margin():
	view.build("manor", "hunter", 6, _tile_set, TILE_SIZE, _terrain_renderer)
	var backdrop := view.backdrop()
	assert_not_null(backdrop)
	var room_size_px := Vector2(view.size) * TILE_SIZE
	assert_gte(backdrop.size.x, room_size_px.x, "must cover the room")
	assert_gte(backdrop.size.y, room_size_px.y, "must cover the room")
	# A margin bigger than the room itself would be the "huge black
	# margin" regression again -- the backdrop should never need to be
	# more than double the room's own footprint.
	assert_lt(backdrop.size.x, room_size_px.x * 2.0, "backdrop has grown huge again")
	assert_lt(backdrop.size.y, room_size_px.y * 2.0, "backdrop has grown huge again")


## Fit-to-content, the same shape main_menu.gd's own diorama camera uses:
## a room this small should end up meaningfully zoomed in (this camera's
## zoom, unlike the outdoor world's fixed 4x, must actually depend on the
## room's own size), and neither the width nor the height fit should ever
## exceed DisplayScaling's own design resolution -- that would crop part
## of the room out of frame.
func test_camera_is_fit_to_the_rooms_own_size():
	view.build("cottage", "farmer", 5, _tile_set, TILE_SIZE, _terrain_renderer)
	var camera := view.camera()
	assert_not_null(camera)
	var room_size_px := Vector2(view.size) * TILE_SIZE
	var visible := Vector2(DisplayScaling.DESIGN_WIDTH, DisplayScaling.DESIGN_HEIGHT) / camera.zoom
	assert_lte(room_size_px.x, visible.x, "the room's own width must fit in frame")
	assert_lte(room_size_px.y, visible.y, "the room's own height must fit in frame")


# -- templates v2: windows, the new blocking pieces, lights, the resident cell

func test_a_window_is_painted_as_a_real_window_piece_and_blocks_like_a_wall():
	view.build("cottage", "farmer", 5, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("cottage", "farmer", 5)
	var cells: Dictionary = expected["cells"]
	var windows := 0
	for local in cells:
		if cells[local] != "window":
			continue
		windows += 1
		assert_eq(
			view.tile_map_layer().get_cell_atlas_coords(local),
			_terrain_renderer.atlas_coords_for_modification("wood_window"), str(local)
		)
		assert_not_null(view.collision_body_at(local), "a window is part of the wall: %s" % str(local))
	assert_gt(windows, 0, "precondition: this template has windows")


## A smith's anvil, a hearth, a barrel, a chest, a cupboard block; a candle
## does not (you walk past a candle on the floor, not through an anvil).
func test_the_new_workshop_and_storage_pieces_block_but_a_candle_does_not():
	view.build("cottage", "blacksmith", 5, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("cottage", "blacksmith", 5)
	var cells: Dictionary = expected["cells"]
	var checked := {}
	for local in cells:
		var value: String = cells[local]
		match value:
			"anvil", "hearth":
				assert_not_null(view.collision_body_at(local), "%s should block" % value)
				checked[value] = true
			"candle":
				assert_null(view.collision_body_at(local), "a candle should not block")
				checked[value] = true
	for value in ["anvil", "hearth", "candle"]:
		assert_true(checked.has(value), "precondition: a %s was actually placed" % value)


func test_every_light_cell_gets_a_real_glow_quad_centred_on_it():
	view.build("house", "nurse", 4, _tile_set, TILE_SIZE, _terrain_renderer)
	var expected := InteriorTemplates.furnish("house", "nurse", 4)
	var light_cells: Array = expected["light_cells"]
	assert_gt(light_cells.size(), 0, "precondition")
	var glows: Array = view.light_glows()
	assert_eq(glows.size(), light_cells.size(), "one glow per candle")
	for i in glows.size():
		var glow: MeshInstance2D = glows[i]
		var centre: Vector2 = (Vector2(light_cells[i]) + Vector2(0.5, 0.5)) * TILE_SIZE
		assert_almost_eq(glow.position.x, centre.x, 0.01)
		assert_almost_eq(glow.position.y, centre.y, 0.01)
		assert_not_null(glow.material, "the glow uses the real additive TorchGlow material")


func test_the_resident_cell_is_a_real_open_floor_cell_of_the_room():
	view.build("manor", "hunter", 6, _tile_set, TILE_SIZE, _terrain_renderer)
	var cell: Vector2i = view.resident_cell
	assert_eq(cell, InteriorTemplates.furnish("manor", "hunter", 6)["resident_cell"])
	assert_null(view.collision_body_at(cell), "the resident stands on open floor")
	assert_true(cell.x > 0 and cell.y > 0 and cell.x < view.size.x - 1 and cell.y < view.size.y - 1)


## A bigger room (manor) needs LESS magnification than a smaller one
## (cottage) to still fit the same design resolution -- the concrete,
## observable difference the fit-to-content formula exists to produce, as
## opposed to every room getting the same fixed zoom regardless of size.
func test_a_bigger_room_gets_a_smaller_zoom_than_a_smaller_room():
	var cottage_view := HouseInteriorView.new()
	add_child(cottage_view)
	cottage_view.build("cottage", "farmer", 5, _tile_set, TILE_SIZE, _terrain_renderer)

	view.build("manor", "hunter", 6, _tile_set, TILE_SIZE, _terrain_renderer)

	assert_lt(view.camera().zoom.x, cottage_view.camera().zoom.x)
	cottage_view.free()
