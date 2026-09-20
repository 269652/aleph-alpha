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
