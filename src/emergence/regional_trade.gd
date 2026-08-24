extends RefCounted

## Cross-settlement resource transfer -- the "trade networks" element of
## docs/emergence/07-implementation-roadmap.md Phase 14 ("regions, trade
## networks, migration flows, dependency graphs, and resource corridors"),
## see docs/concept/regional_trade.md. Reuses Phase 12's own real shortage
## detection (Quest) rather than inventing a parallel "who needs what"
## system, and a settlement's own real EntityRef key rather than a second
## stored position.
##
## Deliberately narrow, same discipline as every earlier phase: of the
## five named elements, only trade networks are grounded in real,
## already-tracked data (Market stock, Quest shortfalls, settlement chunk
## coordinates). Migration flows need a real migration/departure mechanism
## that doesn't exist yet (the same "nothing removes a household" gap
## Phase 9 already documented); dependency graphs and resource corridors
## are real aggregations OVER trade edges once enough of them exist, not a
## separate structure this slice builds.

const EntityRef = preload("res://src/emergence/entity_ref.gd")

## How much of an item a market must hold ABOVE what a shortfall needs
## before it counts as real, tradeable surplus -- a safety margin so a
## settlement never trades away its own last reserve down to the exact
## edge just to help a neighbor. Tested against the behavior it produces
## (test_regional_trade.gd), the same "no real economy data to derive a
## correct number from yet" honesty every other tuned constant in this
## substrate already states.
const MIN_SURPLUS := 5


## Whether a market holding `stock` of an item has real surplus beyond
## `need` units.
static func has_surplus(stock: int, need: int) -> bool:
	return stock >= need + MIN_SURPLUS


## The settlement's own chunk coordinate, parsed back out of its real
## EntityRef key ("settlement:<x>_<y>") -- the same key
## EntityRef.for_settlement already derives a settlement's identity from,
## not a second stored position. Vector2i.ZERO for an id that doesn't
## parse as one, rather than crashing.
static func chunk_coord_of(settlement_id: String) -> Vector2i:
	var parts := EntityRef.key_of(settlement_id).split("_")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


## Real Euclidean distance between two settlements' own chunk coordinates.
static func distance_between(a_id: String, b_id: String) -> float:
	return chunk_coord_of(a_id).distance_to(chunk_coord_of(b_id))
