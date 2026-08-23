extends RefCounted

## Fruit on the ground does not last (see docs/concept/flora.md#where-a-forest-
## comes-from).
##
## It is eaten -- by the player, by mammals, by birds who carry the seed on --
## or it rots. Fruit that lies untouched forever turns the ground under every
## tree into a permanent larder and removes the reason to come back in season.
##
## Pure and engine-free: this says how long a windfall keeps and how fresh it
## is right now. Removing the item, or refusing to let something eat it, is
## the caller's job.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long an ordinary fruit stays edible, in world seconds, at neutral
## warmth.
##
## Measured against the season rather than picked from nowhere: a windfall
## should be worth walking back for and then be gone, so it keeps for a
## noticeable slice of a season and nothing like the whole one.
##
## Was ONE day, which is roughly how long soft fruit really lasts -- and made
## the whole system unobservable. A season is twelve in-game days and a day is
## four real hours, so at fast-forward a day passes in about two seconds:
## windfalls rotted before any animal could reach them, and nothing was ever
## seen lying on the ground (reported). Five days is still well under a season,
## still means a glut does not last, and is long enough that a windfall is
## something animals converge on rather than something that has already gone.
const BASE_EDIBLE_SECONDS := SeasonCycle.SECONDS_PER_DAY * 5.0

## How much longer a given food keeps than the base.
##
## A nut in its shell keeps far longer than soft fruit -- that is the whole
## reason a squirrel caches nuts and nobody caches cherries. The shell is the
## difference, so the split is by whether there is one.
const KEEPING_MULTIPLIER := {
	"cherry": 0.6,
	"fruit": 1.0,
	"apple": 1.6,
	"nut": 6.0,
	"walnut": 8.0,
	"acorn": 8.0,
	"hazelnut": 8.0,
}

## What an unregistered food keeps for, relative to the base. Soft fruit is the
## safe assumption: an item that rots too soon is a nuisance, one that never
## rots is the larder this exists to prevent.
const DEFAULT_KEEPING := 1.0

## How much the season's cold slows rot.
##
## Cold keeps things: a windfall in late autumn is still there weeks later and
## the same fruit in high summer is not. This is the one part of spoilage the
## player can plan around, which is why it is a real factor rather than a
## flat rate.
const SEASON_KEEPING := {
	"spring": 1.0,
	"summer": 0.6,
	"autumn": 1.4,
	"winter": 3.0,
}


## How long this food stays edible where it lies, in world seconds.
static func edible_seconds(item_id: String, season: String) -> float:
	var keeping: float = KEEPING_MULTIPLIER.get(item_id, DEFAULT_KEEPING)
	var cold: float = SEASON_KEEPING.get(season, 1.0)
	return BASE_EDIBLE_SECONDS * keeping * cold


## How sound this food still is, 1 fresh to 0 rotten.
static func freshness(item_id: String, age_seconds: float, season: String) -> float:
	var life := edible_seconds(item_id, season)
	if life <= 0.0:
		return 0.0
	return clampf(1.0 - maxf(age_seconds, 0.0) / life, 0.0, 1.0)


## Whether this is still worth eating.
static func is_edible(item_id: String, age_seconds: float, season: String) -> bool:
	return freshness(item_id, age_seconds, season) > 0.0


## Whether this food rots at all. Anything not in the table is assumed to --
## the larder is the failure worth guarding against.
static func spoils(item_id: String) -> bool:
	return edible_seconds(item_id, "spring") > 0.0
