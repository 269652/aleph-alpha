extends RefCounted

## Fish-to-fish social behavior: approach, follow (heading-match), avoid, and
## an occasional playful chase (see
## docs/concept/ecosystem_dynamics.md#a-shoal-finds-its-shape).
##
## Grounded in the classic ZONAL MODEL of fish schooling (Aoki 1982; Huth &
## Wissel 1992): a shoaling fish reacts to its nearest neighbour purely by
## distance, through three concentric zones -- repulsion (too close: swim
## away), orientation (a comfortable middle distance: match heading, i.e.
## follow), and attraction (far but still noticed: swim toward). No
## coordination between fish is modeled or needed -- each fish runs this same
## function against its own single nearest neighbour and a real shoal's shape
## falls out of that alone (docs/concept/animal_husbandry.md's herding
## section makes the identical point: "do not build a herding AI").
##
## Pure and engine-free like CreatureBehavior/ThreatAvoidantWander --
## FishMarker gathers the nearest schoolmate and its heading, this decides
## what to do about it.

## A fish's own body length, in world px. FishMarker.CLEARANCE_PX is
## documented there as "roughly the sprite's half-extent", so a full body
## length is twice that -- restated here rather than imported (importing
## FishMarker here would be circular, since FishMarker imports THIS module)
## and cross-checked directly by
## test_fish_schooling.gd's test_body_length_constant_matches_fish_markers_
## own_clearance_diameter, not left to drift as an unchecked comment.
const FISH_BODY_LENGTH_PX := 12.0

## Real shoaling fish hold their nearest neighbour at roughly 0.5-1 body
## length -- close enough to benefit from the group, not so close they
## collide. Below this, a fish peels away (avoid).
const REPULSION_BODY_LENGTHS := 1.0
## The "parallel orientation" band: several body lengths, where a fish
## matches its neighbour's heading rather than closing or opening the gap --
## the literal mechanism behind a shoal appearing to swim "together" without
## any of them aiming at each other (follow).
const ORIENTATION_BODY_LENGTHS := 4.0
## The outer edge of what a fish notices at all -- several to around ten body
## lengths in the literature, depending on turbidity/species. Beyond this a
## fish outside the shoal has no reaction to it at all; inside it but outside
## the orientation band, it is drawn back toward the shoal (approach).
const ATTRACTION_BODY_LENGTHS := 10.0

const REPULSION_RADIUS_PX := FISH_BODY_LENGTH_PX * REPULSION_BODY_LENGTHS
const ORIENTATION_RADIUS_PX := FISH_BODY_LENGTH_PX * ORIENTATION_BODY_LENGTHS
const ATTRACTION_RADIUS_PX := FISH_BODY_LENGTH_PX * ATTRACTION_BODY_LENGTHS


## The steering this fish should apply because of ONE neighbour at
## `neighbor_position` (heading `neighbor_heading`, pass Vector2.ZERO if
## unknown/still) -- a unit vector, or Vector2.ZERO if the neighbour is
## outside ATTRACTION_RADIUS_PX altogether (too far to matter) or exactly
## overlapping (no direction to give). FishMarker blends this straight into
## the same turn-toward-target heading machinery its wander/attraction/bolt
## targets already go through, so it is never normalized to anything other
## than unit length or zero.
static func steering_for_neighbor(
	own_position: Vector2, neighbor_position: Vector2, neighbor_heading: Vector2
) -> Vector2:
	var offset := neighbor_position - own_position
	var distance := offset.length()
	if distance < 0.001:
		return Vector2.ZERO  # exactly overlapping: no direction to avoid toward
	if distance < REPULSION_RADIUS_PX:
		return -offset / distance  # avoid: swim directly away
	if distance < ORIENTATION_RADIUS_PX:
		if neighbor_heading.length() > 0.001:
			return neighbor_heading.normalized()  # follow: match heading
		return offset / distance  # a still/unknown-heading neighbor: drift toward it instead
	if distance < ATTRACTION_RADIUS_PX:
		return offset / distance  # approach: swim toward
	return Vector2.ZERO  # outside perception range entirely


## How often (seconds) a fish re-scans for its nearest schoolmate. Mirrors
## AmbientFlyerMarker.PARTNER_SEARCH_INTERVAL's own cadence, for the same
## reason: a full group scan every frame for every fish is exactly the shape
## of cost that caused this project's own fish/is_river_at_global performance
## regression (see FishMarker's own perf history in project memory) --
## re-scanning a few times a second instead of every frame is imperceptible
## for a slow-drifting fish.
const SCAN_INTERVAL := 0.5

## How far (as a multiple of a fish's own wander radius) a schoolmate is
## allowed to pull it from home before schooling is ignored in favour of
## ordinary wander -- without this, a fish could in principle keep closing on
## a schoolmate that itself keeps drifting, indefinitely, away from where
## either of them actually lives. A generous multiple, not a tight leash:
## real shoal cohesion legitimately carries a fish beyond its own solitary
## home range; this only catches the unbounded case, mirroring the
## butterfly-dance's own leash-past-a-radius shape.
const SCHOOL_LEASH_RADIUS_FACTOR := 3.0


## Whether this is one of the rare intervals a fish attempts a playful chase
## at its current schoolmate, instead of the ordinary steady approach/follow/
## avoid above. Real shoaling fish are observed to burst-chase a schoolmate
## as investigatory/social behaviour distinct from feeding, aggression or
## fleeing; modeled here as a low, deterministic, per-interval chance, the
## same hash-roll shape as CreatureWander.is_pausing -- deterministic so the
## same fish re-checking the same interval always gets the same answer.
const PLAY_CHANCE := 0.05

static func rolls_for_play(seed_value: int, interval_index: int) -> bool:
	var roll := hash("%d_%d_play" % [seed_value, interval_index]) % 1000
	return float(roll) < PLAY_CHANCE * 1000.0

## How long a playful chase burst lasts before this fish settles back into
## ordinary schooling.
const PLAY_CHASE_SECONDS := 2.0
