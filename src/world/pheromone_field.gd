extends RefCounted

## A real ant colony's trail pheromone -- see docs/concept/soil_fauna.md
## "Pheromone trails: recruitment to a known-good source" and "Scouting:
## real search, not omniscient dispatch". A successful forager deposits it
## at a food source on the way home; it fades over real time; another
## forager reads it as a bias toward a KNOWN source over an equally-
## convenient unknown one -- the mechanism behind real ant colonies
## collectively favouring shorter/richer paths (Deneubourg et al.'s
## double-bridge experiments) with no individual ant ever comparing
## routes. Read via gradient_direction -- a LOCAL concentration sensed
## exactly where a scout currently stands (real chemotaxis), never a list
## of known candidate destinations compared from a stationary point (that
## omniscient shape, best_candidate_index, was removed -- see
## AntScoutWander for what replaced it).
##
## Deliberately NOT a reuse of ScentField, despite the similar-sounding
## job: ScentField.concentration_at recomputes fresh, every call, from
## whichever flowers are CURRENTLY alive and blooming -- there is nothing
## to persist, because a flower's own presence already IS the state. A
## pheromone trail is the opposite: it has to outlive the ant that laid
## it, which is the entire point of another ant finding it later. So this
## is a real stateful, decaying store, borrowing ScentField's FALLOFF/
## GRADIENT-SAMPLING MATH (a concentration field is a concentration field
## regardless of what maintains it), not its statelessness.

## How far one deposit's scent carries, in tiles -- beyond this it
## contributes nothing, the same squared-taper shape ScentField.falloff
## uses and for the same reason (keeps concentration_at O(nearby deposits)
## and gives a clump's core a genuinely stronger signal than its fringe).
const RADIUS_TILES := 4.0

## Real trail-pheromone components fade over minutes; this game's own
## ecosystem clock already compresses a full simulated day into
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY (60) real seconds, so a
## trail half-life on the same order of magnitude keeps a trail from
## earlier in one simulated "day" reading as fresh while an older one has
## genuinely faded -- proportioned to this game's own pacing rather than a
## literal real-world duration, the same "tuned to how this game actually
## runs" reasoning most of this project's other decay constants already
## use (snow thaw, ripple lifetime).
const HALF_LIFE_SECONDS := 30.0

## Below this, a deposit is indistinguishable from nothing -- pruned so the
## backing dictionary does not grow forever as trails fade.
const PRUNE_THRESHOLD := 0.02

## One successful forager's own deposit.
const DEPOSIT_AMOUNT := 1.0

## Step used when sampling the field to estimate its gradient, in tiles --
## mirrors ScentField.GRADIENT_SAMPLE_TILES exactly, same reasoning.
const GRADIENT_SAMPLE_TILES := 1.0

var _deposits: Dictionary = {}  # Vector2i tile -> float amount


## Adds to whatever is already at `tile` -- repeated success at the same
## spot reads as a stronger trail, not a replaced one.
func deposit(tile: Vector2i, amount: float = DEPOSIT_AMOUNT) -> void:
	_deposits[tile] = _deposits.get(tile, 0.0) + amount


## Fades every deposit by real elapsed time -- exponential decay at
## HALF_LIFE_SECONDS, pruning anything that has faded below
## PRUNE_THRESHOLD so the dictionary does not grow forever.
func decay(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or _deposits.is_empty():
		return
	var factor := pow(0.5, delta_seconds / HALF_LIFE_SECONDS)
	var stale: Array = []
	for tile in _deposits:
		var amount: float = _deposits[tile] * factor
		if amount < PRUNE_THRESHOLD:
			stale.append(tile)
		else:
			_deposits[tile] = amount
	for tile in stale:
		_deposits.erase(tile)


## A single deposit's contribution at `distance_tiles`, as a fraction of
## its own amount: full at the source, tapering to nothing at
## RADIUS_TILES. Mirrors ScentField.falloff exactly.
static func falloff(distance_tiles: float) -> float:
	if distance_tiles >= RADIUS_TILES:
		return 0.0
	var t := 1.0 - clampf(distance_tiles, 0.0, RADIUS_TILES) / RADIUS_TILES
	return t * t


## Total pheromone at `point` (world pixels): every deposit's amount scaled
## by its falloff, summed -- mirrors ScentField.concentration_at's own
## superposition shape.
func concentration_at(point: Vector2, tile_size: float) -> float:
	if tile_size <= 0.0:
		return 0.0
	var total := 0.0
	for tile in _deposits:
		var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * tile_size
		var distance_tiles := point.distance_to(tile_center) / tile_size
		total += _deposits[tile] * falloff(distance_tiles)
	return total


## A unit vector pointing up the concentration gradient -- mirrors
## ScentField.gradient_direction's own finite-difference sampling exactly.
## Vector2.ZERO where there is nothing to sense (or at a perfectly flat
## spot).
func gradient_direction(point: Vector2, tile_size: float) -> Vector2:
	var step := GRADIENT_SAMPLE_TILES * tile_size
	var east := concentration_at(point + Vector2(step, 0.0), tile_size)
	var west := concentration_at(point - Vector2(step, 0.0), tile_size)
	var south := concentration_at(point + Vector2(0.0, step), tile_size)
	var north := concentration_at(point - Vector2(0.0, step), tile_size)
	var gradient := Vector2(east - west, south - north)
	if gradient.length() <= 0.0001:
		return Vector2.ZERO
	return gradient.normalized()


func is_empty() -> bool:
	return _deposits.is_empty()
