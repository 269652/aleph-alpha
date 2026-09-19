extends RefCounted

## The carter: the villager who walks the store's round and pulls the
## Bollerwagen (docs/concept/village_warehouse.md, Mechanism 4).
##
## Asked directly, and then corrected: *"The warehouse also needs to bind a
## worker which then collects all ressources from every production
## building"*, and *"It should be a real NPC pulling the cart, not an
## additional sprite"*. A village's hauling is a TRADE, not a spawned
## walker -- so a carter works the store's round exactly the way the
## lumberjack works the mill and the farmer works their beds: an NpcMarker
## work step over the same LogisticsBehavior phase machine the
## placeable-scale worker already uses.
##
## The WHAT half only. WHEN each leg completes is LogisticsBehavior's, and
## the world effect is NpcMarker's -- the same three-part split
## VillageSawmill/VillageFarm/VillagePond already keep.

## What this trade is called. A real entry in NpcIdentity.OCCUPATIONS, not a
## role invented beside the list: a carter is born to it like any other
## villager is born to theirs.
const OCCUPATION := "carter"

## Where their schedule sends them: the store itself, not a prop beside it.
## The same choice the lumberjack's own "sawmill" tag makes, and for the same
## reason -- the building is really there, and the work override takes them
## out to the producers anyway.
const WORK_LOCATION := "warehouse"


static func walks_the_round(occupation: String) -> bool:
	return occupation == OCCUPATION


## Which producer's shelf is worth walking to: the one with the most waiting
## on it. `shelves` is a list of {cell, waiting} records -- the caller's own
## reading of what each producer is really holding.
##
## {} when nothing is waiting anywhere, which is a carter's ordinary answer
## in a village whose producers are between harvests: they keep the day's
## schedule like any other villager whose work has nothing in it.
##
## Ties are broken by CELL, so a village sends its carter the same way on
## every visit rather than by whichever order a Dictionary happened to
## enumerate its buildings in -- the same determinism every other siting and
## pairing rule in this project keeps.
static func fullest_shelf(shelves: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for shelf in shelves:
		var waiting := int(shelf.get("waiting", 0))
		if waiting <= 0:
			continue
		var cell: Vector2i = shelf.get("cell", Vector2i.ZERO)
		var key: Array = [-waiting, cell.y, cell.x]
		if best.is_empty() or key < best_key:
			best_key = key
			best = shelf
	return best
