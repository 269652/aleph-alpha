extends RefCounted

## Pure cost/cooldown rules for fast travel: distance-scaled currency cost and
## cooldown, with a flat minimum of each so even a zero-distance jump isn't free.

const BASE_COST: int = 10
const COST_PER_TILE: float = 0.5

const BASE_COOLDOWN_SECONDS: float = 5.0
const COOLDOWN_PER_TILE_SECONDS: float = 0.2


## Currency cost of a fast travel, rounded to the nearest int. Never below
## BASE_COST, and non-decreasing as distance_tiles grows.
func cost_for_distance(distance_tiles: float) -> int:
	return int(round(BASE_COST + distance_tiles * COST_PER_TILE))


## Cooldown, in seconds, before another fast travel is allowed. Never below
## BASE_COOLDOWN_SECONDS, and non-decreasing as distance_tiles grows.
func cooldown_seconds_for_distance(distance_tiles: float) -> float:
	return BASE_COOLDOWN_SECONDS + distance_tiles * COOLDOWN_PER_TILE_SECONDS


## Combined check: affordable and not on cooldown.
func can_fast_travel(wallet_balance: int, cost: int, cooldown_remaining: float) -> bool:
	return wallet_balance >= cost and cooldown_remaining <= 0.0


## Whether a load of cargo may be brought along on a fast travel
## (concept/transportation.md "Fast travel: free for cargo, never for living
## stock"). Inanimate cargo is always allowed, with no mass/value cost of any
## kind; a load is disallowed entirely if it contains even one living creature
## (tamed/bred stock), regardless of what else is in it. Each cargo entry is a
## Dictionary; "is_living" absent defaults to false (inanimate).
func can_fast_travel_with_cargo(cargo: Array) -> bool:
	for entry in cargo:
		if entry.get("is_living", false):
			return false
	return true
