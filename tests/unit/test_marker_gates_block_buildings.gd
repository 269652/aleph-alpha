extends GutTest

## Every walking marker must be stopped by a WHOLE-BUILDING ENTITY, not
## only by a legacy BuildingPiece wall.
##
## Reported twice. First *"Creatures and NPCs also walk through houses"*,
## which was answered by giving every marker a gate that asks
## `piece_blocks_movement_at_global` -- the same question the wall's own
## collision body is spawned from. Then, unchanged: **"NPCs still walk
## through houses and ignore the hitbox"**.
##
## The gate was right and the question was wrong. A village house is a
## whole-building ENTITY now (docs/concept/building.md, "Buildings are
## entities; interiors are scenes"): its cells carry the building id and
## `BuildingCatalog.FOOTPRINT_TILE_ID`, it has NO `BuildingPiece` walls at
## all, and `BuildingCatalog.occupies` says so in as many words -- "a
## legacy BuildingPiece or a single-tile placeable is its own thing and
## answers false here". So the piece question answers *false* on every cell
## of a cottage, while the player is stopped by a `StaticBody2D` over its
## whole footprint. The player and the markers were asking about two
## different kinds of building.
##
## These tests are deliberately built on a REAL building in a REAL chunk
## rather than a stub world: a stub can be made to answer anything, and
## what was wrong here was which question the real world was asked.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const BuildingCatalog = preload("res://src/gameplay/building_catalog.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const AgentPassability = preload("res://src/gameplay/agent_passability.gd")
const WalkGate = preload("res://src/gameplay/walk_gate.gd")

