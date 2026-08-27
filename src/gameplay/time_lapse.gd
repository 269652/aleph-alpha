extends RefCounted

## Running the world's ecology fast, so a year can be watched in a minute (see
## the /ecotest console command).
##
## Everything worth watching -- seasons turning, canopies going bare and back
## into leaf, fruit ripening and falling, saplings coming up and growing --
## is driven by the same `delta` the ecology steps take. Running it fast is
## therefore only a question of how much simulated time to hand them per frame.
##
## Pure and engine-free: this decides HOW MUCH time and IN WHAT SLICES. Doing
## the stepping is the caller's job.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How long a whole year takes by default, in real seconds.
##
## Long enough to watch: at a minute a year each season lasts fifteen real
## seconds, which is time to see a canopy turn rather than a flicker between
## two frames.
const DEFAULT_SECONDS_PER_YEAR := 45.0

## The largest slice of simulated time handed over in one go.
##
## Time has to arrive in slices rather than in one lump. The ecology steps
## accumulate toward their own intervals and act once when they cross them, so
## a single frame carrying an hour of world time would make each of them fire
## exactly once and discard the rest -- fruit ripening at frame rate rather
## than at its own rate, and accumulators running away because they are only
## ever decremented by one interval.
##
## Only the FINE group is sliced now (see World._step_ecology_fine) -- the
## clock, worm surfacing and fruiting -- and those are rate-based or reset
## their accumulator, so they tolerate a large slice. The heavy periodic work
## takes the whole frame at once instead, which is what its accumulators want.
##
## Sized against measurement: each slice costs about six milliseconds, so
## sixteen thirty-second slices spent 96ms a frame to buy only eight minutes of
## world time -- seven frames a second, and a season still taking the best part
## of a minute to turn. Fewer, bigger slices buy the same time for a quarter of
## the cost.
const SLICE_SECONDS := 240.0

## How many slices a single frame may simulate.
##
## There is only so much work a frame can do. Past this the world runs slower
## than asked rather than freezing -- which is the failure that matters here,
## because a frozen game cannot be watched at all.
const MAX_SLICES_PER_FRAME := 4

## How many times a SPAWNING step may run in one frame, whatever the rate.
##
## A time lapse accelerates phenology, not population. Seasons, ripening,
## falling fruit and growing saplings all read the world clock, and are what
## the lapse exists to show. Tree spread is different in kind -- it ADDS trees,
## a fixed few per tick -- and running it at the same multiple planted well
## over a thousand saplings a second, each an O(all-loaded-trees) scan. The
## game locked up within a frame or two of /ecotest being typed.
##
## One per frame. Saplings still appear, and the ones already in the ground
## still grow up fast, because growth is on the clock rather than on this.
const MAX_SPAWNING_STEPS_PER_FRAME := 1


## How many times faster than real time the world must run for a year to take
## `seconds_per_year`.
##
## Asked in terms of the thing being watched rather than as a bare multiplier:
## "600x" means nothing to someone waiting for autumn, and "a year in two
## minutes" does.
static func scale_for(seconds_per_year: float) -> float:
	if seconds_per_year <= 0.0:
		return SeasonCycle.SECONDS_PER_YEAR / DEFAULT_SECONDS_PER_YEAR
	return SeasonCycle.SECONDS_PER_YEAR / seconds_per_year


## The slices of simulated time to hand the ecology this frame.
##
## At normal speed this is simply the frame's own delta, unchanged, so nothing
## about the ordinary game runs through a different path than it did before.
static func slices(delta_seconds: float, scale: float) -> Array[float]:
	var out: Array[float] = []
	if delta_seconds <= 0.0:
		return out
	if scale <= 1.0:
		out.append(delta_seconds)
		return out

	var remaining := delta_seconds * scale
	while remaining > 0.0 and out.size() < MAX_SLICES_PER_FRAME:
		var slice: float = minf(remaining, SLICE_SECONDS)
		out.append(slice)
		remaining -= slice
	return out


## The simulated time the CALENDAR advances this frame -- the full amount
## asked for, uncapped.
##
## Deliberately NOT the sum of slices(). The slice budget is sized against
## what a frame can SIMULATE (see SLICE_SECONDS/MAX_SLICES_PER_FRAME, both
## measured), and tying the clock to it made the rate depend on the
## framerate: a lapse drops the game to a few frames a second, and the cap is
## per FRAME, so a frame asking for five thousand seconds of world time
## received nine hundred and sixty and the year ran several times slower than
## the number the player typed. Seasons and canopies are what /ecotest exists
## to show, and they read the CLOCK rather than the stepping -- so the clock
## runs at the rate asked and the ecology keeps its measured budget.
##
## This is the same separation EarthChunkManager.advance_world_age was split
## out from step_tree_spread for, applied one level up: advancing the clock is
## free, ADDING trees is not.
##
## A scale below one is clamped away: the lapse only ever makes the world run
## FASTER, and nothing may quietly run the calendar slow (or backwards).
static func calendar_seconds(delta_seconds: float, scale: float) -> float:
	if delta_seconds <= 0.0:
		return 0.0
	return delta_seconds * maxf(scale, 1.0)


## How long one season lasts, in real seconds, at this rate -- for reporting
## back to whoever asked for the run.
static func real_seconds_per_season(scale: float) -> float:
	var season_seconds := SeasonCycle.SECONDS_PER_YEAR / float(SeasonCycle.SEASONS.size())
	return season_seconds / maxf(scale, 0.0001)
