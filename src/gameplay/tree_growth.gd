extends RefCounted

## A tree's seven stages from seedling to full maturity.
##
## Trees previously popped into existence at full size, which made a forest
## read as scenery placed all at once rather than as a population with an
## age structure. Growth gives tree spread (see TreeSpread, and
## ecosystem_dynamics.md) a consequence you can actually watch: a sapling
## appears under a mature canopy, and years later it is the canopy.
##
## Pure logic over an age in seconds, so the renderer, the chopping rules
## and the fruiting model all read the same stage from the same clock
## (EarthChunkManager's `_world_age_seconds`).

## Seedling, sprout, sapling, young, growing, near-mature, mature.
const STAGE_COUNT := 7

## How long a tree takes to reach the final stage, in simulated seconds.
## Long enough that growth reads as a slow background process rather than a
## timer the player watches, short enough to be witnessed across a few play
## sessions -- roughly ten simulated ecosystem days at
## EarthChunkManager.SECONDS_PER_SIMULATED_DAY.
const MATURITY_SECONDS := 600.0

## How big a seedling is relative to a full-grown tree. Small enough to read
## instantly as "not a tree yet" without becoming an invisible speck.
const SEEDLING_SCALE := 0.22

## Only from this stage on does a tree bear fruit or count as real timber --
## a sapling is not a harvest.
const PRODUCTIVE_STAGE := 4


## Which stage a tree of `age_seconds` is in, 0 (seedling) through
## STAGE_COUNT - 1 (mature). Growth is even across the stages: the drama
## comes from the size curve below, not from uneven timing.
func stage_at(age_seconds: float) -> int:
	if age_seconds <= 0.0:
		return 0
	var fraction := age_seconds / MATURITY_SECONDS
	return clampi(int(fraction * float(STAGE_COUNT)), 0, STAGE_COUNT - 1)


## The render scale for a stage. Deliberately NOT linear: young trees put on
## height fast and then slow as they mature, so an eased curve reads far
## more like real growth than a constant creep.
func scale_for_stage(stage: int) -> float:
	var clamped := clampi(stage, 0, STAGE_COUNT - 1)
	var t := float(clamped) / float(STAGE_COUNT - 1)
	# Ease-out: quick early gains, tapering toward full size.
	var eased := 1.0 - pow(1.0 - t, 1.8)
	return lerp(SEEDLING_SCALE, 1.0, eased)


## The render scale for a tree of this age -- the form the renderer wants.
func scale_at(age_seconds: float) -> float:
	return scale_for_stage(stage_at(age_seconds))


## Does a tree at this stage bear fruit and yield real wood?
func is_productive(stage: int) -> bool:
	return stage >= PRODUCTIVE_STAGE
