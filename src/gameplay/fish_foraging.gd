extends RefCounted

## Pure aquatic-foraging target-finding -- see docs/concept/
## aquatic_foraging.md. Mirrors FishSchooling's own shape exactly: a
## handful of pure static functions FishMarker calls into each frame, not
## an instantiated behaviour object -- the fish system's own established
## pattern, not the land-animal XForageBehavior state-machine convention
## this file has never used.

## How far (in tiles) a fish notices a real vegetation patch worth
## swimming to -- short: a fish forages what is genuinely near its own
## current position, the same "an ant's own forage reach is far smaller
## than a mouse's whole home range" shortest-reach reasoning
## AntColony.FORAGE_RADIUS_TILES already applies to a much smaller animal
## foraging much closer to home.
const DETECTION_RADIUS_TILES := 6.0

## How close counts as "arrived" at a vegetation patch -- close enough to
## graze it. Mirrors DecomposerMarker.ARRIVE_DISTANCE_PX's own small,
## tiny-creature arrival tolerance.
const GRAZE_ARRIVE_DISTANCE_PX := 6.0

## How often a foraging fish re-queries for a nearby patch, rather than
## every frame -- the same "don't repeat a nontrivial per-chunk scan every
## single frame for every fish" performance discipline FishSchooling.
## SCAN_INTERVAL already applies to its own (unrelated) neighbour scan.
## Pinned independently rather than reusing that constant directly: the two
## are separate mechanisms that happen to share a cadence, not one concept,
## the same "independently define, even when the reasoning is shared"
## precedent DETECTION_RADIUS_TILES's own doc comment already sets against
## AntColony.FORAGE_RADIUS_TILES above.
const SCAN_INTERVAL := 0.5


## The nearest position in `candidates` (an Array of {"position": Vector2}
## dictionaries, the same shape EarthChunkManager.worms_near/
## aquatic_vegetation_near already return) to `position`, or null if
## `candidates` is empty. Pure geometry -- independently testable without
## a real EarthChunkManager, mirroring DecomposerMarker._nearest_food's
## own "nearest in reach" shape as a standalone function instead.
static func nearest_target(position: Vector2, candidates: Array):
	if candidates.is_empty():
		return null
	var nearest: Vector2 = candidates[0]["position"]
	var nearest_distance := position.distance_to(nearest)
	for candidate in candidates:
		var candidate_position: Vector2 = candidate["position"]
		var distance := position.distance_to(candidate_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate_position
	return nearest
