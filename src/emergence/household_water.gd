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

## The vessel the water is carried in. A bucket is never where water
## LIVES (that is the tank on the house) -- it is how a trip's worth moves
## across the square, and it is what a villager is seen holding.
const BUCKET_ITEM_ID := "bucket"

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
	return _started_above(seed_value, TANK_LITRES * TRIP_THRESHOLD_SHARE)


## The same stagger, seeded the same way, from a different floor -- so a
## building whose trip comes sooner is not simply raised already needing
## one. See farm_starting_level.
static func _started_above(seed_value: int, lowest: float) -> float:
	# 1..10000 rather than 0..9999, so the lowest possible start is still
	# strictly above the floor rather than exactly on it.
	var steps := float((absi(hash("%d_water_start" % seed_value)) % 10000) + 1) / 10000.0
	return lowest + (TANK_LITRES - lowest) * steps


## What a farmhouse may pour on its field: everything above the household's
## own drinking reserve, and nothing at all once the tank is down to it.
static func spare_for_crops(level: float) -> float:
	return maxf(0.0, level - DRINKING_RESERVE_LITRES)


## -- what the field costs (docs/concept/village_water.md mechanism 3) ------

## What ONE tending visit takes out of the farmhouse tank.
##
## A tending visit is what a farmer actually does at a bed: they water it
## and the beds around it run wet too (NpcMarker._water_the_beds_around).
## So the unit priced here is the VISIT, not the tile -- pricing tiles
## would make a wide field cost more than a narrow one for the same walk,
## which is not how a furrow works.
##
## Pinned against the MEASURED tending rate below, never chosen: what
## matters is what a field costs the tank in a DAY, and a day holds about
## six visits. See test_household_water.gd's "what the field costs the
## tank" block, which pins the rhythm this produces rather than the number
## itself.
const LITRES_PER_TENDING := 1.0

## How often a real village field is actually tended, per simulated day.
##
## **Measured, not assumed** (`tools/probe_farm_water.gd`): 5.7 and 6.1 on
## the two working farms of a real twelve-villager village.
##
## The first cut of this feature assumed 1.33 -- reasoning from
## FarmPlot.MIN_WATER_GRACE_SECONDS being shorter than a simulated day --
## and so billed the field more than four times what it should have. The
## farmhouse ran dry almost at once, the beds stopped being watered, and
## the same probe village went from 164 wheat harvested to 24. The
## assumption looked careful and was wrong by a factor of four; only the
## probe said so.
const TENDINGS_PER_SIMULATED_DAY := 6.0

## How much watering a farmhouse keeps in hand when it sends somebody to
## the well -- in tendings, because that is the unit the field is billed
## in. Without a margin the trip only becomes due once the beds are
## already dry, and the field then goes thirsty for the whole walk across
## the square.
const TENDINGS_IN_HAND := 4.0


## What a working field takes out of the tank in one simulated day -- the
## number that actually decides how often a farm is seen at the well, and
## the one the constants above are pinned through.
static func field_draw_per_day() -> float:
	return LITRES_PER_TENDING * TENDINGS_PER_SIMULATED_DAY


## How often a working farm has to send somebody, once it has settled into
## its rhythm: one bucket's worth, divided by what the field drinks.
static func days_between_farm_trips() -> float:
	return BUCKET_LITRES / field_draw_per_day()


## The same for a household of `heads`, who only drink.
static func days_between_household_trips(heads: int) -> float:
	return BUCKET_LITRES / draw_for(heads, 1.0)


## Whether this farmhouse can put water on its beds at all: only ever out
## of the spare above the household's own drinking reserve.
static func can_water_crops(level: float) -> bool:
	return spare_for_crops(level) >= LITRES_PER_TENDING


## The tank after one tending visit -- unchanged when there was nothing to
## spare, so a farm can never water itself into a drought however many
## times it is asked. People before plants, enforced here rather than
## trusted to every caller.
static func level_after_tending(level: float) -> float:
	return level - LITRES_PER_TENDING if can_water_crops(level) else level


## The level a farmhouse sends somebody at: its household's own reserve
## plus TENDINGS_IN_HAND more visits' worth.
##
## Named once rather than written twice, because the SAME number is also
## the floor a farm is raised above (farm_starting_level). Two copies that
## drifted apart would raise farms already needing a trip, which is the
## one way to lose the whole anti-crowd stagger.
static func farm_trip_level() -> float:
	return DRINKING_RESERVE_LITRES + LITRES_PER_TENDING * TENDINGS_IN_HAND


## Whether this FARMHOUSE must send somebody to the well. Sooner than a
## household would go (TENDINGS_IN_HAND), because a field that stops being
## watered withers, where a household that runs low is merely thirsty.
static func farm_trip_is_due(level: float) -> bool:
	return level < farm_trip_level()


## What a FARMHOUSE has in it the day it is raised.
##
## The same anti-crowd stagger, off the same seed -- but floored at the
## farm's OWN threshold rather than a household's. A farm seeded from
## starting_level would be raised already needing a trip about a third of
## the time (measured: seeds 3, 17 and 91 of the four in
## test_earth_chunk_manager_household_water.gd), and two farms founded
## together would then walk to the well together forever after. The whole
## point of the stagger is that it is a property of the INITIAL
## CONDITION, so getting the initial condition wrong loses all of it.
static func farm_starting_level(seed_value: int) -> float:
	return _started_above(seed_value, farm_trip_level())
