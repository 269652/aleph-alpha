extends GutTest

## How leaf litter accumulates and decays on the ground -- see
## docs/concept/leaf_litter.md.

const LeafLitter = preload("res://src/world/leaf_litter.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")


# -- how fast litter falls, by season ----------------------------------------

func test_autumn_sheds_the_most():
	assert_gt(LeafLitter.fall_rate("autumn"), LeafLitter.fall_rate("spring"))
	assert_gt(LeafLitter.fall_rate("autumn"), LeafLitter.fall_rate("summer"))


## A trickle, not nothing -- real wind damage and petal-drop, just far less
## of it than the real autumn shed.
func test_spring_and_summer_shed_a_light_trickle():
	assert_gt(LeafLitter.fall_rate("spring"), 0.0)
	assert_gt(LeafLitter.fall_rate("summer"), 0.0)
	assert_lt(LeafLitter.fall_rate("spring"), LeafLitter.fall_rate("autumn") * 0.2)
	assert_lt(LeafLitter.fall_rate("summer"), LeafLitter.fall_rate("autumn") * 0.2)


## An already-bare winter canopy has nothing left to shed.
func test_winter_sheds_nothing():
	assert_eq(LeafLitter.fall_rate("winter"), 0.0)


## An unrecognised season falls back to shedding nothing rather than
## crashing a chunk step -- the safe default, same reasoning
## IllustratedTree's own season fallback documents (unexpectedly bare reads
## as wrong; unexpectedly stops shedding just does nothing extra).
func test_an_unknown_season_sheds_nothing():
	assert_eq(LeafLitter.fall_rate("solstice"), 0.0)


# -- accumulating and decaying over time -------------------------------------

func test_litter_accumulates_over_time_in_autumn():
	var after := LeafLitter.advance(0.0, SeasonCycle.SECONDS_PER_YEAR * 0.01, "autumn")
	assert_gt(after, 0.0)


## More elapsed time means more litter, evaluated directly rather than
## accumulated in tiny per-frame steps -- the real bug FruitingModel's own
## history documents (increments this small round to zero in floating
## point, silently losing the whole accumulation). advance() is checked
## here against a real, very small delta specifically because that is
## exactly the size of step a per-frame caller would use.
func test_a_tiny_delta_still_accumulates_something():
	var tiny_delta := 1.0 / 60.0 # one frame at 60fps
	var after := LeafLitter.advance(0.0, tiny_delta, "autumn")
	assert_gt(after, 0.0, "a single frame's worth of autumn fall rounded away to nothing")


func test_more_elapsed_time_means_more_litter():
	var short := LeafLitter.advance(0.0, 1000.0, "autumn")
	var long := LeafLitter.advance(0.0, 5000.0, "autumn")
	assert_gt(long, short)


func test_litter_never_exceeds_the_max():
	var after := LeafLitter.advance(0.0, SeasonCycle.SECONDS_PER_YEAR * 100.0, "autumn")
	assert_eq(after, LeafLitter.MAX_LITTER)


## Litter thins on its own even when nothing is falling and nothing is
## eating it -- real decomposition, not just depletion by a decomposer's own
## bite.
func test_litter_decays_over_time_with_nothing_falling():
	var after := LeafLitter.advance(LeafLitter.MAX_LITTER, 5000.0, "winter")
	assert_lt(after, LeafLitter.MAX_LITTER)


func test_litter_never_goes_negative():
	var after := LeafLitter.advance(0.0, SeasonCycle.SECONDS_PER_YEAR * 100.0, "winter")
	assert_eq(after, 0.0)


## Zero elapsed time is a no-op -- asking twice in the same instant (a
## reload immediately followed by a live step, say) must not double-count.
func test_zero_elapsed_time_changes_nothing():
	assert_eq(LeafLitter.advance(12.0, 0.0, "autumn"), 12.0)


## AUTUMN_FALL_RATE alone is calibrated to fill MAX_LITTER over one autumn
## season, but decay runs the whole time too -- the real, computed net
## effect of both together is exactly half that (fall rate is exactly
## double the decay rate by construction), not the full MAX_LITTER a reader
## of AUTUMN_FALL_RATE's own doc comment alone might assume. Pinned here so
## that assumption is checked, not just asserted in a comment.
func test_a_full_autumn_season_reaches_exactly_half_the_max():
	var after := LeafLitter.advance(0.0, SeasonCycle.SECONDS_PER_YEAR / 4.0, "autumn")
	assert_almost_eq(after, LeafLitter.MAX_LITTER / 2.0, 0.001)
