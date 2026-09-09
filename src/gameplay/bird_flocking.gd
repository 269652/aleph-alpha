extends RefCounted

## Sparrow-to-sparrow flocking: approach, follow (heading-match), and avoid,
## by distance to the single nearest same-species flockmate (see
## docs/concept/soil_fauna.md's "Sparrows flock, robins don't"). Reported
## live: "make sparrows build flocks and hang around in groups? maybe
## increase their number slightly" (see AmbientFlyerRenderer.MAX_SPARROWS_
## PER_CHUNK for the population half of that request).
##
## Mirrors FishSchooling's own ZONAL MODEL exactly (Aoki 1982; Huth & Wissel
## 1992): a flocking bird reacts to its nearest neighbour purely by
## distance, through three concentric zones -- repulsion (too close: peel
## away), orientation (a comfortable middle distance: match heading, i.e.
## follow), and attraction (far but still noticed: fly toward). No
## coordination between birds is modeled or needed -- each bird runs this
## same function against its own single nearest neighbour and a real
## flock's shape falls out of that alone (docs/concept/ecosystem_dynamics.
## md's "A shoal finds its shape" makes the identical point for fish: "give
## every individual the same independent reaction and the group behaviour
## emerges for free"; docs/concept/animal_husbandry.md's herding section
## says it again for herds: "do not build a herding AI").
##
## Deliberately WITHOUT FishSchooling's play-chase extra -- not asked for
## here, and a fish-specific flourish rather than part of the zonal model
## itself. Deliberately its OWN module rather than a shared base class with
## FishSchooling: this codebase's own convention for small per-species
## behavior modules (see MillipedeMarker/DecomposerMarker/AntForagerMarker
## each independently duplicating _lod_step rather than sharing one) is
## small, self-contained modules over cross-cutting shared bases.
##
## Gated by SPECIES (FLOCKS below), not a separate marker class:
## AmbientFlyerMarker.BEHAVIOR_TREE_SPECIES/FLYER_RANGE/FlyerDiet.
## DIET_BY_SPECIES already establish that a species is a lookup consulted
## by the one shared marker class, never a code branch (see soil_fauna.md's
## design pillar 2, "diet is a property of the species, not of the code
## path") -- flocking follows the same rule.

const GroundSlide = preload("res://src/gameplay/ground_slide.gd")

## Real average house sparrow body length (bill to tail), meters --
## converted via GroundSlide.PX_PER_METER, the same real-world-to-world-px
## idiom this codebase already uses for every other body-scale constant
## (see that class's own doc comment), rather than borrowing FishSchooling's
## own FISH_BODY_LENGTH_PX, an unrelated species' scale.
const SPARROW_BODY_LENGTH_METERS := 0.15
const SPARROW_BODY_LENGTH_PX := SPARROW_BODY_LENGTH_METERS * GroundSlide.PX_PER_METER

## The same three zonal multiples FishSchooling uses -- the zonal model's
## own 1/4/10 body-length ratios are a general result of the schooling/
## flocking literature cited above, not fish-specific, so only the base
## body length is re-derived for a sparrow's real scale.
const REPULSION_BODY_LENGTHS := 1.0
const ORIENTATION_BODY_LENGTHS := 4.0
const ATTRACTION_BODY_LENGTHS := 10.0

const REPULSION_RADIUS_PX := SPARROW_BODY_LENGTH_PX * REPULSION_BODY_LENGTHS
const ORIENTATION_RADIUS_PX := SPARROW_BODY_LENGTH_PX * ORIENTATION_BODY_LENGTHS
const ATTRACTION_RADIUS_PX := SPARROW_BODY_LENGTH_PX * ATTRACTION_BODY_LENGTHS

## Which species actually flock -- currently sparrows only. Robins (and
## blackbirds) are deliberately excluded: a real European robin is famously
## territorial and solitary outside a mated pair, the opposite disposition
## from a real house sparrow. A data set, not a hardcoded single-species
## check, so a future flocking species (starlings, geese) is one entry, not
## a new code path.
const FLOCKS: Array[String] = ["sparrow"]

static func flocks(species: String) -> bool:
	return FLOCKS.has(species)


## The steering this bird should apply because of ONE neighbour at
## `neighbor_position` (heading `neighbor_heading`, pass Vector2.ZERO if
## unknown/still) -- a unit vector, or Vector2.ZERO if the neighbour is
## outside ATTRACTION_RADIUS_PX altogether (too far to matter) or exactly
## overlapping (no direction to give). AmbientFlyerMarker blends this
## straight into the same wander-heading machinery its carry/scent
## steering already goes through, so it is never normalized to anything
## other than unit length or zero.
static func steering_for_neighbor(
	own_position: Vector2, neighbor_position: Vector2, neighbor_heading: Vector2
) -> Vector2:
	var offset := neighbor_position - own_position
	var distance := offset.length()
	if distance < 0.001:
		return Vector2.ZERO  # exactly overlapping: no direction to avoid toward
	if distance < REPULSION_RADIUS_PX:
		return -offset / distance  # avoid: peel away
	if distance < ORIENTATION_RADIUS_PX:
		if neighbor_heading.length() > 0.001:
			return neighbor_heading.normalized()  # follow: match heading
		return offset / distance  # a still/unknown-heading neighbor: drift toward it instead
	if distance < ATTRACTION_RADIUS_PX:
		return offset / distance  # approach: fly toward
	return Vector2.ZERO  # outside perception range entirely


## How often (seconds) a flocking bird re-scans for its nearest flockmate.
## Mirrors FishSchooling.SCAN_INTERVAL's own cadence and reasoning exactly:
## a full neighbour scan every frame for every bird is exactly the shape of
## cost that caused this project's own fish/is_river_at_global and
## AmbientFlyerMarker._scan_for_partners performance regressions (see
## project history) -- re-scanning a few times a second instead of every
## frame is imperceptible for a bird that is mostly just wandering anyway.
const SCAN_INTERVAL := 0.5

## How far (as a multiple of a bird's own wander radius) a flockmate is
## allowed to pull it from home before flocking is ignored in favour of
## ordinary wander -- mirrors FishSchooling.SCHOOL_LEASH_RADIUS_FACTOR's
## own reasoning exactly: without this, a bird could in principle keep
## closing on a flockmate that itself keeps drifting, indefinitely, away
## from where either of them actually lives.
const FLOCK_LEASH_RADIUS_FACTOR := 3.0
