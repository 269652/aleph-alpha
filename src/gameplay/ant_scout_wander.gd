extends RefCounted

## Biases an ant scout's own ambient wander heading toward a LOCALLY-sensed
## pheromone trail, when one exists (see docs/concept/soil_fauna.md's
## "Scouting: real search, not omniscient dispatch"). Real ant trail-
## following is chemotaxis: an ant senses a concentration gradient exactly
## where it currently stands and turns toward it -- it does not compare a
## list of known candidate destinations from afar (that omniscient-list
## shape is exactly what `PheromoneField.best_candidate_index` used to do,
## and exactly what a scout replaces it with here).
##
## A pure post-process on an already-computed candidate heading, mirroring
## ThreatAvoidantWander's own shape exactly -- so AmbientFlyerMovement
## itself (the shared, already hard-won wander primitive several OTHER
## species depend on: birds, DecomposerMarker's own ants/bugs) never needs
## touching for this one extra, ant-specific need. Pure vector math, no
## nodes -- testable without a running creature.

## How strongly a real, LOCALLY-sensed trail bends this scout's own
## exploration heading, once sensed at all -- 1.0 would follow the trail
## with total certainty (no exploration left once ANY trail exists,
## however faint), 0.0 would make sensing a trail meaningless. Chosen as a
## strong-but-not-absolute bend: a real ant that crosses a trail while
## scouting turns noticeably onto it (this is the whole recruitment
## effect), but does not instantly snap onto a perfectly straight line the
## way an omniscient "go exactly there" dispatch would -- it still keeps
## walking, just now strongly favouring the trail's own direction. Pinned
## by test_trail_bias_is_pinned, not eyeballed in the math below.
const TRAIL_BIAS := 0.7


## `wander_heading`: this scout's own ambient roam heading (see
## AmbientFlyerMovement.direction_at), already unit-length. `gradient`: the
## LOCAL pheromone gradient at the scout's OWN current position (see
## PheromoneField.gradient_direction) -- Vector2.ZERO where nothing is
## sensed there (that field's own "nothing to sense" contract), in which
## case this returns wander_heading completely unchanged: real
## exploration, nothing to bias toward.
static func biased_heading(wander_heading: Vector2, gradient: Vector2) -> Vector2:
	return _lerped_heading(wander_heading, gradient, TRAIL_BIAS)


## How gently a scout's own ASSIGNED sector (see spread_heading's own doc
## comment) nudges its wander heading -- deliberately far weaker than
## TRAIL_BIAS: an assigned sector is not a real discovery, just a
## diversity nudge so several scouts dispatched together fan out rather
## than converging on near-identical paths (reported live: "other ants
## follow him in a line even when nothing has been discovered yet"). A
## real sensed trail (TRAIL_BIAS) must always be able to override it
## outright -- pinned by test_spread_heading_bias_is_gentler_than_real_
## trail_bias, not just asserted by convention.
const SPREAD_BIAS := 0.3


## `assigned_direction`: this scout's own dispatch-time assigned sector
## (see EarthChunkManager's own scout-wave dispatch, which spreads several
## scouts' assigned directions evenly around a circle) -- Vector2.ZERO for
## a scout dispatched alone (or any caller with nothing to spread against),
## in which case this returns wander_heading unchanged, same "nothing to
## bias toward" contract biased_heading's own gradient parameter has.
static func spread_heading(wander_heading: Vector2, assigned_direction: Vector2) -> Vector2:
	return _lerped_heading(wander_heading, assigned_direction, SPREAD_BIAS)


static func _lerped_heading(wander_heading: Vector2, bias_direction: Vector2, weight: float) -> Vector2:
	if bias_direction == Vector2.ZERO:
		return wander_heading
	var blended := wander_heading.lerp(bias_direction, weight)
	if blended.length() < 0.0001:
		# wander_heading and bias_direction point almost exactly opposite --
		# lerp degenerates toward zero exactly at the midpoint. Break the
		# tie with a perpendicular nudge (same "never return a dead zero
		# vector" reasoning ThreatAvoidantWander.away_biased_step already
		# uses) rather than propagate a non-unit-length NaN-prone result.
		return Vector2(-bias_direction.y, bias_direction.x)
	return blended.normalized()
