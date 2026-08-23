extends RefCounted

## A fly's life: egg, maggot, pupa, adult (see docs/concept/flies.md).
##
## The loop is the feature: rot draws a fly, the fly lays, the maggots eat the
## rot, the maggots become flies, those flies lay. It is the one population in
## the world a player can create on purpose by leaving food out.
##
## It is also the one that will eat the world if it is not bounded. A breeding
## population with no ceiling is the tree-spread bug again and worse, because
## flies breed on a timescale of days rather than years -- so every level here
## has a cap, and the caps are the load-bearing part.
##
## Pure and engine-free: stages, timings, and who may lay what where. Spawning
## anything is the caller's job.

const Olfaction = preload("res://src/gameplay/olfaction.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

const STAGE_EGG := "egg"
const STAGE_MAGGOT := "maggot"
const STAGE_PUPA := "pupa"
const STAGE_ADULT := "adult"

## ## Timings
##
## A housefly at summer temperatures: egg about a day, larva about four, pupa
## about four, then weeks as an adult. Kept in real proportion because the
## proportion is what makes the loop watchable -- the several days of pupa are
## what keep a swarm's growth in check.
##
## The PUPA is included even though it is invisible and does nothing. Leaving
## it out would have maggots turning into flies where they stand and run the
## loop several days faster, which is the difference between a swarm over a
## windfall and an explosion.
const MAGGOT_AT_SECONDS := SeasonCycle.SECONDS_PER_DAY * 1.0
const PUPA_AT_SECONDS := SeasonCycle.SECONDS_PER_DAY * 5.0
const ADULT_AT_SECONDS := SeasonCycle.SECONDS_PER_DAY * 9.0


## Which stage a fly of this age is in.
static func stage_at(age_seconds: float) -> String:
	if age_seconds < MAGGOT_AT_SECONDS:
		return STAGE_EGG
	if age_seconds < PUPA_AT_SECONDS:
		return STAGE_MAGGOT
	if age_seconds < ADULT_AT_SECONDS:
		return STAGE_PUPA
	return STAGE_ADULT


## Only the maggot eats. Nothing else in the life cycle touches the rot it
## hatched on -- which is why a swarm makes its own food run out rather than
## living off it forever.
static func eats(stage: String) -> bool:
	return stage == STAGE_MAGGOT


## Only an adult flies. An egg or a pupa drifting around would be a rendering
## bug with a life cycle attached.
static func flies(stage: String) -> bool:
	return stage == STAGE_ADULT


# -- laying ------------------------------------------------------------------

## How rotten a thing must smell before it is worth laying on. Fresh fruit has
## nothing on it for a maggot to eat.
const LAYABLE_DECAY := 0.5

## How many eggs one clutch is.
##
## A real housefly lays about a hundred. Scaled down hard, because a hundred
## eggs is a hundred nodes -- but the SHAPE is kept: several eggs, several
## clutches, and most of the young never reaching the air.
const CLUTCH_SIZE := 4

## How many clutches one female lays in her life. An endlessly laying female
## is an endlessly growing swarm.
const MAX_CLUTCHES := 3

## How many flies one source can support, at any stage.
##
## The apple runs out. This is what turns "a pile of rotten apples gets a
## swarm" into a bounded promise rather than an unbounded one.
const MAX_PER_SOURCE := 8

## And a ceiling across the whole world, so a hundred sources cannot each be
## under their own limit and still take the frame rate down between them.
const MAX_FLIES_IN_WORLD := 60


## Whether this thing is far enough gone to lay on.
static func can_lay_on(mixture: Dictionary) -> bool:
	return float(mixture.get(Olfaction.DECAY, 0.0)) >= LAYABLE_DECAY


## Whether this individual can lay right now.
static func can_lay(stage: String, mated: bool, clutches_laid: int) -> bool:
	return stage == STAGE_ADULT and mated and clutches_laid < MAX_CLUTCHES


## Whether a source with this many flies already on it can take more.
static func may_add_to_source(present: int) -> bool:
	return present < MAX_PER_SOURCE


## Whether the world can take more flies at all.
static func may_add_to_world(present: int) -> bool:
	return present < MAX_FLIES_IN_WORLD


## How many eggs are actually laid into a source that already holds `present`,
## which is a clutch or whatever is left of the ceiling.
static func eggs_for_clutch(present: int) -> int:
	return clampi(MAX_PER_SOURCE - present, 0, CLUTCH_SIZE)
