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
const CaptureTool = preload("res://src/gameplay/capture_tool.gd")


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


## How much harder a PREDATOR fights the rope at the same physical condition,
## grounded in the real domestication-asymmetry point taming.md's "Any
## animal, the right tool" makes: wild predators are measurably harder to
## habituate than domesticable prey species. DERIVED, not eyeballed -- the
## ratio of average MAX_HEALTH_BY_SPECIES across CreatureInfo.PREDATOR_SPECIES
## to average MAX_HEALTH_BY_SPECIES across every other species in that same
## table (see test_predator_break_free_multiplier_is_derived_from_species_health,
## which recomputes this independently and pins the constant against it).
##
## GDScript consts can't call a function to initialize themselves, so this is
## a `static var` computed once at class load rather than a `const` -- still
## fixed for the life of the game, just not a compile-time literal.
static var PREDATOR_BREAK_FREE_MULTIPLIER: float = _compute_predator_break_free_multiplier()


static func _compute_predator_break_free_multiplier() -> float:
	var predator_sum := 0.0
	var predator_count := 0
	var other_sum := 0.0
	var other_count := 0
	for a_species in CreatureInfo.MAX_HEALTH_BY_SPECIES:
		var hp: float = CreatureInfo.MAX_HEALTH_BY_SPECIES[a_species]
		if CreatureInfo.PREDATOR_SPECIES.has(a_species):
			predator_sum += hp
			predator_count += 1
		else:
			other_sum += hp
			other_count += 1
	return (predator_sum / predator_count) / (other_sum / other_count)


## How much a fully-invested `taming_affinity` (the menagerie keystone's own
## ceiling, 15.0 -- see skill_web.gd -- used here rather than a second,
## invented ceiling) can reduce the break-free chance the player faces, as a
## FRACTION of the chance itself. Derived from this file's own existing
## MIN/MAX_BREAK_FREE_CHANCE spread rather than a fresh eyeballed number: an
## experienced handler closes roughly the same fraction of that spread that
## separates a fresh animal from a spent one. Deliberately < 1.0 so a
## fully-invested handler still never reaches a guaranteed hold (0.0) --
## "harder", per taming.md's pillars, never "impossible".
const AFFINITY_CEILING := 15.0
static var AFFINITY_MAX_REDUCTION_FRACTION: float = MIN_BREAK_FREE_CHANCE / MAX_BREAK_FREE_CHANCE


## `is_predator` scales the animal's effective condition up by
## PREDATOR_BREAK_FREE_MULTIPLIER before it enters the same MIN/MAX lerp
## every species uses -- a predator saturates to MAX_BREAK_FREE_CHANCE at a
## much lower condition than a herbivore does, so it stays measurably harder
## to hold across most of a struggle even though both share the same ceiling.
##
## `affinity` (Player.skill_bonus("taming_affinity"), 0 with no investment up
## to AFFINITY_CEILING at menagerie) then scales the result back DOWN by up to
## AFFINITY_MAX_REDUCTION_FRACTION. At affinity 0 this is a no-op, so a
## character with no investment sees byte-identical numbers to before this
## parameter existed (see
## test_break_free_chance_is_unchanged_with_no_predator_and_no_affinity).
static func break_free_chance(condition: float, is_predator: bool = false, affinity: float = 0.0) -> float:
	var predator_multiplier := PREDATOR_BREAK_FREE_MULTIPLIER if is_predator else 1.0
	var scaled_condition := clampf(condition, 0.0, 1.0) * predator_multiplier
	var chance := lerpf(MIN_BREAK_FREE_CHANCE, MAX_BREAK_FREE_CHANCE, clampf(scaled_condition, 0.0, 1.0))
	var affinity_fraction := clampf(affinity, 0.0, AFFINITY_CEILING) / AFFINITY_CEILING
	return chance * (1.0 - affinity_fraction * AFFINITY_MAX_REDUCTION_FRACTION)


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


## How long, in world seconds since an animal was first caught, it must have
## been kept before it will fight for its owner rather than merely follow
## them -- PetLoyalty's one genuinely distinct idea (docs/concept/taming.md
## "Retiring pet_loyalty.gd"), folded in here as an axis ORTHOGONAL to trust
## rather than a second, stricter point on the trust scale: accepts_orders
## already gates at TAME_TRUST, trust's own ceiling
## (test_trust_never_climbs_past_tame), so a stricter trust gate has no
## headroom to occupy.
##
## Derived from NEGLECT_SECONDS rather than eyeballed: a few full neglect
## periods' worth of continuous keeping, so a single forgotten afternoon can
## never retroactively make an animal guard-worthy.
const GUARD_KEPT_SECONDS := NEGLECT_SECONDS * 3.0


## Whether a tamed animal will fight for its owner, not just follow them.
## `kept_seconds` is world time elapsed since the animal was first caught --
## the caller's to supply, the same division of labour trust_after_neglect
## already has with hungry_seconds, and exactly the `kept_since` field
## animal_genetics.md's V2 record already reserves for other reasons. An
## animal that has fallen back below TAME_TRUST (neglect) never qualifies
## regardless of how long ago it was first caught.
static func accepts_guard_order(trust: float, kept_seconds: float) -> bool:
	return accepts_orders(trust) and kept_seconds >= GUARD_KEPT_SECONDS


## Species that could plausibly carry a person. A tamed boar follows and
## stays; it is not a horse.
const RIDABLE_SPECIES := {"horse": true}


static func can_be_mounted(species: String) -> bool:
	return RIDABLE_SPECIES.has(species)


static func is_mountable(species: String, trust: float) -> bool:
	return can_be_mounted(species) and accepts_orders(trust)


## Whether `tool_id` is the right tool to catch `species` with, AND capture
## is currently allowed for it at all.
##
## Predators are no longer a categorical exclusion (see docs/concept/
## taming.md's "Any animal, the right tool") -- a wolf has a neck exactly
## like a horse does, so it joins the Roped class like everything else with
## legs and a neck. What changes for a predator is how hard it fights the
## rope once caught (see break_free_chance's predator harshness below), not
## whether a lasso is the right tool.
##
## World-boss-scale species (CreatureInfo.WORLD_BOSS_SPECIES) stay excluded
## regardless of tool, on purpose: the reinforced rope is real and craftable
## today, but actually resolving a capture attempt against something with
## its own aggro state and fitness-driven promotion score is a documented
## open question (worldbosses.md), not one this function should answer in
## passing.
static func can_be_tamed(species: String, tool_id: String) -> bool:
	if CreatureInfo.WORLD_BOSS_SPECIES.has(species):
		return false
	return CaptureTool.required_tool_for(species) == tool_id
