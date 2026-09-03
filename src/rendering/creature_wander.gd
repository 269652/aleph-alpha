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

## Per-instance override for WANDER_RADIUS/WANDER_SPEED -- defaults to the
## module consts above, so every EXISTING caller (CreatureMarker, FishMarker
## with a live water world) is completely unaffected; only a caller that
## explicitly wants a different scale needs to touch these at all (see
## FishMarker.configure_wander, used by the character preview diorama's own
## tiny pond -- the real WANDER_RADIUS, 40 world units, comfortably exceeds
## the whole pond, and driving fish with a separate movement system instead
## of this one was reported live: "fish don't swim like in the real game").
var wander_radius := WANDER_RADIUS
var wander_speed := WANDER_SPEED


## How far out (as a MULTIPLE of WANDER_RADIUS) the pull toward home becomes
## total, leaving no roam component at all -- see direction_at.
const HOME_PULL_FULL_RADIUS_FACTOR := 1.5

## How wide the band where the outward component is progressively removed
## is, as a FRACTION of WANDER_RADIUS. The band sits just INSIDE the radius
## (from WANDER_RADIUS * (1 - this) out to WANDER_RADIUS), so that by the
## time a creature actually reaches the radius it already has no outward
## component left at all -- see direction_at.
const HOME_CONTAINMENT_BAND_FRACTION := 0.25


## A unit-length heading for a creature at `current`, home-anchored at `home`.
## Deterministic for (home, elapsed_time, seed): the same creature re-derives
## the same heading within a given DIRECTION_CHANGE_INTERVAL window rather
## than needing to store per-frame state.
##
## Staying near home is done by CONTAINMENT, not by a tug of war: as the
## creature approaches WANDER_RADIUS its heading's outward radial component
## is progressively projected away (the same "strip the component pointing
## where you shouldn't go" shape as ThreatAvoidantWander.away_biased_step),
## so at the radius it can only travel tangentially or inward. Past the
## radius a genuine inward pull eases in on top, reaching fully homeward by
## HOME_PULL_FULL_RADIUS_FACTOR x the radius, so a creature that somehow
## ends up far out (spawned, knocked back) still comes home rather than
## circling forever.
##
## Both earlier approaches BLENDED an outward roam against an inward pull,
## and both chattered, because opposing vectors cancel: normalizing a
## near-zero blend amplifies sub-pixel position noise into a full-speed
## reversal. The first version switched hard at the radius (outward roam,
## snap home, back inside, outward roam again -- a frame-rate limit cycle);
## easing the blend just moved the cancellation to wherever the two forces
## balanced, measured sitting at distance 49.7<->50.1 flipping every single
## frame. Downstream either one read as a legged animal flipping its drawn
## facing every other frame, since CreatureMarker flips immediately off the
## requested direction's own x sign (reported: "now it constantly flips back
## and forth"; measured at 800 flips per 1800 frames, see
## test_a_wandering_creature_does_not_rapidly_flip_its_facing). Containment
## has no cancellation to be ill-conditioned about: once the outward
## component is gone, the remaining heading and the inward pull are at worst
## perpendicular, never opposed. Shared by fish too (FishMarker), which had
## the same latent chatter.
## `radius` is a PER-CALL override of the instance's own wander_radius --
## negative (the default) means "not supplied", falling back to
## wander_radius so every existing caller (which never passes this
## argument at all) reproduces today's exact heading. A caller that wants a
## containment distance that changes call-to-call (a juvenile widening its
## range as it grows, see CreatureMarker._wander_radius) passes it here
## instead of writing it into the shared instance field first, which would
## be indistinguishable from a genuine persistent override like
## FishMarker.configure_wander's (see wander_radius's own "Per-instance
## override" doc comment above).
func direction_at(
	home: Vector2, current: Vector2, elapsed_time: float, seed_value: int, radius: float = -1.0
) -> Vector2:
	var effective_radius := wander_radius if radius < 0.0 else radius
	var roam := roam_direction(elapsed_time, seed_value)
	var to_home := home - current
	var distance := to_home.length()
	if distance < 0.001:
		return roam
	var inward := to_home / distance
	var outward := -inward

	var band := effective_radius * HOME_CONTAINMENT_BAND_FRACTION
	var containment := clampf((distance - (effective_radius - band)) / band, 0.0, 1.0)
	var outward_amount := maxf(0.0, roam.dot(outward))
	var contained := roam - outward * outward_amount * containment
	if contained.length() < 0.001:
		# Roam pointed dead outward and was fully contained away -- slide
		# along the boundary rather than stalling.
		contained = Vector2(-outward.y, outward.x)

	if distance <= effective_radius:
		return contained.normalized()

	var pull_span := effective_radius * (HOME_PULL_FULL_RADIUS_FACTOR - 1.0)
	var pull := clampf((distance - effective_radius) / pull_span, 0.0, 1.0)
	# Safe to lerp here: `contained` has no outward component left at this
	# distance (containment is already 1.0), so it and `inward` are at worst
	# perpendicular -- they cannot cancel.
	return contained.normalized().lerp(inward, pull).normalized()


## What share of direction-change intervals are grazing PAUSES rather than
## walks (see is_pausing). Pinned by
## test_roughly_the_pause_fraction_of_intervals_are_pauses.
const PAUSE_FRACTION := 0.3


## Whether this interval is a standing pause: continuous, never-resting
## drift reads as mechanical (reported: "it doesn't look like natural
## wandering or foraging") -- real animals stop, look around, and graze
## between short walks. Deterministic per (seed, interval) like every other
## wander decision. Consulted by CreatureMarker's ordinary-wander path only:
## searching for a needed resource, seeking, and fleeing never pause.
func is_pausing(elapsed_time: float, seed_value: int) -> bool:
	var interval_index := int(elapsed_time / DIRECTION_CHANGE_INTERVAL)
	var roll := hash("%d_%d_pause" % [seed_value, interval_index]) % 1000
	return float(roll) < PAUSE_FRACTION * 1000.0


## A free exploration heading with no home bias: an interval-stable
## pseudo-random unit vector. Used when a creature is actively searching for
## food/water and should range outward rather than orbit its spawn point.
func roam_direction(elapsed_time: float, seed_value: int) -> Vector2:
	var interval_index := int(elapsed_time / DIRECTION_CHANGE_INTERVAL)
	var angle_seed := hash("%d_%d" % [seed_value, interval_index])
	var angle := float(angle_seed % 360) * PI / 180.0
	return Vector2(cos(angle), sin(angle))


## Advances `current` by one step of wander motion over `delta` seconds.
## `radius` is forwarded to direction_at as-is -- see its own doc comment.
func step_position(
	home: Vector2, current: Vector2, elapsed_time: float, delta: float, seed_value: int,
	radius: float = -1.0
) -> Vector2:
	var direction := direction_at(home, current, elapsed_time, seed_value, radius)
	return current + direction * wander_speed * delta
