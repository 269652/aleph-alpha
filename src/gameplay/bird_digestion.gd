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
## Since docs/concept/ethogram.md slice 3 the crop is the one drive clock
## every animal shares (Drives), upside down: fullness is one minus the bird
## body plan's hunger drive, and the numbers are the ethogram's bird profile
## (Ethogram.drive_profile("", "bird")). This file keeps its fullness-facing
## API for AmbientFlyerMarker and re-exports the numbers.
##
## Pure and engine-free, like the rest of the behaviour modules.

const SeasonCycle = preload("res://src/world/season_cycle.gd")
const Drives = preload("res://src/gameplay/drives.gd")
const Ethogram = preload("res://src/gameplay/ethogram.gd")

const BODY_PLAN := "bird"

## Fullness runs 0 (empty) to 1 (fed), the same unit scale every other
## condition value in this project uses. A bird starts empty, because a bird
## that starts fed does nothing until it is not.
static var STARTING_FULLNESS: float = (
	1.0 - float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["start"])
)

## Below this a bird goes looking for food.
static var HUNGRY_BELOW: float = (
	1.0 - float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["threshold"])
)

## How long a full crop takes to empty.
##
## Small birds eat through the day rather than at meals -- a songbird gets
## through a serious fraction of its body weight daily -- so this is hours,
## not a day. Pinned by test_a_bird_eats_several_times_a_day, which brackets
## it from both sides: too fast and it never stops eating, too slow and it
## feeds once and is done.
static var DIGEST_SECONDS: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["rise_seconds"]
)

## How much one meal fills a bird.
static var MEAL_FULLNESS: float = float(
	Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["meal"]
)


static func is_hungry(fullness: float) -> bool:
	return fullness < HUNGRY_BELOW


## Fullness after `delta_seconds` of digesting.
static func fullness_after(fullness: float, delta_seconds: float) -> float:
	return 1.0 - Drives.advanced(1.0 - fullness, DIGEST_SECONDS, delta_seconds)


static func fullness_after_meal(fullness: float) -> float:
	return 1.0 - Drives.after_meal(1.0 - fullness, MEAL_FULLNESS)


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
