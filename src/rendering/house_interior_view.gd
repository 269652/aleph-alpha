extends Node2D

## Enterable house interiors (docs/concept/building.md "Entering"): the
## real scene an "Enter" prompt swaps the player into -- built once per
## Enter, freed on Leave. An opaque backdrop, a TileMapLayer sharing the
## MAIN terrain tile set (the exact illustrated wall/floor/furniture tiles
## the rest of the world already draws with -- no second art pipeline),
## and real StaticBody2D collision on every wall AND every "blocking"
## furniture piece, positioned so InteriorTemplates' own door cell lands
## exactly on the house's real world doorstep -- walking out the door
## puts the player back exactly where they entered. Built in code like
## JoustMatchView/HandheldBattleView (see World._build_joust_view), but
## deliberately NOT paused -- the player keeps moving in real world
## coordinates the whole time (see scenes/player.gd's indoors state, the
## two-story floor-switch's own mechanism), so chunk streaming, NPC
## schedules and the clock all keep running while a house is entered.

const InteriorTemplates = preload("res://src/gameplay/interior_templates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const DisplayScaling = preload("res://src/rendering/display_scaling.gd")

## A new collision layer, not layers 1/2 (EarthChunkManager.
## GROUND_FLOOR_COLLISION_LAYER/UPPER_FLOOR_COLLISION_LAYER) -- an interior
## is never simultaneously walkable with either outdoor floor, so it needs
## its own bit rather than reusing one.
const INTERIOR_COLLISION_LAYER := 4

## Above every real world z-index today (UpperFloor/UpperFloorFurniture = 2,
## Player.UPPER_FLOOR_OCCUPANT_Z_INDEX = 4 -- see EarthChunkManager) --
## an interior must always draw over the whole outdoor world, the same
## "one number higher than the current ceiling" reasoning the two-story
## pass itself already used.
const INTERIOR_Z_INDEX := 10
const INTERIOR_OCCUPANT_Z_INDEX := 11

const _WALL_PIECE_ID := "wood_wall"
const _FLOOR_PIECE_ID := "wood_floor"
const _DOOR_PIECE_ID := "wood_door"

## Furniture that blocks movement, by real BuildingPiece.CATEGORY_FURNITURE
## id (docs/concept/building.md "Entering": "its walls and blocking
## furniture (bed, table, bookshelf, couch)... chair/rug/frame don't") --
## the OPPOSITE of BuildingPiece.is_walkable's own blanket-true-for-every-
## furniture-id rule (see that file's own doc comment on why furniture
## never blocks OUTDOORS): an interior room is small and meant to be
## navigated around its own furniture, unlike a sprawling exterior plot.
const _BLOCKING_FURNITURE_IDS := {
	"wood_bed": true, "wood_table": true, "wood_bookshelf": true, "couch": true,
}

## door_cell/size mirror InteriorTemplates.furnish's own output exactly,
## exposed here for callers that need to reason about the room's shape
## without re-deriving it.
var door_cell: Vector2i
var size: Vector2i
## The house's real, world-pixel doorstep -- "Leave" sends the player back
## here (see is_on_exit), and it's exactly where door_cell was aligned to.
var exit_world_position: Vector2

var _tile_map_layer: TileMapLayer
var _backdrop: ColorRect
var _collision_bodies: Dictionary = {}  # local Vector2i -> StaticBody2D
var _tile_size := 16


## Builds the whole interior scene as children of `self`.
## `doorstep_world_position`: the house's real exterior doorstep in world
## pixels (EarthChunkManager.building_door_near's own "doorstep_global",
## converted to pixels) -- InteriorTemplates' own door_cell is aligned
## exactly there, by positioning `self` so that math falls out naturally
## rather than translating every child individually. `shared_tile_set`:
## the SAME TileSet the main terrain TileMapLayer already built (see
## TerrainRenderer.build_tile_set / EarthChunkManager's own
## `_tile_map_layer.tile_set = _terrain_renderer.build_tile_set()`) --
## reused directly, never rebuilt, the same convention every sibling
## overlay layer (roof/furniture/upper floor) already follows.
func build(
	interior_family: String, occupation: String, seed_value: int,
	doorstep_world_position: Vector2, shared_tile_set: TileSet, tile_size: int, terrain_renderer: TerrainRenderer
) -> void:
	var result := InteriorTemplates.furnish(interior_family, occupation, seed_value)
	size = result["size"]
	door_cell = result["door_cell"]
	var cells: Dictionary = result["cells"]
	_tile_size = tile_size
	exit_world_position = doorstep_world_position

	# doorstep_world_position is a CELL CENTER (the same +0.5 convention
	# every doorstep/stand position in this codebase already uses -- see
	# VillageRenderer's own doorstep_position), so door_cell's own center
	# (not its top-left corner) must land exactly there.
	position = doorstep_world_position - (Vector2(door_cell) + Vector2(0.5, 0.5)) * tile_size

	# Padded well past the room's own grid (see visible_world_size_px) --
	# sized to just the grid, this used to leave the real outside world
	# (grass, NPCs, the exterior building) visible all around a small
	# patch of floor, since every authored room is smaller than what the
	# 4x-zoomed camera actually frames. Centering the pad on the room
	# (rather than only growing right/down from local (0,0)) guarantees
	# coverage no matter where in the room the player -- and so the
	# camera, which follows them -- currently stands.
	var room_size_px := Vector2(size) * tile_size
	var visible := visible_world_size_px(tile_size)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.04, 0.03)
	_backdrop.position = -visible * 0.5
	_backdrop.size = room_size_px + visible
	_backdrop.z_index = -2
	add_child(_backdrop)

	_tile_map_layer = TileMapLayer.new()
	_tile_map_layer.tile_set = shared_tile_set
	_tile_map_layer.scale = Vector2.ONE * TerrainRenderer.LAYER_SCALE
	add_child(_tile_map_layer)

	for local: Vector2i in cells:
		var value: String = cells[local]
		_tile_map_layer.set_cell(local, 0, terrain_renderer.atlas_coords_for_modification(_piece_id_for(value)))
		if value == "wall" or _BLOCKING_FURNITURE_IDS.has(value):
			_add_collision_at(local)

	z_index = INTERIOR_Z_INDEX


