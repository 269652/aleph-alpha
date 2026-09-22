extends RefCounted
## Putting the night behind you (docs/concept/sleep.md).
##
## `docs/concept/survival.md`'s first paragraph has always said a character
## must "eat, drink, and sleep". Eating and drinking are real --
## `SurvivalMeters` carries hunger, thirst and nutrition and `eat`/`drink`
## relieve them. Sleep never existed: `SurvivalMeters.rest(amount)` is an
## arithmetic helper that adds to the stamina bar, with no resting state,
## nothing that can interrupt one, and no way for a character to put a night
## behind them.
##
## That gap is what blocked docs/concept/monsters.md's entry 3, the Alp,
## whose entire behaviour is "it approaches only while you rest, and drains
## stamina rather than health. Waking is the counterplay, and the cost of
## waking is the rest you lose." There was nothing for it to attach to.
##
## Sleep here is a VERB, not a fifth need. This game already has four needs
## and a sickness model, and a fatigue bar that fills while you play would
## be a chore rather than a mechanic. What a rest buys is the night itself:
## the cold, the dark, and the hours in which there is nothing to do but
## freeze.
##
## Pure: RefCounted, static functions, no player, no world, no scene tree.

const DawnClause = preload("res://src/gameplay/dawn_clause.gd")
const Answerback = preload("res://src/gameplay/answerback.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")

## Hours on a clock face.
const HOURS_PER_DAY := 24.0

## How fast the clock runs while a character sleeps, derived from two
## constants that already exist rather than chosen.
##
## `DawnClause.MAX_OFFSET_HOURS` is half a clock face -- the worst night any
## rest can possibly face -- and `Answerback.MAX_CARD_SECONDS` is this HUD's
## own statement of the longest thing it will ask a player to sit and read.
## So the LONGEST POSSIBLE NIGHT PASSES IN NO MORE REAL TIME THAN THE
## LONGEST CARD, which is the property that makes skipping a night actually
## skip it, and the rate falls out at a memorable one in-game hour per real
## second. Both bounds are pinned by test.
const HOURS_PER_REAL_SECOND := DawnClause.MAX_OFFSET_HOURS / Answerback.MAX_CARD_SECONDS

## One in-game hour, in the world-age seconds `EarthChunkManager.
## advance_world_age` counts (`SeasonCycle.SECONDS_PER_DAY` is four real
## hours per in-game day). Read from the season clock rather than restated,
## so a rest moves the sun, the season, the fruit and the ecology together
## and nothing runs on a second clock.
const WORLD_AGE_SECONDS_PER_IN_GAME_HOUR := SeasonCycle.SECONDS_PER_DAY / HOURS_PER_DAY


## Why this character may not lie down, or the empty string when they may.
##
## Deliberately short. No refusal here keeps a sleeper SAFE -- a safe sleep
## is a loading screen, and being unwatched is the whole cost of resting.
## These are the three states in which lying down is not a decision at all:
## something is already coming, you are in the water, or you are asleep.
static func refusal_for(facts: Dictionary) -> String:
	if bool(facts.get("already_resting", false)):
		return "You are already asleep."
	if bool(facts.get("hunted", false)):
		return "Something is hunting you."
	if bool(facts.get("in_water", false)):
		return "Not in the water."
	return ""


## How long a rest begun at `local_hour` has to run, in hours, wrapping the
## clock face.
##
## First light is `DawnClause.FIRST_LIGHT_HOUR` -- civil dawn, the sun's
## centre six degrees below the horizon, already derived from this repo's
## own astronomy for the arrival clause. The hour a character wakes and the
## hour a new character opens their eyes are ONE fact, stated once.
##
## A rest begun in daylight is allowed and simply runs nearly a whole day:
## the world does not forbid a nap.
static func hours_until_first_light(local_hour: float) -> float:
	var wait := fposmod(DawnClause.FIRST_LIGHT_HOUR - local_hour, HOURS_PER_DAY)
	return wait


## How much world age one frame of resting advances.
static func world_age_seconds_for(real_delta_seconds: float) -> float:
	if real_delta_seconds <= 0.0:
		return 0.0
	return (
		real_delta_seconds * HOURS_PER_REAL_SECOND * WORLD_AGE_SECONDS_PER_IN_GAME_HOUR
	)


## Whether first light has arrived. A frame that overshoots still counts --
## the clock does not stop on an exact boundary.
static func is_complete(hours_remaining: float) -> bool:
	return hours_remaining <= 0.0


## What the character is told on waking.
##
## An interrupted rest names the hours that really passed, because the cost
## of waking early IS the rest you lose and a player has to be able to see
## what they got.
static func wake_report(hours_slept: float, completed: bool) -> String:
	if completed:
		return "You slept until first light."
	var hours := maxf(0.0, hours_slept)
	if hours < 1.0:
		return "Woken almost at once."
	return "Woken after %d hours." % int(roundf(hours))
