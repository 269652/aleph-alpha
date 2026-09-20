extends GutTest

## A village farm's rail is a real thing the PLAYER bumps into (docs/concept/
## village_farms.md, "The rail stands on the inner edge").
##
## Carried for several rounds: the player walked straight through every fence
## in the game while every animal and villager respected them. Nothing was
## broken about the fence rule -- rails_block_step is an ask-before-you-step
## query, markers are Sprite2Ds that ask it, and the player is a
## CharacterBody2D that cannot. It needs something in the world to hit, and a
## rail is not a BuildingPiece, so nothing was ever spawned for it.
##
## The geometry itself lives in VillageFarm and is tested there; this is the
## wiring -- that a real rail placed in a real chunk actually produces a
## body, on the right edge, and that it is cleaned up like every other one.
##
## Uses `_load_chunk` directly and the origin chunk, for the same reason
## test_earth_chunk_manager_upper_floor_collision.gd does: collision-body
## bookkeeping needs no biome or ecosystem simulation.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const VillageFarm = preload("res://src/gameplay/village_farm.gd")

var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var _chunk_coord := Vector2i(0, 0)
var _tile := Vector2i(4, 4)


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


func _bodies() -> Array:
	var out: Array = []
	for child in entities_parent.get_children():
		if child is StaticBody2D:
			out.append(child)
	return out


func _shape_size(body: Node) -> Vector2:
	for child in body.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.shape.size
	return Vector2.ZERO


func _raise_rail(facing: String) -> Node:
	manager.build_at_global(_tile.x, _tile.y, VillageFarm.fence_tile_for(facing))
	var bodies := _bodies()
	return bodies[0] if bodies.size() == 1 else null


func test_a_raised_rail_gets_a_real_collision_body():
	assert_not_null(_raise_rail("north"), "the player needs something to hit")


## The body is a THIN STRIP, not a tile-sized block: the rest of a rail's
## cell is street you may walk.
func test_the_rail_body_is_a_strip_on_one_edge_not_a_whole_tile():
	var body := _raise_rail("north")
	assert_not_null(body)
	var size := _shape_size(body)
	assert_eq(size.x, float(TerrainRenderer.TILE_SIZE), "it spans the tile across the edge")
	assert_eq(size.y, VillageFarm.FENCE_COLLIDER_THICKNESS_PX, "and is only a rail thick")


## ...and it sits on the edge the crop is behind, not in the middle of the
## cell. A rail on the field's north side closes its own SOUTHERN edge.
func test_the_rail_body_sits_on_the_edge_it_closes():
	var body := _raise_rail("north")
	assert_not_null(body)
	var tile_bottom := float(_tile.y + 1) * TerrainRenderer.TILE_SIZE
	assert_almost_eq(
		body.position.y, tile_bottom - VillageFarm.FENCE_COLLIDER_THICKNESS_PX * 0.5, 0.001,
		"the strip's centre is half a thickness in from the southern edge"
	)


## A corner post gets NONE, or it would wall off the two runs it caps and
## shut the ring a villager is supposed to be able to walk round.
func test_a_corner_post_raises_no_body_at_all():
	for facing in VillageFarm.FENCE_TILE_IDS:
		var tile_id: String = VillageFarm.FENCE_TILE_IDS[facing]
		if not VillageFarm.is_fence_corner_tile(tile_id):
			continue
		manager.build_at_global(_tile.x, _tile.y, tile_id)
		assert_eq(_bodies().size(), 0, "%s must not wall the ring" % facing)
		manager.build_at_global(_tile.x, _tile.y, "")


## Ordinary ground raises nothing, and pulling a rail out takes its body with
## it -- the same "overwriting must not leave the old body behind" rule
## _sync_piece_collision already keeps for walls.
func test_pulling_the_rail_out_takes_its_body_with_it():
	assert_not_null(_raise_rail("north"))
	manager.build_at_global(_tile.x, _tile.y, "")
	assert_eq(_bodies().size(), 0, "a torn-out fence line is ordinary ground again")


# -- a horizontal rail's body stands at the foot of its wood ----------------
#
# Reported after the bodies first went in: "The horizontal fences should
# have the hitbox at the bottom of the rail ... so it should use fence
# height instead of thickness".
#
# The two horizontal facings anchor their art to OPPOSITE ends of the cell
# (IllustratedStructureSprite.footprint_offset). A north rail's wood really
# does end at the tile's bottom edge, so its body was always right. A south
# rail's hangs DOWN from the top edge, and a body pinned to that edge
# stopped the player at the rail's HEAD, a good seven pixels short of the
# line they could see.
#
# VillageFarm owns the rule and is tested there; this is the WIRING -- that
# the manager hands it the height of the wood it actually drew, rather than
# a number that makes a south rail look right by accident.

const IllustratedStructureSprite = preload("res://src/rendering/illustrated_structure_sprite.gd")

## How far the body's own bottom edge is allowed to be from the wood's foot.
## Sub-pixel: both come from the same scaled art, so anything larger means
## the manager is measuring something else.
const _FOOT_TOLERANCE := 0.01


func _body_bottom_y(body: Node) -> float:
	return body.position.y + _shape_size(body).y * 0.5


## Where the rail's wood really ends, in world pixels -- read off the sprite
## class rather than restated, so the body and the picture cannot drift.
func _wood_foot_world_y(facing: String) -> float:
	var sprite := IllustratedStructureSprite.new()
	var placed: Rect2 = sprite.placed_art_rect(
		VillageFarm.fence_tile_for(facing), TerrainRenderer.TILE_SIZE
	)
	return float(_tile.y) * TerrainRenderer.TILE_SIZE + placed.end.y


func test_a_horizontal_rails_body_stands_at_the_foot_of_its_wood():
	for facing in ["north", "south"]:
		var body := _raise_rail(facing)
		assert_not_null(body, facing)
		assert_almost_eq(
			_body_bottom_y(body), _wood_foot_world_y(facing), _FOOT_TOLERANCE,
			"%s rail is not standing where its posts land" % facing
		)
		manager.build_at_global(_tile.x, _tile.y, "")


## Stated as the regression itself, with no reference to the art at all: a
## south rail's body used to sit flat against the TOP of its cell. Wherever
## the wood is measured to end, it is not there.
func test_a_south_rails_body_is_no_longer_pinned_to_the_top_of_its_cell():
	var body := _raise_rail("south")
	assert_not_null(body)
	var tile_top := float(_tile.y) * TerrainRenderer.TILE_SIZE
	assert_gt(
		body.position.y, tile_top + TerrainRenderer.TILE_SIZE * 0.5,
		"a south rail hangs down from its top edge, so it blocks in the lower half"
	)


## ...and the north one, which was never wrong, must not move to fix it.
func test_a_north_rails_body_still_sits_on_the_cells_bottom_edge():
	var body := _raise_rail("north")
	assert_not_null(body)
	var tile_bottom := float(_tile.y + 1) * TerrainRenderer.TILE_SIZE
	assert_almost_eq(_body_bottom_y(body), tile_bottom, _FOOT_TOLERANCE)


## A VERTICAL rail spans the full height of its cell and is untouched by any
## of this -- its wood is anchored left or right, so it has no foot on the
## y axis to stand at.
func test_a_vertical_rails_body_still_spans_its_whole_cell():
	for facing in ["east", "west"]:
		var body := _raise_rail(facing)
		assert_not_null(body, facing)
		assert_eq(_shape_size(body).y, float(TerrainRenderer.TILE_SIZE), facing)
		manager.build_at_global(_tile.x, _tile.y, "")
