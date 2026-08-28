extends RefCounted

const AnimalFitness = preload("res://src/world/animal_fitness.gd")
static var _fitness := AnimalFitness.new()

## Land-mammal courtship: two eligible animals noticing each other, walking
## together, and lingering near each other for a real duration before
## reproduction actually fires (see docs/concept/ecosystem_dynamics.md's
## "Courtship, and where births come from"). This is the walking-quadruped
## counterpart to Courtship, which is pollinators-only -- its tight
## synchronized-orbit flutter is a butterfly's courtship flight and reads as
## a bird (or a horse) glitching in place, exactly the bug Courtship.dances()
## already exists to prevent for birds.
##
## Reuses Courtship's PAIRING primitives directly rather than duplicating
## them -- can_pair/pair_seed/mates/leads are already id-based and
## species-agnostic, so "which two individuals, who leads, did it take"
## resolve the same way regardless of body plan (see World._pair_up_
## courtships / _advance_courtships / _resolve_courtship, which call
## Courtship's statics directly). Only the DANCE motion (dance_offset) and
## the species gate (Courtship.dances/can_court, both keyed to
## DANCING_SPECIES) are pollinator-only and are deliberately NOT reused here.
##
## Pure and engine-free, like the rest of the behaviour modules: this module
## only answers "how close is close enough" and "how long is long enough" and
## "which candidate is nearest" -- actually walking a creature toward its
## partner is CreatureMarker's job (via CreatureBehavior's "court" intent),
## the same split GrazerForaging/FoodConsumption use for feeding.

## How long a paired-up pair must actually stand together before the pairing
## resolves. Several World.REPRODUCTION_INTERVAL ticks -- long enough that a
## player watching sees two animals genuinely walk toward and stay near each
## other, not a single-frame swap (the same complaint that motivated
## Courtship.DANCE_SECONDS for pollinators) -- but nowhere near LifeCycle's
## wall-clock REAL-DAY stages: courtship itself is meant to be a common,
## watchable sight, same as the pollinator dance. What it LEADS to stays rare
## and slow via AnimalReproduction.REPRO_COOLDOWN (a full real day before a
## creature is even eligible again), which this duration does not shorten or
## replace.
const COURTSHIP_SECONDS := 15.0

## How close two courting animals must close the distance to before they stop
## walking and simply stand together -- roughly the same body-length scale
## World already treats as "sharing one spot" (see OFFSPRING_SCATTER, the
## spread used to place a newborn beside its parent). Comfortably inside
## World.NEIGHBOUR_RADIUS_PX (the radius that found them each other in the
## first place, see nearest_partner_index/World._find_courtship_partner), so
## the pair visibly closes real distance instead of starting already
## "arrived" (pinned by test_linger_radius_is_comfortably_inside_the_
## neighbour_radius).
const LINGER_RADIUS_PX := 18.0


## Whether a courting pair should keep walking toward each other. False once
## they are close enough to simply stand together (see LINGER_RADIUS_PX).
static func should_approach(distance_between: float) -> bool:
	return distance_between > LINGER_RADIUS_PX


## Whether `elapsed` seconds of a pair lingering together is enough for the
## courtship to resolve (mate-or-not is decided separately, by Courtship.mates).
static func courtship_complete(elapsed: float) -> bool:
	return elapsed >= COURTSHIP_SECONDS


## Index of the nearest eligible partner within `radius` of `position`, or -1
## if nobody qualifies. Mirrors FoodConsumption.nearest_food_index's own
## shape exactly: the caller (World._find_courtship_partner) owns which NODES
## even count as candidates in the first place (same species, individually
## eligible via AnimalReproduction.can_reproduce, not already courting, a
## genuinely different individual via Courtship.can_pair) -- this only picks
## the nearest of whatever candidate positions it's handed.
static func nearest_partner_index(position: Vector2, candidate_positions: Array, radius: float) -> int:
	var best_index := -1
	var best_distance := INF
	for i in candidate_positions.size():
		var distance: float = position.distance_to(candidate_positions[i])
		if distance <= radius and distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


## Index of the MOST ATTRACTIVE eligible partner within `radius` of
## `position` (AnimalFitness's first real caller -- see docs/concept/
## ecosystem_dynamics.md's "Land-mammal courtship"), or -1 if nobody
## qualifies.
##
## Distance is checked FIRST, exactly like nearest_partner_index, and
## attractiveness only ranks whatever survives that filter -- deliberately
## NOT an unbounded global search ranked by attractiveness alone. A highly
## attractive mate three chunks away is not reachable: a real animal courts
## from whoever is actually nearby, it does not sense the fittest individual
## in the whole population and travel to it. So this is a bounded nudge
## around the existing "who's even in range" gate, not a replacement of
## it -- same shape as nearest_partner_index, with the tie-break rule
## swapped from "closest" to "most attractive to me" once the candidate
## pool is fixed.
static func most_attractive_partner_index(
	own_phenotype: Dictionary,
	position: Vector2,
	candidate_positions: Array,
	candidate_phenotypes: Array,
	radius: float
) -> int:
	var best_index := -1
	var best_attractiveness := -1.0
	for i in candidate_positions.size():
		var distance: float = position.distance_to(candidate_positions[i])
		if distance > radius:
			continue
		var attractiveness: float = _fitness.mate_attractiveness(
			own_phenotype, candidate_phenotypes[i]
		)
		if attractiveness > best_attractiveness:
			best_attractiveness = attractiveness
			best_index = i
	return best_index
