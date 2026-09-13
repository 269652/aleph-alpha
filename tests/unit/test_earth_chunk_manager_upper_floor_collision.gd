extends GutTest

## Real per-floor collision for two-story houses (docs/concept/housing.md's
## "Two-story houses" section) -- named honestly as a gap when that feature
## first shipped ("no real upper-floor wall collision yet (visual/room-
## detection only) -- a player can walk through an upstairs wall today"),
## closed here directly per a follow-up request to "properly implement" it.
##
## Ground-floor wall/window collision (test_earth_chunk_manager.gd's own
## "building-piece collision" section) already proved a StaticBody2D+
## CollisionShape2D per solid cell is the real mechanism this project uses
## for tile solidity -- this mirrors that exactly, one layer up, rather than
## inventing a second one. The one genuinely new idea is WHY a second real
## Godot physics layer (bit 2, not bit 1) is needed rather than just reusing
## the ground body mechanism verbatim: a house's ground and upper wall rings
## occupy the SAME (x, y) cells almost everywhere (HouseBlueprint.
## build_upper_floor reuses build()'s own footprint), but NOT at the one
## cell that matters most -- the ground floor's door (walkable, no
## collision) sits under the upper floor's OWN window there instead (solid).
## A single shared collision layer could only pick one answer for that cell;
## two independent layers, with the PLAYER's own collision_mask switching
## between them on step_on_stairs, let each floor be correct on its own
## terms with a single property flip rather than iterating and toggling
## every collision body in the loaded world on every staircase crossing.
##
## Uses `_load_chunk` directly rather than `update()` (see CONTRIBUTING.md /
## test_earth_chunk_manager.gd's own known-slow-file note) -- collision-body
## bookkeeping needs no biome/ecosystem simulation, so the origin chunk is a
## perfectly good fixture, unlike the footprint/footstep tests that need a
## real inland Berlin tile.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _tile := Vector2i(4, 4)  # comfortably inside the origin chunk


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	add_child(entities_parent)
	manager._load_chunk(_chunk_coord)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _expected_position(tile: Vector2i) -> Vector2:
	return Vector2((tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE)


func _static_body_at(position: Vector2) -> Node:
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == position:
			return child
	return null


# -- the two real physics layers themselves --------------------------------

## Ground stays on Godot's own default layer (bit 1) -- unchanged from
## before this feature existed, so every pre-existing collision body in
## this codebase (trees, stones, ore, ground walls) keeps colliding exactly
## as it always has, with zero blast radius.
func test_ground_floor_collision_layer_is_the_default_bit():
	assert_eq(EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER, 1)


## A genuinely different bit, not a re-used or zero value -- the whole
## mechanism depends on these two never colliding with the same mask.
func test_upper_floor_collision_layer_is_a_distinct_bit():
	assert_eq(EarthChunkManager.UPPER_FLOOR_COLLISION_LAYER, 2)


# -- build_upper_floor_at_global: the same per-cell contract build_at_global
# -- already has, one layer up (also BuilderMarker's own per-piece placement
# -- hook -- see test_builder_marker.gd's two-story tests) --------------------

func test_building_an_upper_wall_piece_adds_a_collision_body():
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_wall")
	assert_not_null(_static_body_at(_expected_position(_tile)), "an upper wall should physically block the upper floor")


func test_building_an_upper_floor_piece_adds_no_collision_body():
	var before := entities_parent.get_child_count()
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_floor")
	assert_eq(entities_parent.get_child_count(), before, "a floor is walkable, nothing should block it")


func test_building_upper_stairs_adds_no_collision_body():
	var before := entities_parent.get_child_count()
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_stairs")
	assert_eq(entities_parent.get_child_count(), before, "stairs must stay walkable on both floors")


func test_destroying_an_upper_wall_piece_removes_its_collision_body():
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_wall")
	var with_wall := entities_parent.get_child_count()
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_door")  # overwrite with a walkable piece
	assert_eq(entities_parent.get_child_count(), with_wall - 1, "the old upper wall's collision body must be gone")


## The upper wall's own body must sit on the NEW physics layer, never the
## ground layer -- this is the one property the whole floor-toggle trick
## (Player.collision_mask) depends on.
func test_upper_wall_collision_body_is_on_the_upper_floor_layer():
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_wall")
	var body := _static_body_at(_expected_position(_tile))
	assert_eq(body.collision_layer, EarthChunkManager.UPPER_FLOOR_COLLISION_LAYER)


## And the ground wall's own body must stay on the ground layer -- a real
## regression test for the exact bug this whole feature exists to fix: the
## ground floor's door cell (walkable) sitting directly under the upper
## floor's own window (solid) at the identical (x, y).
func test_ground_wall_collision_body_is_on_the_ground_floor_layer_not_the_upper_one():
	manager.build_at_global(_tile.x, _tile.y, "wood_wall")
	var body := _static_body_at(_expected_position(_tile))
	assert_eq(body.collision_layer, EarthChunkManager.GROUND_FLOOR_COLLISION_LAYER)


## The exact scenario this feature is FOR: a ground door (walkable, no
## collision) with a real, solid upper window directly above it at the
## SAME (x, y) -- both pieces coexist as two independent collision bodies
## on two independent layers, neither shadowing the other.
func test_a_ground_door_and_an_upper_window_at_the_same_cell_both_get_their_own_correct_collision():
	manager.build_at_global(_tile.x, _tile.y, "wood_door")
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_window")
	var bodies := []
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == _expected_position(_tile):
			bodies.append(child)
	assert_eq(bodies.size(), 1, "only the upper window should be solid -- the ground door stays walkable")
	assert_eq(bodies[0].collision_layer, EarthChunkManager.UPPER_FLOOR_COLLISION_LAYER)


# -- stamp_upper_floor_at_global: the bulk per-house stamp (player-built and,
# -- once wired, village-generated two-story houses) also syncs collision,
# -- not just the per-cell build path above -----------------------------------

func test_stamping_a_two_story_house_adds_collision_for_its_upper_walls():
	var HouseBlueprint = preload("res://src/gameplay/house_blueprint.gd")
	var house_blueprint = HouseBlueprint.new()
	var origin_tile := Vector2i(2, 2)
	var upper_pieces := house_blueprint.build_upper_floor("tower_keep", 7)
	var before := entities_parent.get_child_count()
	manager.stamp_upper_floor_at_global(_chunk_coord, origin_tile, upper_pieces)
	assert_gt(entities_parent.get_child_count(), before, "a real stamped upper floor should add real wall collision")


# -- chunk lifecycle: same create-at-load/erase-at-unload/restore-at-reload --
# -- shape the ground layer's own collision bodies already have -------------

func test_unloading_a_chunk_frees_its_upper_floor_collision_bodies_too():
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_wall")
	var body := _static_body_at(_expected_position(_tile))
	assert_not_null(body, "precondition: the upper wall's collision body exists")

	manager._unload_chunk(_chunk_coord)

	assert_false(is_instance_valid(body), "unloading the chunk should free its upper-floor collision bodies too")
	var path := "user://chunk_upper_floor_modifications/%d_%d.bin" % [_chunk_coord.x, _chunk_coord.y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_reloading_a_chunk_restores_collision_for_a_persisted_upper_wall():
	manager.build_upper_floor_at_global(_tile.x, _tile.y, "wood_wall")

	manager._unload_chunk(_chunk_coord)  # persists to disk
	manager._load_chunk(_chunk_coord)  # reloads it

	assert_not_null(
		_static_body_at(_expected_position(_tile)), "a restored upper-floor wall should get its collision body back"
	)
	var path := "user://chunk_upper_floor_modifications/%d_%d.bin" % [_chunk_coord.x, _chunk_coord.y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