const _BUILDING := "house_medium"

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord: Vector2i
var _origin: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	var berlin := Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	_chunk_coord = Vector2i(
		floori(float(berlin.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(berlin.y) / EarthChunkManager.CHUNK_SIZE)
	)
	_scrub()
	manager._load_chunk(_chunk_coord)
	_origin = _a_clear_footprint_origin(BuildingCatalog.footprint_of(_BUILDING))
	assert_true(
		manager.place_building(_chunk_coord, _origin, _BUILDING, Vector2i(0, 1), 7, ""),
		"the whole test rests on a real house really standing here"
	)


func after_each():
	_scrub()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _scrub() -> void:
	for path in [
		manager._modifications_path(_chunk_coord), manager._buildings_path(_chunk_coord),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _a_clear_footprint_origin(footprint: Vector2i):
	for y in range(2, EarthChunkManager.CHUNK_SIZE - footprint.y - 3):
		for x in range(2, EarthChunkManager.CHUNK_SIZE - footprint.x - 3):
			var origin := Vector2i(x, y)
			var ok := true
			for cell in BuildingCatalog.footprint_cells(_BUILDING, origin) + [
				origin + BuildingCatalog.doorstep_of(_BUILDING)
			]:
				var g: Vector2i = _chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
				if (
					not manager.is_buildable_terrain_at(g.x, g.y)
					or manager.modification_at_global(g.x, g.y) != ""
				):
					ok = false
					break
			if ok:
				return origin
	fail_test("no clear footprint origin found in this chunk")
	return Vector2i.ZERO


func _global(local: Vector2i) -> Vector2i:
	return _chunk_coord * EarthChunkManager.CHUNK_SIZE + local


## A cell well inside the house, not on its rim -- so nothing here turns on
## rounding at a footprint edge.
func _inside_cell() -> Vector2i:
	var footprint := BuildingCatalog.footprint_of(_BUILDING)
	return _global(_origin + Vector2i(footprint.x / 2, footprint.y / 2))


func _centre_px(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * float(TerrainRenderer.TILE_SIZE)


func _building_shape() -> CollisionShape2D:
	for node in entities_parent.get_children():
		for child in node.get_children():
			if child is StaticBody2D and child.name == "BuildingCollision":
				for grandchild in child.get_children():
					if grandchild is CollisionShape2D and grandchild.shape is RectangleShape2D:
						return grandchild
	return null


# -- the diagnosis, stated as a test so it cannot quietly stop being true ---

## What stops the PLAYER: one StaticBody2D over the whole footprint. This is
## the reference every gate below has to match.
func test_the_player_is_stopped_by_a_body_over_the_whole_house():
	var bodies := 0
	for node in entities_parent.get_children():
		for child in node.get_children():
			if child is StaticBody2D and child.name == "BuildingCollision":
				bodies += 1
	assert_gt(bodies, 0, "a house the player walks into has a real body")


## ...and that body covers EXACTLY the footprint cells the world reports a
## building on -- which is what makes "ask has_building_at_global" the right
## answer rather than an approximation of one. If these two ever drift, the
## player and the markers are back to being stopped in different places.
func test_the_body_covers_exactly_the_cells_the_world_calls_a_building():
	var shape := _building_shape()
	assert_not_null(shape)
	var footprint := BuildingCatalog.footprint_of(_BUILDING)
	var tile := float(TerrainRenderer.TILE_SIZE)
	var world_rect := Rect2(
		shape.global_position - shape.shape.size * 0.5, shape.shape.size
	)
	assert_almost_eq(world_rect.position.x, float(_global(_origin).x) * tile, 0.001)
	assert_almost_eq(world_rect.position.y, float(_global(_origin).y) * tile, 0.001)
	assert_almost_eq(world_rect.size.x, float(footprint.x) * tile, 0.001)
	assert_almost_eq(world_rect.size.y, float(footprint.y) * tile, 0.001)
	for cell in BuildingCatalog.footprint_cells(_BUILDING, _origin):
		var g := _global(cell)
		assert_true(
			world_rect.has_point(_centre_px(g)),
			"%s is called a building and must be under the body too" % g
		)
		assert_true(manager.has_building_at_global(g.x, g.y), str(g))


## ...and the question every marker gate was asking instead answers FALSE on
## every cell of it, because a whole-building entity has no pieces. Not a
## bug in itself -- it is the correct answer to the wrong question, and the
## reason the two disagreed.
func test_the_piece_question_is_silent_about_a_whole_building():
	var inside := _inside_cell()
	assert_false(
		manager.piece_blocks_movement_at_global(inside.x, inside.y),
		"a cottage is not made of BuildingPiece walls"
	)
	assert_true(
		manager.has_building_at_global(inside.x, inside.y),
		"...but the world can say a building stands there, and was never asked"
	)


# -- so every gate has to ask both ------------------------------------------

## What a route plans around.
func test_a_route_plans_around_a_whole_building():
	var blocked: Callable = AgentPassability.blocked_predicate_for(manager)
	assert_true(blocked.is_valid(), "the real world answers these questions")
	assert_true(blocked.call(_inside_cell()), "a villager must not route through a house")


## What the six person-shaped markers ask before each step (builder,
## farmer, lumberjack, logistics carrier and their kin).
func test_the_shared_walk_gate_refuses_a_step_into_a_house():
	var inside := _inside_cell()
	var outside := _centre_px(inside + Vector2i(0, -BuildingCatalog.footprint_of(_BUILDING).y - 2))
	assert_true(
		WalkGate.blocks(manager, outside, _centre_px(inside), float(TerrainRenderer.TILE_SIZE)),
		"a marker must not be able to stand inside a house"
	)


## ...and it still SLIDES rather than stopping dead, which is the whole
## reason a villager can reach their own front door by walking at the house.
## Stated in CELLS off the house's own north-west corner rather than in
## offsets from somewhere inside it -- the first draft of this aimed a
## "diagonal into the house" at a cell one row BELOW the footprint, where
## there was nothing to be stopped by and nothing to slide along.
func test_a_marker_brushing_a_house_keeps_moving_along_it():
	var corner := _global(_origin)  # the footprint's north-west cell
	var escape := corner + Vector2i(-1, 1)  # due west of the house, free
	# Asserted rather than skipped over: a silent skip here would hide the
	# only two assertions this test has.
	assert_false(
		AgentPassability.blocked_predicate_for(manager).call(escape),
		"the cell the walker is meant to slide into has to be open ground"
	)
	var from := _centre_px(corner + Vector2i(-1, 0))
	# One cell south-east. The destination is inside the house and so is the
	# cell due east of `from`, so only the southward half can survive.
	var to := from + Vector2.ONE * float(TerrainRenderer.TILE_SIZE)
	var slid: Vector2 = WalkGate.slide(manager, from, to, float(TerrainRenderer.TILE_SIZE))
	assert_almost_eq(slid.y, to.y, 0.001, "the free axis survives")
	assert_almost_eq(slid.x, from.x, 0.001, "the axis into the house does not")


# -- ...and the two kinds of building really are disjoint -------------------
#
# The whole fix rests on this: asking BOTH questions with `or` is only safe
# because a legacy BuildingPiece structure answers `false` to the whole-
# building question, so its walkable DOOR and FLOOR are not swept up by the
# footprint answer. `BuildingCatalog.occupies` says as much in prose; these
# measure it on a real stamped piece.

## Row +3 is below the house and below its doorstep (row +2), and well
## inside the loaded chunk -- reaching north of the origin instead ran off
## the chunk's own edge, where build_at_global is a silent no-op.
func test_a_piece_built_wall_is_not_a_whole_building():
	var cell := _global(_origin + Vector2i(0, 3))
	manager.build_at_global(cell.x, cell.y, "wood_wall")
	assert_true(
		manager.piece_blocks_movement_at_global(cell.x, cell.y), "a wall is solid"
	)
	assert_false(
		manager.has_building_at_global(cell.x, cell.y),
		"...and it is a PIECE, not a whole-building entity"
	)
	assert_true(
		AgentPassability.structure_blocks(manager, cell), "so the shared question stops it"
	)


## The load-bearing half: a DOOR is a walkable piece, and asking the
## whole-building question as well must not turn it solid -- or no villager
## could ever plan a way indoors, which is exactly what the old `elif` was
## guarding against.
func test_a_piece_built_door_stays_walkable():
	var cell := _global(_origin + Vector2i(1, 3))
	manager.build_at_global(cell.x, cell.y, "wood_door")
	assert_false(
		manager.piece_blocks_movement_at_global(cell.x, cell.y), "a door is walkable"
	)
	assert_false(manager.has_building_at_global(cell.x, cell.y), "and is not a building entity")
	assert_false(
		AgentPassability.structure_blocks(manager, cell), "so the shared question lets it through"
	)


func test_a_piece_built_floor_stays_walkable():
	var cell := _global(_origin + Vector2i(2, 3))
	manager.build_at_global(cell.x, cell.y, "wood_floor")
	assert_false(
		AgentPassability.structure_blocks(manager, cell), "indoors stays reachable"
	)


# -- and the door still works ----------------------------------------------

## The DOORSTEP is outside the footprint by construction
## (BuildingCatalog.doorstep_of: "just south of the door, outside the
## footprint"), so making the whole house solid must not shut a villager
## out of their own front door.
func test_the_doorstep_of_a_house_stays_walkable():
	var doorstep := _global(_origin + BuildingCatalog.doorstep_of(_BUILDING))
	var blocked: Callable = AgentPassability.blocked_predicate_for(manager)
	assert_false(blocked.call(doorstep), "a villager reaches their door from here")
	assert_false(
		WalkGate.blocks(
			manager, _centre_px(doorstep + Vector2i(0, 1)), _centre_px(doorstep),
			float(TerrainRenderer.TILE_SIZE)
		),
		"and may walk onto it"
	)
