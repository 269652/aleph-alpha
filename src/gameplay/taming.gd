extends RefCounted

## Taming: the rules for catching an animal with a lasso, holding it while it
## fights, and winning it over by feeding it (see docs/concept/taming.md).
##
## Pure and engine-free -- no nodes, no RNG held here -- so the whole
## capture-and-trust cycle is unit-testable headlessly. The same split as
## GrazerForaging and GroundForageBehavior: this decides WHAT the numbers are
## and WHETHER a thing may happen; the caller (CreatureMarker / the player's
## lasso interaction) owns the world state it applies to.

const CreatureInfo = preload("res://src/world/creature_info.gd")


# -- breaking free -----------------------------------------------------------

## Chance in [0,1] that a restrained animal breaks the rope on ONE attempt.
##
## Note what this is NOT: the chance of getting away. Attempts repeat every
## CreatureMarker.STRUGGLE_INTERVAL, so a per-attempt chance compounds fast --
## the first version of this used 0.85 here, reasoning that "a healthy animal
## usually wins", and the result was ~99.9% escape within a few seconds and
## every animal getting away every single time (reported: "both horses and
## deer always break free").
##
## The quantity a player actually experiences is hold_chance() below -- the
## odds across the whole struggle -- so that is what is pinned by tests, and
## these two numbers are chosen to produce it. Change them by checking what
## hold_chance does, never by eye.
const MAX_BREAK_FREE_CHANCE := 0.22
const MIN_BREAK_FREE_CHANCE := 0.05


static func break_free_chance(condition: float) -> float:
	return lerpf(MIN_BREAK_FREE_CHANCE, MAX_BREAK_FREE_CHANCE, clampf(condition, 0.0, 1.0))


## Stamina spent per failed struggle, and how long a rested animal takes to
## get it back.
##
## Fighting the rope TIRES an animal; it does not injure it. The spec always
## said stamina (see docs/concept/taming.md) but the first implementation took
## it out of health, which meant a successful catch handed the player a
## nearly-dead horse as its prize, and an animal that escaped stayed maimed.
const STRUGGLE_FATIGUE := 0.25
const FATIGUE_RECOVERY_SECONDS := 45.0


static func fatigue_after_struggle(fatigue: float) -> float:
	return minf(1.0, fatigue + STRUGGLE_FATIGUE)


static func fatigue_after_rest(fatigue: float, rested_seconds: float) -> float:
	return maxf(0.0, fatigue - rested_seconds / FATIGUE_RECOVERY_SECONDS)


## Whether the animal has fought itself to a standstill and stopped fighting.
##
## This is how breaking an animal actually works -- it fights the restraint
## until it has nothing left, and then accepts it -- and mechanically it is
## what makes the rest of taming possible. Without it an exhausted animal goes
## on rolling the floor chance every STRUGGLE_INTERVAL forever, so a horse
## tied to a tree while the player walks off to find carrots is certain to be
## gone by the time they get back, and taming can never be completed.
static func has_given_up(fatigue: float) -> bool:
	return fatigue >= 1.0


## How hard an animal is fighting right now: how healthy it is, scaled down by
## how tired it already is.
static func effective_condition(health_fraction: float, fatigue: float) -> float:
	return clampf(health_fraction, 0.0, 1.0) * (1.0 - clampf(fatigue, 0.0, 1.0))


## An ESTIMATE of the odds of still holding an animal that started at
## `condition` once it has fought itself to a standstill, by walking the
## struggle-and-tire chain.
##
## Deliberately labelled an estimate: it reads optimistic against what the
## game actually does (0.48 here versus a measured 0.32 for a fresh
## full-health horse), because the live struggle gets more rolls in than this
## idealised chain accounts for. It is kept for SHAPE -- monotonic in
## condition, a probability, worn-down animals far easier to hold -- and the
## authority on the actual rate is
## test_the_measured_catch_rate_matches_the_model, which runs sixty real
## animals through a real capture. Tune MAX_BREAK_FREE_CHANCE against that
## measurement, never against this.
static func hold_chance(condition: float) -> float:
	var held := 1.0
	var fatigue := 0.0
	# Bounded by how many struggles it takes to exhaust an animal completely.
	for _i in int(ceil(1.0 / STRUGGLE_FATIGUE)) + 1:
		held *= 1.0 - break_free_chance(effective_condition(condition, fatigue))
		fatigue = fatigue_after_struggle(fatigue)
	return held


# -- trust -------------------------------------------------------------------

## Trust runs 0 (wild) to TAME_TRUST (fully tame). Expressed as a unit scale
## like every other condition value in the sim (see AnimalReproduction.energy,
## CreatureNeeds).
const TAME_TRUST := 1.0

## What one meal is worth when the animal actually wanted it. Chosen so
## taming takes a handful of feeds rather than one (which would make the
## lasso the whole system) or dozens (which would make it a grind) -- pinned
## as the resulting COUNT by test_it_takes_several_hungry_feeds_to_tame_an_animal,
## not as this number.
const TRUST_PER_FEED := 0.2


