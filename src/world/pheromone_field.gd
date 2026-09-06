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
##
## ## Directional trails (recruitment to a CLUSTER)
##
## Reported live: "when a scout goes out other ants follow him in a line
## even when nothing has been discovered yet... these scouts should only
## lay out pheromones after they discovered a cluster for which multiple
## ants are needed... he encodes direction and amount in the pheromones so
## other ants don't follow it back into the mound on the way back from a
## discovery... the last ant which takes home the last piece or one that
## encounters it empty invalidates the pheromone trail by masking the
## existing pheromone trail with complete marker". Each deposit is now
## {amount, direction, exhausted}, not a bare float:
##   amount     -- same role as before (concentration_at/gradient_direction
##                 math is completely unchanged), PLUS roughly how much/
##                 how many a resolver can expect to find at the far end.
##   direction  -- unit vector pointing TOWARD the resource FROM this tile,
##                 computed once at deposit time from the food's own real
##                 position (see AntForagerMarker's own trail-laying) --
##                 exact, not inferred from a gradient, and specifically
##                 why a new ant reading a trail near the mound heads OUT
##                 rather than mistaking the trail's own origin for its
##                 destination. Vector2.ZERO for a plain deposit() call
##                 (see that function's own doc comment) -- nothing to
##                 follow there.
##   exhausted  -- set by invalidate_near once a cluster is fully spent
##                 (the last real item taken, or an ant arriving to find
##                 it already empty) -- a real stop signal a resolver can
##                 read directly, distinct from "merely faded" (which
##                 looks the same as "never existed" once low enough).
##                 Excluded from concentration_at/gradient_direction (an
##                 exhausted spot must not keep pulling anyone toward it)
##                 and from nearest_trail_near/has_active_trail (nothing
##                 left worth resolving). Still decays/prunes normally --
##                 the "stop" signal does not need to outlast the deposit's
##                 own ordinary fade.

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

var _deposits: Dictionary = {}  # Vector2i tile -> {amount, direction, exhausted}


## Adds to whatever is already at `tile` -- repeated success at the same
## spot reads as a stronger trail, not a replaced one. No direction
## encoded (Vector2.ZERO) -- a plain "there was something here" mark, not
## a followable trail (see nearest_trail_near/has_active_trail, which both
## ignore a Vector2.ZERO direction for exactly that reason). Kept
## unchanged for backward compatibility; real cluster recruitment now
## goes through deposit_trail instead (see this file's own doc comment).
func deposit(tile: Vector2i, amount: float = DEPOSIT_AMOUNT) -> void:
	var existing: Dictionary = _deposits.get(tile, _blank_deposit())
	existing.amount += amount
	_deposits[tile] = existing


## Real directional trail deposit -- see this file's own doc comment.
## REPLACES (not accumulates) whatever was at `tile`: a fresh observation
## of "amount left, which way to the resource" is more useful than a
## blended history of possibly-stale ones, unlike the plain deposit()'s
## own "repeated success reads as stronger" reasoning.
func deposit_trail(tile: Vector2i, direction: Vector2, amount: float) -> void:
	_deposits[tile] = {"amount": amount, "direction": direction, "exhausted": false}


func _blank_deposit() -> Dictionary:
	return {"amount": 0.0, "direction": Vector2.ZERO, "exhausted": false}


