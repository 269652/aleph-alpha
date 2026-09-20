extends RefCounted

## A* over the tile grid -- how a villager gets AROUND a building rather
## than merely along it (see docs/concept/navigation.md).
##
## Reported live: "add proper wayfinding / routing". The wall slide's axis
## sliding keeps an agent moving along a wall it brushes, which is right
## for brushing and useless for a detour: a villager whose own doorstep sat
## behind its own house pressed into that house forever. Sliding is a local
## reflex; this is a plan.
##
## Deliberately an ordinary A*. The interesting decisions here are not in
## the search -- they are in what the search is allowed to cost, and in
## what it does when it cannot succeed:
##
##   * EIGHT-CONNECTED, octile heuristic. Agents move diagonally, so a
##     four-connected route would visibly staircase where a straight
##     diagonal exists.
##   * NO CORNER CUTTING. A diagonal between two blocked orthogonal
##     neighbours is refused, or villagers slip through the exact seam
##     where two buildings touch.
##   * A HARD NODE BUDGET, not a distance limit. The world is chunk-
##     streamed and effectively infinite; an unbounded search toward an
##     unreachable goal would walk the whole loaded region. Exhausting the
##     budget returns NO route rather than a bad one.
##   * A BLOCKED GOAL RETURNS NOTHING, rather than a nearest-reachable
##     guess. A villager's real destination is its doorstep, which is
##     never inside a footprint (BuildingCatalog.doorstep_of puts it one
##     row south), so a blocked goal means something genuinely unexpected
##     and guessing would hide it.
##
## Pure and static: tiles in, tiles out, no nodes and no world -- the same
## split CreatureMovementGate and AgentPassability already keep, so every
## branch is reachable headlessly against a hand-written predicate.

## Straight moves cost 1; a diagonal costs sqrt(2). Integers scaled by 100
## keep the whole search in ints, which keeps ordering exact -- float
## accumulation over a long route can make two genuinely equal paths
## compare unequal and the result non-deterministic.
const _STRAIGHT_COST := 100
const _DIAGONAL_COST := 141  # round(100 * sqrt(2))

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


## The tiles to walk, in order, EXCLUDING the one already stood on, or []
## when there is no route within `node_budget`.
##
## `is_blocked` takes a Vector2i and returns whether that tile is solid. An
## invalid Callable routes as open ground, the same fail-open every other
## mover contract here keeps.
## `cost_scale` optionally takes a Vector2i and returns how much longer
## crossing it takes than open flat ground (see AgentPassability) -- water
## is slow but crossable, so a route costed in TIME can prefer a dry
## detour and still wade when wading is genuinely quicker. Clamped to at
## least 1.0: the octile heuristic assumes open ground is the cheapest
## there is, and a cheaper tile would make it overestimate and quietly
## return non-optimal routes.
static func route(
	from_tile: Vector2i, to_tile: Vector2i, is_blocked: Callable, node_budget: int,
	cost_scale: Callable = Callable()
) -> Array:
	if from_tile == to_tile:
		return []
	var blocked := is_blocked
	if not blocked.is_valid():
		blocked = func(_tile: Vector2i) -> bool: return false
	if blocked.call(to_tile):
		return []
	# Standing inside a wall is not a reason to refuse to leave: the start
	# tile is never tested, only the tiles stepped onto. Every other rule
	# in this stack keeps the same escape.

	var came_from := {}
	var cost_so_far := {from_tile: 0}
	# Plain array used as a priority queue: this search is bounded by
	# node_budget (a few thousand at most), and an array scan at that size
	# costs less than maintaining a heap in GDScript.
	var frontier: Array = [{"tile": from_tile, "priority": 0}]
	var expanded := 0

	while not frontier.is_empty():
		if expanded >= node_budget:
			return []  # budget spent: no route, rather than a bad one
		var best := 0
		for i in range(1, frontier.size()):
			if frontier[i]["priority"] < frontier[best]["priority"]:
				best = i
		var current: Vector2i = frontier[best]["tile"]
		frontier.remove_at(best)
		expanded += 1

		if current == to_tile:
			return _rebuild(came_from, from_tile, to_tile)

		for step in _NEIGHBOURS:
			var next: Vector2i = current + step
			if blocked.call(next):
				continue
			var diagonal: bool = step.x != 0 and step.y != 0
			if diagonal:
				# Refuse to squeeze between two blocked orthogonal
				# neighbours -- that seam is where two buildings touch, and
				# it is not walkable however the geometry looks.
				if (
					blocked.call(Vector2i(current.x + step.x, current.y))
					and blocked.call(Vector2i(current.x, current.y + step.y))
				):
					continue
			var step_cost: int = _DIAGONAL_COST if diagonal else _STRAIGHT_COST
			if cost_scale.is_valid():
				step_cost = int(round(step_cost * maxf(float(cost_scale.call(next)), 1.0)))
			var new_cost: int = int(cost_so_far[current]) + step_cost
			if cost_so_far.has(next) and new_cost >= int(cost_so_far[next]):
				continue
			cost_so_far[next] = new_cost
			came_from[next] = current
			frontier.append({"tile": next, "priority": new_cost + _octile(next, to_tile)})
	return []


## Octile distance: the exact cost of the cheapest unobstructed 8-connected
## path, so the heuristic is admissible (never overestimates) and A* stays
## optimal rather than merely fast.
static func _octile(a: Vector2i, b: Vector2i) -> int:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return _STRAIGHT_COST * (dx + dy) + (_DIAGONAL_COST - 2 * _STRAIGHT_COST) * mini(dx, dy)


static func _rebuild(came_from: Dictionary, from_tile: Vector2i, to_tile: Vector2i) -> Array:
	var reversed_route: Array = []
	var cursor := to_tile
	while cursor != from_tile:
		reversed_route.append(cursor)
		cursor = came_from[cursor]
	reversed_route.reverse()
	return reversed_route
