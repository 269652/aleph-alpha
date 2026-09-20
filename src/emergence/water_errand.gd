extends RefCounted

## The trip to the well, as a state machine you can SEE (docs/concept/
## village_water.md mechanism 2).
##
## Pillar 2 is the whole point of this file: what a villager is doing must
## be answerable by LOOKING at them. They carry an empty bucket one way and
## a full one back, and that difference is the entire UI this feature
## needs. So `carried` is not decoration hung off the state -- it is the
## state, seen from outside.
##
## Pure and static. Nothing here knows about pathing, tiles or time: the
## walk is driven by ARRIVAL (`arrived`), so a villager who is slow, or
## blocked, or halfway across the square when the day rolls over, is simply
## still on the leg they were on.
##
## The "go again" loop deliberately lives in the CALLER, not here. A pail
## holds less than a dry household is short of, so one trip is often not
## enough -- which is right, because fetching water meant going twice. A
## villager who is at home and still short simply sets out again, and that
## reads as what it is rather than as a machine with a cycle in it.

const HouseholdWater = preload("res://src/emergence/household_water.gd")

## Not on an errand: the bucket is by the door.
const AT_HOME := "at_home"
## Walking to the square with an empty bucket.
const TO_WELL := "to_well"
## Standing at the well, filling it.
const DRAWING := "drawing"
## Walking home with a full one.
const TO_HOME := "to_home"
## Standing at the house, tipping it into the tank.
const POURING := "pouring"

const STATES: Array[String] = [AT_HOME, TO_WELL, DRAWING, TO_HOME, POURING]

## What is in the villager's hand. The two must never look alike, or the
## errand is invisible again and nothing has been fixed.
const BUCKET_EMPTY := "bucket_empty"
const BUCKET_FULL := "bucket_full"

## Where each leg of the errand is headed -- the same `location_tag`
## vocabulary NpcPlanner's schedule already speaks, so an errand and a
## timetable entry are the same kind of instruction to whatever walks it.
const _LOCATION_BY_STATE := {
	AT_HOME: "home",
	TO_WELL: "well",
	DRAWING: "well",
	TO_HOME: "home",
	POURING: "home",
}

const _CARRIED_BY_STATE := {
	TO_WELL: BUCKET_EMPTY,
	DRAWING: BUCKET_EMPTY,
	TO_HOME: BUCKET_FULL,
	POURING: BUCKET_FULL,
}

## What each state becomes once the villager gets where they were going.
const _NEXT_ON_ARRIVAL := {
	TO_WELL: DRAWING,
	DRAWING: TO_HOME,
	TO_HOME: POURING,
	POURING: AT_HOME,
}


## Sets out, if this household's tank says somebody must. Stays at home
## otherwise -- nobody is ever SCHEDULED to the well (pillar 1).
static func begin_if_due(level: float) -> String:
	return TO_WELL if HouseholdWater.trip_is_due(level) else AT_HOME


## Whether this villager is on the errand right now.
static func is_running(state: String) -> bool:
	return state != AT_HOME and STATES.has(state)


## The next state, having got where they were going. An unknown state --
## or one already home -- resolves to AT_HOME rather than stranding
## somebody mid-square holding a bucket forever.
static func arrived(state: String) -> String:
	return String(_NEXT_ON_ARRIVAL.get(state, AT_HOME))


## What the renderer puts in their hand: "" for empty-handed.
static func carried(state: String) -> String:
	return String(_CARRIED_BY_STATE.get(state, ""))


## Where this leg is headed, in NpcPlanner's own location vocabulary.
static func location_tag_for(state: String) -> String:
	return String(_LOCATION_BY_STATE.get(state, "home"))


## Whether being on this leg outranks whatever the day's schedule says.
##
## It has to, or the day rollover takes a villager off the errand halfway
## across the square and the bucket is simply abandoned there. An errand is
## a thing somebody is in the middle of; a timetable is a thing somebody
## intends.
static func overrides_schedule(state: String) -> bool:
	return is_running(state)


## The tank after this errand's bucket goes in.
static func poured(level: float) -> float:
	return HouseholdWater.poured_into(level, HouseholdWater.BUCKET_LITRES)
