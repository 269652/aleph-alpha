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
	if gradient == Vector2.ZERO:
		return wander_heading
	var blended := wander_heading.lerp(gradient, TRAIL_BIAS)
	if blended.length() < 0.0001:
		# wander_heading and gradient point almost exactly opposite -- lerp
		# degenerates toward zero exactly at the midpoint. Break the tie
		# with a perpendicular nudge (same "never return a dead zero
		# vector" reasoning ThreatAvoidantWander.away_biased_step already
		# uses) rather than propagate a non-unit-length NaN-prone result.
		return Vector2(-gradient.y, gradient.x)
	return blended.normalized()
