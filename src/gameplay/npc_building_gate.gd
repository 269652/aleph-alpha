extends RefCounted

## Where an NPC may actually step, given the buildings in its way (see
## docs/concept/npc.md "Walls are solid to a villager too").
##
## Reported live: *"NPCs walk straight through houses, ignoring the
## hitbox"*. The hitbox is real and it is not broken --
## EarthChunkManager._spawn_building_node gives every building a
## StaticBody2D, and that is exactly what stops the PLAYER, who is a real
## physics body. An NpcMarker is a plain Sprite2D that assigns `position`
## directly (`position = position.move_toward(target, ...)`), so no
## physics body is ever consulted on its behalf and no collision can
## possibly happen. Nothing needed fixing in the building; the villager
## needed to be asked to look.
##
## The same ask-first shape CreatureMovementGate already uses for trees and
## stones, and the same "pure math over plain data, no nodes" split: the
## caller supplies a predicate saying which tiles are solid, and gets back
## the position the NPC is allowed to occupy.
##
## Deliberately TILE-based rather than radius-based, unlike its creature
## sibling: a building already knows its own footprint cell by cell
## (EarthChunkManager.building_at_global answers for any of them), so a
## tile test is both exact and cheaper than fitting circles to rectangles.

## The position an NPC ends up at, having tried to move from `from` to
## `desired`.
##
## `is_blocked` takes a tile (Vector2i) and returns whether it is solid. An
## invalid Callable means "nothing is solid" -- the same duck-typed
## fail-open NpcMarker._is_in_water already uses for a marker with no world
## bound, so an isolated test or an unbound marker walks exactly as before.
static func resolve_step(
	from: Vector2, desired: Vector2, tile_size: int, is_blocked: Callable
) -> Vector2:
	if not is_blocked.is_valid() or tile_size <= 0:
		return desired
	# Already standing in something solid -- a house raised over a standing
	# villager, or an older save that put one there. Every step is allowed
	# so they can walk out; refusing here would imprison them permanently,
	# which is a worse bug than the one this class exists to fix.
	if is_blocked.call(_tile_of(from, tile_size)):
		return desired
	if not is_blocked.call(_tile_of(desired, tile_size)):
		return desired
	# Blocked head-on. Slide along whichever axis is still free rather than
	# stopping dead: walking diagonally into a wall is the commonest case by
	# far, and refusing outright would pin villagers against their own
	# houses instead of letting them walk along them, which is what a
	# person does.
	var along_x := Vector2(desired.x, from.y)
	if not is_blocked.call(_tile_of(along_x, tile_size)):
		return along_x
	var along_y := Vector2(from.x, desired.y)
	if not is_blocked.call(_tile_of(along_y, tile_size)):
		return along_y
	return from


## floori, not int() -- villages exist west and north of the origin, and
## int truncation rounds toward zero there, which would place a negative
## position one tile too far east/south and let a step slip inside a wall.
static func _tile_of(point: Vector2, tile_size: int) -> Vector2i:
	return Vector2i(floori(point.x / tile_size), floori(point.y / tile_size))
