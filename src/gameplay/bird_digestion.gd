extends RefCounted

## A bird's gut: why it eats, and what comes out (see
## docs/concept/seed_dispersal.md).
##
## Birds already carried a swallowed seed and planted it further on. What they
## did not have was a REASON to eat -- they foraged constantly whether or not
## they needed to, which makes a bird a harvesting machine rather than an
## animal -- or anything to show for the other end of it.
##
## A dropping is the visible half of dispersal. Without it a seed simply
## appears somewhere a bird happened to be, and the player never sees the
## connection between the bird that ate the berry and the flower that came up.
##
## Pure and engine-free, like the rest of the behaviour modules.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Fullness runs 0 (empty) to 1 (fed), the same unit scale every other
## condition value in this project uses. A bird starts empty, because a bird
## that starts fed does nothing until it is not.
const STARTING_FULLNESS := 0.0

## Below this a bird goes looking for food.
const HUNGRY_BELOW := 0.35

## How long a full crop takes to empty.
##
## Small birds eat through the day rather than at meals -- a songbird gets
## through a serious fraction of its body weight daily -- so this is hours,
## not a day. Pinned by test_a_bird_eats_several_times_a_day, which brackets
## it from both sides: too fast and it never stops eating, too slow and it
## feeds once and is done.
const DIGEST_SECONDS := SeasonCycle.SECONDS_PER_DAY / 8.0

## How much one meal fills a bird.
const MEAL_FULLNESS := 0.7


static func is_hungry(fullness: float) -> bool:
	return fullness < HUNGRY_BELOW


## Fullness after `delta_seconds` of digesting.
static func fullness_after(fullness: float, delta_seconds: float) -> float:
	var emptied := maxf(delta_seconds, 0.0) / DIGEST_SECONDS
	return clampf(fullness - emptied, 0.0, 1.0)


static func fullness_after_meal(fullness: float) -> float:
	return clampf(fullness + MEAL_FULLNESS, 0.0, 1.0)


## ## On gut passage
##
## There is deliberately no second clock for "has the seed passed through yet".
##
## SeedEndozoochory already models passage as a DISTANCE the bird carries the
## seed -- which is better than a time, because a faster bird carries it
## proportionally further. Adding a passage timer on top gave two clocks for
## one thing, at wildly different scales: the carry is seconds of game time and
## a real gut passage is minutes, so the timer never elapsed and dispersal
## stopped happening at all. Every seed a bird swallowed simply stayed in it.
##
## The carry IS the passage. What digestion adds here is a reason to eat, and
## the dropping at the end of it.
