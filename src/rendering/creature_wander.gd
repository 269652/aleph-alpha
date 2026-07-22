extends RefCounted

## Pure, deterministic idle-wander motion for placeholder creature markers.
## Not AI/pathfinding (that's real gameplay behavior, out of Phase 1 scope --
## see docs/progress.md) -- just enough movement that a spawned marker reads
## as "alive" rather than a static prop, staying loosely near where it spawned.

## 8px/s (half a 16px tile per second) turned out to be imperceptible at a
## glance; bumped to a clearly-visible pace. Underlying tests assert
## properties (moves by speed*delta, stays bounded, biases home) rather than
## this exact number, so it's safe to retune without touching test coverage.
const WANDER_SPEED := 24.0  # pixels per second
const WANDER_RADIUS := 40.0  # drifts within roughly this many pixels of home
const DIRECTION_CHANGE_INTERVAL := 1.5  # seconds between picking a new heading


## A unit-length heading for a creature at `current`, home-anchored at `home`.
## Deterministic for (home, elapsed_time, seed): the same creature re-derives
## the same heading within a given DIRECTION_CHANGE_INTERVAL window rather
## than needing to store per-frame state. Once drifted past WANDER_RADIUS from
## home, the heading points back toward home instead of the pseudo-random pick.
func direction_at(home: Vector2, current: Vector2, elapsed_time: float, seed_value: int) -> Vector2:
	if current.distance_to(home) > WANDER_RADIUS:
		return (home - current).normalized()

	return roam_direction(elapsed_time, seed_value)


## A free exploration heading with no home bias: an interval-stable
## pseudo-random unit vector. Used when a creature is actively searching for
## food/water and should range outward rather than orbit its spawn point.
func roam_direction(elapsed_time: float, seed_value: int) -> Vector2:
	var interval_index := int(elapsed_time / DIRECTION_CHANGE_INTERVAL)
	var angle_seed := hash("%d_%d" % [seed_value, interval_index])
	var angle := float(angle_seed % 360) * PI / 180.0
	return Vector2(cos(angle), sin(angle))


## Advances `current` by one step of wander motion over `delta` seconds.
func step_position(
	home: Vector2, current: Vector2, elapsed_time: float, delta: float, seed_value: int
) -> Vector2:
	var direction := direction_at(home, current, elapsed_time, seed_value)
	return current + direction * WANDER_SPEED * delta
