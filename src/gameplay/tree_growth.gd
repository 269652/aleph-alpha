extends RefCounted

const SeasonCycle = preload("res://src/world/season_cycle.gd")

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

## ## A tree takes YEARS
##
## A sapling becomes a young tree in a year, and takes two more to mature.
##
## This was 600 simulated seconds against a year of 691,200 -- under a tenth of
## a percent of a year -- so a tree went from nothing to full-grown inside a
## single season. It was justified as "roughly ten simulated ecosystem days",
## which is a different clock from the one the seasons run on, and the mismatch
## was invisible until /ecotest made a year watchable.
##
## Measured against the season cycle now, because that is the clock a player
## experiences growth against: they remember the tree that was a stick last
## autumn.
const YOUNG_SECONDS := SeasonCycle.SECONDS_PER_YEAR
const MATURITY_SECONDS := SeasonCycle.SECONDS_PER_YEAR * 3.0

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
	# Guard the mature end BEFORE converting to int: callers pass INF to mean
	# "this has always been here" (map-generated forest), and int(INF) does
	# not clamp to a large value -- it collapses, which silently turned every
	# mature forest tree into a seedling.
	if age_seconds >= MATURITY_SECONDS:
		return STAGE_COUNT - 1
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
##
## CONTINUOUS, not one of seven fixed sizes.
##
## This used to return scale_for_stage(stage_at(age)), so a tree held one size
## for a seventh of its life and then jumped. Over ten simulated minutes that
## was unnoticeable; over three years of watchable growth it reads as a tree
## popping between sizes rather than a stem thickening.
##
## The STAGES still exist and still mean what they meant -- they gate bearing
## and timber -- but size is a curve through them.
func scale_at(age_seconds: float) -> float:
	if age_seconds <= 0.0:
		return SEEDLING_SCALE
	if age_seconds >= MATURITY_SECONDS:
		return 1.0
	var t := age_seconds / MATURITY_SECONDS
	# The same ease-out the stage curve uses: quick early gains, tapering
	# toward full size, which is how a real stem puts on height.
	var eased := 1.0 - pow(1.0 - t, 1.8)
	return lerp(SEEDLING_SCALE, 1.0, eased)


## Does a tree at this stage bear fruit and yield real wood?
func is_productive(stage: int) -> bool:
	return stage >= PRODUCTIVE_STAGE
