extends RefCounted

## A house's own water (docs/concept/village_water.md mechanism 1): what is
## in the tank, what the people in it drink, and when somebody has to take
## a bucket to the well.
##
## Pure and static. The level itself lives as one number on the building's
## own record -- the same persistence idiom `guild_days_open` already uses
## (see mage_guild.md): no new store, no new save format, and it travels
## with the house through a chunk round trip.
##
## **No new clock.** Water is drawn on the simulated-day cadence
## village_estates.md's baskets already run on, and the thirst it answers
## is the one Ethogram's villager profile has always defined -- npc_needs.gd
## simulates hunger only because "thirst has no villager-side consumer",
## and this is that consumer.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## What a house holds: a kitchen barrel, not a cistern. Six full buckets.
const TANK_LITRES := 60.0

## What one villager drinks a day. Drinking water, not washing or brewing --
## those are the village's own trades and have their own inputs.
const BUCKET_LITRES := 10.0
const DRAW_PER_HEAD_PER_DAY := 2.5

## How low a tank gets before somebody is sent. Deliberately not empty: a
## household that waits until it is dry has a thirsty day while somebody
## walks to the square and back.
const TRIP_THRESHOLD_SHARE := 0.25

## What a farm may never pour on its field. People before plants -- and it
## is pinned to outlast the walk (test_the_reserve_outlasts_the_walk_to_the_
## well), so watering crops can never leave the household itself dry.
const DRINKING_RESERVE_LITRES := 15.0

## None of the four numbers above is a number somebody liked. They are
## pinned by the ERRAND they produce, which is the thing a player actually
## experiences: a two-person household must reach the well less than once a
## season and more than once a day, a bigger household must go more often
## than a smaller one, and the reserve must outlast a trip. Change any of
## them and tests/unit/test_household_water.gd says whether the errand still
## reads like an errand.


## What a household of `heads` drinks over `days`. Nothing for an empty
## house or a span that has not passed -- never negative, so a nonsense
## argument cannot refund water into a tank.
static func draw_for(heads: int, days: float) -> float:
	if heads <= 0 or days <= 0.0:
		return 0.0
	return float(heads) * days * DRAW_PER_HEAD_PER_DAY


## The tank after that household has drunk from it, floored at empty.
static func level_after(level: float, heads: int, days: float) -> float:
	return maxf(0.0, level - draw_for(heads, days))


## The tank after a bucket (or any amount) is poured in, capped at full --
## what does not fit runs down the step.
static func poured_into(level: float, litres: float) -> float:
	return minf(TANK_LITRES, level + maxf(0.0, litres))


## Whether this house must send somebody to the well.
static func trip_is_due(level: float) -> bool:
	return level <= TANK_LITRES * TRIP_THRESHOLD_SHARE


## What a house has in it the day it is raised.
##
## **This is the anti-crowd mechanism**, and it is the whole reason the
## village stops emptying into the square at once. Two houses raised on the
## same day start with different amounts of water, so they cross the trip
## threshold on different days and never re-synchronise afterwards. The
## stagger is a property of the initial condition rather than jitter
## applied to a queue -- nothing has to remember to spread anybody out.
##
## Always above the threshold: a village founded this morning must not send
## every household to the well before noon, which is exactly the crowd this
## feature exists to break up.
static func starting_level(seed_value: int) -> float:
	var lowest := TANK_LITRES * TRIP_THRESHOLD_SHARE
	# 1..10000 rather than 0..9999, so the lowest possible start is still
	# strictly above the threshold rather than exactly on it.
	var steps := float((absi(hash("%d_water_start" % seed_value)) % 10000) + 1) / 10000.0
	return lowest + (TANK_LITRES - lowest) * steps


## What a farmhouse may pour on its field: everything above the household's
## own drinking reserve, and nothing at all once the tank is down to it.
static func spare_for_crops(level: float) -> float:
	return maxf(0.0, level - DRINKING_RESERVE_LITRES)
