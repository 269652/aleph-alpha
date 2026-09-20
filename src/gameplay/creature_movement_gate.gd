extends RefCounted

## Decides where a creature is ALLOWED to step, BEFORE it steps there.
##
## Everything else in the creature-movement stack reacts after the fact:
## ThreatAvoidantWander reshapes a heading that already points somewhere bad,
## CreatureMarker._is_moving notices afterwards that the creature didn't
## actually get anywhere. That works while there is somewhere to go, but a
## creature wedged between the player and a tree has nowhere -- and every
## after-the-fact mechanism responds by picking a new direction, every frame,
## which is exactly what reads as erratic flipping (reported: "when it's
## stuck between player and blocked by a tree it still flips erratically...
## same when blocked by a stone").
##
## The fix is to ask first (reported, as the explicit requirement): "make it
## so that all animals first check if moving is going to be blocked by a tree
## or by entering flee radius and only actually execute the move if it's
## clear. If it doesn't have anywhere to go, it should just stay in idle mode
## without walk animation or flips." So this returns either a heading that is
## genuinely clear, or Vector2.ZERO meaning "stay put" -- never a heading the
## caller will then fail to follow.
##
## Pure vector math over plain data (positions + radii), no nodes: the caller
## gathers the real trees/stones/threats (see CreatureMarker._cached_blockers)
## and applies the result.

## Turns tried, in preference order: straight on first, then progressively
## wider deviations to either side, and only as a last resort straight back.
## Preferring the SMALLEST turn that clears keeps a creature walking around
## an obstacle rather than veering wildly off a perfectly good heading, which
## would read as panicking rather than as navigating.
const _TURN_OFFSETS := [
	0.0,
	PI / 6.0, -PI / 6.0,
	PI / 3.0, -PI / 3.0,
	PI / 2.0, -PI / 2.0,
	2.0 * PI / 3.0, -2.0 * PI / 3.0,
	5.0 * PI / 6.0, -5.0 * PI / 6.0,
	PI,
]


## A clear unit heading for a creature at `origin` that wants to go `desired`,
## or Vector2.ZERO when every candidate is blocked -- in which case the caller
## must stand still, NOT move anyway.
##
## `blockers` is an Array of {position: Vector2, radius: float} (trees,
## stones). `threats` is an Array[Vector2] the creature is keeping
## `keep_out_radius` away from; pass an empty Array to ignore threats
## entirely (a fleeing creature still dodges trees, but must not be talked
## out of running by the very thing it is running from).
## `previous_heading` (optional) is the heading this creature actually moved
## along last frame. A detour, once picked, is STICKY: while the desired
## heading stays blocked and the previous heading stays clear, the previous
## heading is kept rather than re-derived -- re-deriving from scratch every
## frame let the chosen side alternate as the position wobbled by
## sub-pixels, which read as flipping erratically right at the obstacle
## (reported: "walks into a tree and starts flipping erratically"). The
## desired heading itself always wins the moment it is clear again, so the
## detour can never outlive the obstacle that caused it.
## `facing_sign` (optional; +1 facing right, -1 facing left, 0 no
## preference) makes a DETOUR prefer the side that keeps the creature's
## current facing: a flip is the single most visible thing a creature can
## do, so a flip-requiring detour when a same-facing one exists reads as
## erratic (reported: "if it gets blocked by a tree and changes direction it
## should not be allowed to instantly flip again"). Candidates whose
## horizontal component opposes the facing are only accepted once every
## facing-preserving candidate has failed -- never refused outright, so a
## creature whose ONLY way out is behind it still takes it.
static func clear_direction(
	origin: Vector2,
	desired: Vector2,
	step_distance: float,
	blockers: Array,
	threats: Array,
	keep_out_radius: float,
	previous_heading: Vector2 = Vector2.ZERO,
	facing_sign: float = 0.0,
	is_blocked_tile: Callable = Callable(),
	tile_size: int = 0
) -> Vector2:
	if desired.length() < 0.001:
		return Vector2.ZERO
	# A building is a rectangle of whole tiles, so it arrives as a tile
	# predicate rather than as circles in `blockers` (see
	# docs/concept/navigation.md): circles over a rectangle either leave
	# real diamond gaps at every four-tile corner or block past the wall,
	# and either way cost O(footprint tiles) per candidate heading -- ~70
	# blockers against twelve headings per creature per tick in a village,
	# the exact shape of cost solid_obstacles_near exists to escape.
	#
	# Resolved to a plain bool ONCE here rather than per candidate: a
	# creature already standing in a building may take any step, the same
	# escape _is_clear's own "don't make it worse" rule already keeps, so
	# that it is never pinned inside a wall.
	var walls := is_blocked_tile
	if walls.is_valid() and tile_size > 0 and walls.call(_tile_of(origin, tile_size)):
		walls = Callable()

	var base := desired.normalized()
	if _is_clear(origin, origin + base * step_distance, blockers, threats, keep_out_radius, walls, tile_size):
		return base
	if previous_heading.length() > 0.001:
		var committed := previous_heading.normalized()
		if _is_clear(origin, origin + committed * step_distance, blockers, threats, keep_out_radius, walls, tile_size):
			return committed
	# Pass 1: facing-preserving candidates only. Pass 2: anything clear.
	if facing_sign != 0.0:
		for offset in _TURN_OFFSETS:
			var candidate: Vector2 = base.rotated(offset)
			if candidate.x * facing_sign < 0.0:
				continue
			if _is_clear(origin, origin + candidate * step_distance, blockers, threats, keep_out_radius, walls, tile_size):
				return candidate
	for offset in _TURN_OFFSETS:
		var candidate: Vector2 = base.rotated(offset)
		if _is_clear(origin, origin + candidate * step_distance, blockers, threats, keep_out_radius, walls, tile_size):
			return candidate
	return Vector2.ZERO


## floori, not int(): the world extends west and north of the origin, where
## truncation rounds toward zero and would read one tile too far east/south.
static func _tile_of(point: Vector2, tile_size: int) -> Vector2i:
	return Vector2i(floori(point.x / tile_size), floori(point.y / tile_size))


## Whether stepping from `origin` to `destination` is allowed.
##
## Both checks are "don't make it WORSE", not "must not be close": a creature
## the player has walked right up to is already inside the keep-out radius,
## and one that has somehow ended up overlapping a tree is already inside
## that too. Refusing every step in those cases would pin the creature in
## place exactly when it most needs to leave, so a step that increases the
## distance (or at least doesn't decrease it) always stays available.
static func _is_clear(
	origin: Vector2,
	destination: Vector2,
	blockers: Array,
	threats: Array,
	keep_out_radius: float,
	is_blocked_tile: Callable = Callable(),
	tile_size: int = 0
) -> bool:
	# Unlike the two "don't make it WORSE" checks below, a wall is absolute:
	# there is no degree of being inside a building. The caller has already
	# cleared this predicate for a creature that starts inside one.
	if is_blocked_tile.is_valid() and tile_size > 0:
		if is_blocked_tile.call(_tile_of(destination, tile_size)):
			return false
	for blocker in blockers:
		var at: Vector2 = blocker["position"]
		var radius: float = blocker["radius"]
		if destination.distance_to(at) < radius and destination.distance_to(at) < origin.distance_to(at):
			return false
	for threat in threats:
		var threat_at: Vector2 = threat
		if (
			destination.distance_to(threat_at) < keep_out_radius
			and destination.distance_to(threat_at) < origin.distance_to(threat_at)
		):
			return false
	return true