static func starting_trust() -> float:
	return 0.0


## Feeding only counts when the animal is actually hungry.
##
## This is the rule the whole system rests on. Without it, taming is spamming
## carrots at a standing animal; with it, taming is paced by the animal's own
## hunger clock (CreatureNeeds), so it happens across real play time -- turn
## up, feed, come back later -- which is what makes it read as a relationship
## rather than a purchase.
static func trust_after_feeding(trust: float, is_hungry: bool) -> float:
	if not is_hungry:
		return trust
	return minf(TAME_TRUST, trust + TRUST_PER_FEED)


## How long an animal may be left restrained and hungry before it starts
## losing faith, and how fast it then goes. Long enough that ordinary play --
## walking off to find carrots -- is never punished; short enough that
## abandoning a tied animal undoes the work.
const NEGLECT_SECONDS := 600.0
const TRUST_LOST_PER_NEGLECT_PERIOD := TRUST_PER_FEED


## Trust after `hungry_seconds` of being left hungry. Neglect is not neutral:
## an animal tied up and ignored ends up less tame than it was.
static func trust_after_neglect(trust: float, hungry_seconds: float) -> float:
	if hungry_seconds < NEGLECT_SECONDS:
		return trust
	var periods := hungry_seconds / NEGLECT_SECONDS
	return maxf(0.0, trust - TRUST_LOST_PER_NEGLECT_PERIOD * periods)


static func is_tame(trust: float) -> bool:
	return trust >= TAME_TRUST


# -- what a tamed animal will do ---------------------------------------------

## What a tamed animal has been told to do. Two orders, cycled by one key --
## a tamed animal is either coming with you or waiting where you left it, and
## a longer menu would be a menu for its own sake.
const ORDER_FOLLOW := 0
const ORDER_STAY := 1


static func next_order(order: int) -> int:
	return ORDER_STAY if order == ORDER_FOLLOW else ORDER_FOLLOW


## How fast the player travels while riding.
##
## Faster than walking, or taming a horse buys the player nothing -- but this
## is a world made of real geography to travel THROUGH (see
## concept/exploration.md), not to blur past, so a horse at a working trot
## rather than a gallop. Pinned as a ratio against Player.BASE_SPEED by
## test_riding_is_faster_than_walking.
const MOUNTED_SPEED := 150.0

## How far an individual horse's own fitness (see AnimalFitness.fitness_score)
## pulls its mounted speed away from the MOUNTED_SPEED baseline -- pets.md's
## own pillar: the same fitness dimension that makes a wild animal strong in
## the ecosystem sim is what makes it good to keep, so a genuinely fitter,
## more agile individual is a genuinely faster ride. Bounded to a real range
## rather than an unbounded scale: a fit riding horse reads as noticeably
## quicker than an average one, not a different creature entirely, so even the
## least-fit tameable horse stays well worth riding over walking and even the
## fittest stays well short of absurd (both ends pinned by
## test_mounted_speed_stays_within_a_real_bounded_range).
const MIN_FITNESS_SPEED_MULTIPLIER := 0.8
const MAX_FITNESS_SPEED_MULTIPLIER := 1.2


## Mounted speed for a horse with this fitness_score (see AnimalFitness). The
## multiplier range above is centered on 1.0, so the population's median
## fitness (0.5 -- AnimalFitness's three traits are each drawn uniformly in
## [0,1]) lands exactly on MOUNTED_SPEED: mounting an "ordinary" horse rides
## exactly as before this per-individual variation existed, not faster or
## slower on average (test_mounted_speed_at_the_population_median_fitness_is_
## the_flat_baseline).
static func mounted_speed_for(fitness_score: float) -> float:
	var multiplier := lerpf(
		MIN_FITNESS_SPEED_MULTIPLIER, MAX_FITNESS_SPEED_MULTIPLIER, clampf(fitness_score, 0.0, 1.0)
	)
	return MOUNTED_SPEED * multiplier


## Orders (follow / stay / mount) are for a fully tamed animal only. A
## half-trusting animal is still one you are holding by a rope.
static func accepts_orders(trust: float) -> bool:
	return is_tame(trust)


## Species that could plausibly carry a person. A tamed boar follows and
## stays; it is not a horse.
const RIDABLE_SPECIES := {"horse": true}


static func can_be_mounted(species: String) -> bool:
	return RIDABLE_SPECIES.has(species)


static func is_mountable(species: String, trust: float) -> bool:
	return can_be_mounted(species) and accepts_orders(trust)


## Whether a rope and a carrot are the right tools for this animal at all.
## Predators are not: being hunted by the thing you tied up is not taming.
## Driven off CreatureInfo's own predator roster rather than a second list, so
## a species added there can't quietly become tameable.
static func can_be_tamed(species: String, is_predator: bool) -> bool:
	if is_predator or CreatureInfo.PREDATOR_SPECIES.has(species):
		return false
	return true