func tile_map_layer() -> TileMapLayer:
	return _tile_map_layer


func backdrop() -> ColorRect:
	return _backdrop


## How much world the 4x-zoomed camera actually frames at once, in world
## pixels: DisplayScaling.visible_tiles_across at the DESIGN resolution --
## the same 320x180 world-px figure EarthChunkManager's own FRUITING_
## DETAIL_RADIUS comment already derives this way, and the true figure
## rather than just a fallback, since visible_tiles_across is independent
## of the real window size BY DESIGN (see that file). Public (not build()'s
## own private detail) so a test can assert the real coverage guarantee
## against the exact same number build() pads the backdrop with, rather
## than a re-derived or eyeballed one.
static func visible_world_size_px(tile_size: int) -> Vector2:
	var across := DisplayScaling.visible_tiles_across(DisplayScaling.DESIGN_WIDTH, DisplayScaling.DESIGN_HEIGHT)
	var down := DisplayScaling.visible_tiles_across(DisplayScaling.DESIGN_HEIGHT, DisplayScaling.DESIGN_HEIGHT)
	return Vector2(across, down) * tile_size


func collision_body_at(local: Vector2i) -> StaticBody2D:
	return _collision_bodies.get(local)


## Whether `pixel_position` (world coordinates) is close enough to this
## interior's own door/exit cell to leave from -- World's own "Leave"
## prompt check. Deliberately SMALLER than one tile (16px): Player.
## enter_building places the player one full cell (16px) north of the
## door on entry, and this must stay false there -- a player who has
## just walked in must not immediately see (or be able to trigger)
## "Leave" again before ever really being in the room. Standing back at
## the door cell itself (0px away) always counts.
const _EXIT_RADIUS_PX := 10.0

func is_on_exit(pixel_position: Vector2) -> bool:
	return pixel_position.distance_to(exit_world_position) <= _EXIT_RADIUS_PX


func _piece_id_for(cell_value: String) -> String:
	if cell_value == "wall":
		return _WALL_PIECE_ID
	if cell_value == "floor":
		return _FLOOR_PIECE_ID
	if cell_value == "door":
		return _DOOR_PIECE_ID
	return cell_value  # already a real furniture id


func _add_collision_at(local: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.name = "InteriorCollision_%d_%d" % [local.x, local.y]
	body.collision_layer = INTERIOR_COLLISION_LAYER
	body.position = (Vector2(local) + Vector2(0.5, 0.5)) * _tile_size
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_tile_size, _tile_size)
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	_collision_bodies[local] = body