## Fades every deposit by real elapsed time -- exponential decay at
## HALF_LIFE_SECONDS, pruning anything that has faded below
## PRUNE_THRESHOLD so the dictionary does not grow forever. Applies
## equally to an exhausted deposit's own stop signal -- it does not need
## to outlast the deposit's ordinary fade (see this file's own doc
## comment).
func decay(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or _deposits.is_empty():
		return
	var factor := pow(0.5, delta_seconds / HALF_LIFE_SECONDS)
	var stale: Array = []
	for tile in _deposits:
		var data: Dictionary = _deposits[tile]
		var amount: float = data.amount * factor
		if amount < PRUNE_THRESHOLD:
			stale.append(tile)
		else:
			data.amount = amount
			_deposits[tile] = data
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


## Total pheromone at `point` (world pixels): every NON-EXHAUSTED deposit's
## amount scaled by its falloff, summed -- mirrors ScentField.
## concentration_at's own superposition shape. An exhausted deposit
## contributes nothing: a scout's own ambient wander bias must not keep
## being pulled toward a spot already known to be spent (see this file's
## own doc comment).
func concentration_at(point: Vector2, tile_size: float) -> float:
	if tile_size <= 0.0:
		return 0.0
	var total := 0.0
	for tile in _deposits:
		var data: Dictionary = _deposits[tile]
		if data.exhausted:
			continue
		var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * tile_size
		var distance_tiles := point.distance_to(tile_center) / tile_size
		total += data.amount * falloff(distance_tiles)
	return total


## A unit vector pointing up the concentration gradient -- mirrors
## ScentField.gradient_direction's own finite-difference sampling exactly.
## Vector2.ZERO where there is nothing to sense (or at a perfectly flat
## spot). Built on concentration_at, so an exhausted deposit is excluded
## here too.
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


## The nearest REAL, followable trail (a non-exhausted deposit with a real
## encoded direction -- see deposit_trail) within RADIUS_TILES of `point`,
## or {} if none. What a resolver reads to know which way to walk from
## wherever it currently stands -- exact and unambiguous (the direction
## was computed once, straight at the resource, at deposit time), unlike
## a scout's own ambient gradient_direction bias, which only ever infers a
## rough uphill direction from concentration differences. A plain
## deposit() (Vector2.ZERO direction) is never returned here -- there is
## nothing real to follow there.
func nearest_trail_near(point: Vector2, tile_size: float) -> Dictionary:
	var best_distance := RADIUS_TILES
	var best: Dictionary = {}
	for tile in _deposits:
		var data: Dictionary = _deposits[tile]
		if data.exhausted or data.direction == Vector2.ZERO:
			continue
		var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * tile_size
		var distance_tiles := point.distance_to(tile_center) / tile_size
		if distance_tiles < best_distance:
			best_distance = distance_tiles
			best = {"direction": data.direction, "amount": data.amount}
	return best


## Whether this field currently holds ANY real, followable trail (see
## nearest_trail_near) anywhere at all -- what the colony checks before
## deciding to dispatch resolvers instead of blind scouts (see
## docs/concept/soil_fauna.md "Scouting: real search, not omniscient
## dispatch"). A plain deposit() alone (no direction) never counts.
func has_active_trail() -> bool:
	for tile in _deposits:
		var data: Dictionary = _deposits[tile]
		if not data.exhausted and data.direction != Vector2.ZERO:
			return true
	return false


## Masks every real trail deposit within `radius_tiles` of `point` with a
## genuine stop signal (see this file's own doc comment) -- called by
## whichever ant discovers a cluster is spent (took the last real item, or
## arrived to find it already empty). Marks `exhausted = true` in place
## rather than erasing the entry outright: nearest_trail_near/
## has_active_trail/concentration_at all already treat an exhausted
## deposit as nothing worth sensing, but the entry itself survives to
## decay on its own ordinary schedule (see decay's own doc comment) rather
## than vanishing outright and risking a fresh, unrelated deposit reusing
## the same tile before the "stop" signal has had any time to matter.
func invalidate_near(point: Vector2, radius_tiles: float, tile_size: float) -> void:
	for tile in _deposits:
		var tile_center := (Vector2(tile) + Vector2(0.5, 0.5)) * tile_size
		if point.distance_to(tile_center) / tile_size <= radius_tiles:
			var data: Dictionary = _deposits[tile]
			data.exhausted = true
			_deposits[tile] = data


func is_empty() -> bool:
	return _deposits.is_empty()
