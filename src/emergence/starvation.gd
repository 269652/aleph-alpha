extends RefCounted

## What the hunger drive does when it is left at the top (docs/concept/
## village_mortality.md mechanism 1).
##
## Pure and static. Hunger itself is not modelled here -- it is already
## Ethogram's villager drive, rising on the shared lived-experience clock
## (NpcNeeds is the facade over it). This is only the clock that runs
## WHILE that drive sits at the top, and what it eventually means.
##
## **Measured in hunger CYCLES, never in days**, and that is the whole
## point of the module. There are two day-lengths in this codebase --
## SeasonCycle.SECONDS_PER_DAY is 14400s of material economy,
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY is the 60s a player feels --
## and a mortality clock written against the wrong one either kills
## instantly or never kills at all. Reading the drive's own cycle means
## starvation cannot drift onto a different clock than the hunger it
## measures: retune the ethogram and this retunes with it.

const Ethogram = preload("res://src/gameplay/ethogram.gd")

const BODY_PLAN := "villager"

## The hunger level at which a villager is no longer merely looking for
## food but dying for want of it. Deliberately above NpcNeeds'
## HUNGRY_THRESHOLD (pinned by test_starving_is_worse_than_merely_hungry):
## "hungry" is a villager walking to the stall, and a villager walking to
## the stall is not a villager to bury.
##
## Just under a full drive rather than exactly 1.0, so the state is reached
## robustly rather than on an exact float landing.
const STARVING_LEVEL := 0.95

## How many full hunger cycles at the top it takes to kill.
##
## Pinned by the window it produces, never chosen -- see
## test_starvation.gd's "the window is the mechanic" block. It has to be
## longer than one cycle (a villager who empties once and eats again is
## not marked for death by it) and short enough that a village with
## nothing to eat really does lose people rather than standing permanently
## at the brink. Pillar 3: the intervention window IS the mechanic, so a
## player who notices has time to cross the village and come back with
## food, several times over.
const CYCLES_TO_DIE := 4.0


## How long this villager's hunger takes to go from full to empty -- their
## OWN drive's cycle, read from the ethogram rather than copied beside it.
static func hunger_cycle_seconds() -> float:
	return float(Ethogram.drive_profile("", BODY_PLAN)[Ethogram.DRIVE_HUNGER]["rise_seconds"])


static func cycles_to_die() -> float:
	return CYCLES_TO_DIE


## The whole window, in seconds of the same clock hunger itself rises on.
static func seconds_to_die() -> float:
	return cycles_to_die() * hunger_cycle_seconds()


## The starvation clock after `delta_seconds` at this hunger level.
##
## Zero the moment hunger drops back below STARVING_LEVEL -- eating clears
## it OUTRIGHT rather than draining it down. A villager who gets a meal is
## not still dying from last week, which is what makes the cart of grain
## arriving mid-famine actually save somebody (pillar 3).
##
## Never runs backwards: a nonsense delta cannot un-starve anybody.
static func advance(
	starved_seconds: float, hunger_before: float, hunger_after: float, delta_seconds: float
) -> float:
	if hunger_after < STARVING_LEVEL:
		return 0.0
	var step := maxf(0.0, delta_seconds)
	if hunger_before >= STARVING_LEVEL:
		return starved_seconds + step
	# They crossed the line partway through this step. Hunger is not always
	# ticked a frame at a time -- a settlement step is 30s and a catch-up
	# after a reload is longer still -- so billing the WHOLE step at the
	# level it ended on kills somebody who was starving for only the last
	# instant of it. Found by test_a_meal_at_the_last_moment_saves_them,
	# which had a villager dead before the meal could reach them.
	#
	# The drive rises linearly, so the part spent above the line is just
	# the share of the climb that was above it.
	var climbed := hunger_after - hunger_before
	if climbed <= 0.0:
		return starved_seconds + step
	return starved_seconds + step * clampf((hunger_after - STARVING_LEVEL) / climbed, 0.0, 1.0)


## Whether it has gone on too long.
static func is_dead(starved_seconds: float) -> bool:
	return starved_seconds >= seconds_to_die()
