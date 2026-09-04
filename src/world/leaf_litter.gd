extends RefCounted

## How leaf litter accumulates and decays on the ground -- see
## docs/concept/leaf_litter.md.
##
## Litter is a real, depletable resource (a decomposer's bite must actually
## reduce it), not a quantity re-derivable from the clock alone the way
## canopy snow depth is (see leaf_litter.md's own "Persisted, not
## re-derived" design pillar for why that distinction matters): what a chunk
## started with, what fell since, what rotted away, and what got eaten all
## have to be threaded through one running total rather than recomputed
## fresh each time. `advance()` folds fall and decay into that running total
## in one closed-form step -- the same shape `ChunkEcologyCatchup.advance`
## already uses for `fruit_stock` (`new = min(old + rate * elapsed, MAX)`),
## reused here rather than FruitingModel's per-tree stateless-curve shape,
## which solves a different problem (a ripening SCHEDULE, not a simple
## linear chunk aggregate). A decomposer's bite subtracts from the running
## total directly, the same contract `Carcass.take_bite` already has.

const SeasonCycle = preload("res://src/world/season_cycle.gd")

## How much litter (in the same abstract units the persisted per-chunk
## total is kept in) a chunk can hold before it saturates -- round, and
## deliberately not derived from any real-world figure, the same way
## `ChunkEcologyCatchup.FRUIT_STOCK_MAX` is a named cap rather than a
## computed one.
const MAX_LITTER := 100.0

## Litter units per second a chunk gains at autumn's own full rate --
## calibrated so, taken alone (ignoring the decay that is always running
## alongside it -- see test_a_full_autumn_season_reaches_exactly_half_the_max
## for the real, measured net effect of the two together), one full autumn
## season (a quarter of SeasonCycle.SECONDS_PER_YEAR) would fill MAX_LITTER
## from empty.
const AUTUMN_FALL_RATE := MAX_LITTER / (SeasonCycle.SECONDS_PER_YEAR / 4.0)

## How much of autumn's own rate spring and summer shed -- real wind damage
## and petal-drop, not nothing, but far less than the real autumn shed. A
## named fraction rather than a fitted curve, the same "one real table"
## precedent `FruitingModel.RIPENING_BY_SPECIES` already sets.
const _TRICKLE_SEASON_WEIGHT := 0.05

const _SEASON_WEIGHT := {
	"spring": _TRICKLE_SEASON_WEIGHT,
	"summer": _TRICKLE_SEASON_WEIGHT,
	"autumn": 1.0,
	"winter": 0.0,
}

## How much litter rots away per second, whatever the season and whether or
## not anything is eating it -- calibrated so a full, untouched pile
## (MAX_LITTER) decays back to nothing over two full seasons if nothing
## else falls or gets eaten in the meantime, twice the timescale fall alone
## takes to fill it -- litter that visibly outlasts the season that shed it,
## the way a real leaf layer does, rather than vanishing with the leaves
## still falling.
const DECAY_RATE := MAX_LITTER / (SeasonCycle.SECONDS_PER_YEAR / 2.0)


## Litter units per second a chunk gains from an unrecognised season falls
## back to shedding nothing -- the safe default: an unexpectedly bare canopy
## reads as broken (see IllustratedTree's own season fallback), but a
## momentarily-unrecognised season simply not adding extra litter does not.
static func fall_rate(season: String) -> float:
	return AUTUMN_FALL_RATE * _SEASON_WEIGHT.get(season, 0.0)


## `litter` after `elapsed_seconds` of falling (at `season`'s own rate) and
## decaying, folded into one closed-form step rather than accumulated in
## per-frame increments -- see this file's own doc comment for why, and
## test_a_tiny_delta_still_accumulates_something for the regression this
## guards against directly. Clamped to [0, MAX_LITTER]: a chunk cannot shed
## into the negative, and cannot overflow past what it can hold.
static func advance(litter: float, elapsed_seconds: float, season: String) -> float:
	var net := litter + (fall_rate(season) - DECAY_RATE) * elapsed_seconds
	return clampf(net, 0.0, MAX_LITTER)
