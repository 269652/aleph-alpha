extends RefCounted

## The one question every walking marker asks before it moves: may I be
## where this step would put me?
##
## Reported live: "Creatures and NPCs also walk through houses". NpcMarker
## and CreatureMarker each grew their own gate; the six OTHER person-shaped
## markers -- builder, farmer, lumberjack, logistics carrier, caravan and
## cart -- had none at all, and walked through walls, fences and cliffs
## alike. This is that rule, written once, so six callers cannot drift from
## it and from each other.
##
## Why a gate rather than physics: every one of these markers is a Sprite2D
## that moves by assigning `position`. No StaticBody2D in the world has ever
## had the slightest effect on one -- which is exactly why the walls that
## stop the PLAYER were walked straight through by everybody else.
##
## Three refusals, and they are different KINDS of fact on purpose:
##   - a slope you cannot climb, and a wall: tiles you may not be IN;
##   - a field's rail: an EDGE you may not CROSS, so the ring around a field
##     stays ordinary ground a villager may walk along.
##
## Pinned by tests/unit/test_walk_gate.gd.

const TerrainPassability = preload("res://src/gameplay/terrain_passability.gd")


## Where the walker may actually end up, given it wanted to reach `to`.
##
## A blocked diagonal slides: the refused axis is dropped and the free one
## survives, so a walker brushing a wall keeps moving ALONG it instead of
## stopping dead against it. Blocked both ways, it stays put -- picking some
## third direction anyway is what produced the erratic flipping this
## project has already fixed twice elsewhere.
##
## `own_field_cells` is the rail exemption (see `blocks`); pass {} for any
## walker that does not work a field, which is all of them but the farmer.
static func slide(
	world, from: Vector2, to: Vector2, tile_size: float, own_field_cells: Dictionary = {}
) -> Vector2:
	if world == null or from == to:
		return to
	if not blocks(world, from, to, tile_size, own_field_cells):
		return to
	var along_x := Vector2(to.x, from.y)
	if not is_equal_approx(to.x, from.x) and not blocks(world, from, along_x, tile_size, own_field_cells):
		return along_x
	var along_y := Vector2(from.x, to.y)
	if not is_equal_approx(to.y, from.y) and not blocks(world, from, along_y, tile_size, own_field_cells):
		return along_y
	return from


## Whether stepping from `from` to `point` is refused.
##
## Every question is asked only of a world that actually answers it, so a
## marker set up with a test double -- or before its world exists -- simply
## walks, rather than erroring once per frame.
##
## The field exemption exists because a field's rails stand on its INNER
## edge, which makes the one villager they shut out the farmer whose beds
## they enclose. It applies to RAILS only: a wall on the worker's own field
## still stops them. Both directions, because a one-way exemption let a
## farmer walk into their own field and then never leave it -- measured on a
## real village (tools/probe_farm_water.gd): three field workers set out for
## the well 8, 2 and 8 times, each refused at their very first step by their
## own rail.
static func blocks(
	world, from: Vector2, point: Vector2, tile_size: float, own_field_cells: Dictionary = {}
) -> bool:
	if world == null:
		return false
	var tile := Vector2i(floori(point.x / tile_size), floori(point.y / tile_size))
	if world.has_method("slope_at_global") and not TerrainPassability.is_passable(
		world.slope_at_global(tile.x, tile.y)
	):
		return true
	if (
		world.has_method("piece_blocks_movement_at_global")
		and world.piece_blocks_movement_at_global(tile.x, tile.y)
	):
		return true
	if not world.has_method("fence_blocks_step_global"):
		return false
	var here := Vector2i(floori(from.x / tile_size), floori(from.y / tile_size))
	if own_field_cells.has(tile) or own_field_cells.has(here):
		return false
	return world.fence_blocks_step_global(here.x, here.y, tile.x, tile.y)
