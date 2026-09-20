extends RefCounted

## The one place a mover learns which tiles a building stands on (see
## docs/concept/navigation.md).
##
## Three different movers need exactly this question answered --
## NpcMarker, CreatureMarker and BondedCompanionMarker -- and all three
## assign `position` directly rather than being physics bodies, so none of
## them can ever collide with a building's real StaticBody2D. Keeping the
## predicate in one place is the same "one function, so two callers cannot
## drift apart" discipline BuildingCatalog.finished_sheet_for keeps.
##
## The Callable is built ONCE per mover (in its own setup), never per
## frame: both movement gates call it several times per frame per agent,
## and allocating a fresh lambda each time is precisely the per-frame
## churn CreatureMarker's own blocker cache already exists to avoid.


## A `func(tile: Vector2i) -> bool` saying whether a building stands on
## that tile, or an INVALID Callable when `world` cannot answer.
##
## Both gates read an invalid Callable as "nothing is solid", so a stub
## world or an unbound marker keeps walking exactly as it always did --
## the same duck-typed fail-open NpcMarker._is_in_water already makes.
static func predicate_for(world) -> Callable:
	if world == null or not world.has_method("has_building_at_global"):
		return Callable()
	return func(tile: Vector2i) -> bool:
		return world.has_building_at_global(tile.x, tile.y)
