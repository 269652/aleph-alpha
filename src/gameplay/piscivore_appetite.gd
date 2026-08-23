extends RefCounted

## What a fish-eating bird wants, and what it does when it wants nothing (see
## docs/concept/ecosystem_dynamics.md's "A kingfisher hunts").
##
## ## The problem this solves
##
## The kingfisher hunted continuously: strike, wait out an eight-second
## cooldown, strike again, forever. Nothing about it was ever full, so a bird
## would work a pond until there was nothing left in it. A predator that
## strips its own larder is not a simulation of a predator, and the fish it
## takes are real -- they come out of the same aquatic population the player
## fishes from.
##
## Two separate rules hold it back, and both are needed:
##
## 1. **Appetite.** A bird eats a couple of fish across an in-game day and is
##    simply not interested in between.
## 2. **Giving up on a poor patch.** Even a hungry bird leaves water that has
##    been worked out, the way a real predator abandons a patch that has
##    stopped paying. Appetite alone only slows the stripping down; this is
##    what actually stops a pond being emptied, because it takes the pressure
##    off exactly when the population can least afford it.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## The world's own day, not an invented one (see SeasonCycle.SECONDS_PER_DAY --
## four real hours), so a bird's appetite keeps the same calendar as the
## seasons and the trees.
const SECONDS_PER_IN_GAME_DAY := SeasonCycle.SECONDS_PER_DAY

## "1 or 2 fish per in-game day based on hunger", as asked. Pinned by the
## resulting COUNT over a simulated day rather than by this number alone.
const MEALS_PER_DAY := 2.0
const SECONDS_PER_MEAL := SECONDS_PER_IN_GAME_DAY / MEALS_PER_DAY

## Hunger runs 0 (full) to 1 (starving), the same unit scale every other
## condition value in this project uses.
const STARTING_HUNGER := 1.0
const HUNGRY_THRESHOLD := 1.0
const HUNGER_PER_SECOND := 1.0 / SECONDS_PER_MEAL

## Below this share of what the water can support, a bird stops working it.
## Not a hard "empty" check: the point is to lift the pressure while a
## population is still able to recover, which is much earlier than zero.
const GIVE_UP_FRACTION := 0.25


static func is_hungry(hunger: float) -> bool:
	return hunger >= HUNGRY_THRESHOLD


static func hunger_after(hunger: float, delta_seconds: float) -> float:
	return clampf(hunger + HUNGER_PER_SECOND * maxf(0.0, delta_seconds), 0.0, 1.0)


## One fish's worth of satisfaction. Takes a full meal off, so a fed bird has
## a whole inter-meal interval before it is interested again.
static func hunger_after_meal(hunger: float) -> float:
	return maxf(0.0, hunger - 1.0)


## Whether this bird will work this water right now: hungry, and the water
## still worth working.
static func will_hunt(hunger: float, fish_population: float, fish_capacity: float) -> bool:
	if not is_hungry(hunger):
		return false
	if fish_capacity <= 0.0 or fish_population <= 0.0:
		return false
	return fish_population / fish_capacity > GIVE_UP_FRACTION


# -- what a bird does when it is not hungry ----------------------------------

## A sated bird is not an idle bird. These are the things it does instead,
## which is the other half of what was asked for: "if they are not hungry they
## should have a different wander mode; fly around; look for mates; mate;
## build a nest".
const ACTIVITY_HUNT := "hunt"
## Ranging widely over its territory rather than holding station on water.
const ACTIVITY_PATROL := "patrol"
## Sitting still somewhere high, digesting.
const ACTIVITY_PERCH := "perch"
## Carrying material back to a nest site.
const ACTIVITY_NEST := "nest"

const ACTIVITIES: Array[String] = [ACTIVITY_HUNT, ACTIVITY_PATROL, ACTIVITY_PERCH, ACTIVITY_NEST]

## The non-hunting activities, in the proportion they are picked. Patrol is
## the commonest because it is the one that reads at a distance -- a bird
## crossing the sky is legible where a bird sitting in a tree is scenery.
const _IDLE_ACTIVITIES: Array[String] = [
	ACTIVITY_PATROL, ACTIVITY_PATROL, ACTIVITY_PERCH, ACTIVITY_NEST
]


## What this bird should be doing. Hunger decides first -- a hungry bird is
## hunting and nothing else -- and a sated one picks from the rest by its own
## seed, so a river full of birds is not choreographed.
static func activity_for(hunger: float, seed_value: int) -> String:
	if is_hungry(hunger):
		return ACTIVITY_HUNT
	return _IDLE_ACTIVITIES[absi(hash(seed_value)) % _IDLE_ACTIVITIES.size()]
