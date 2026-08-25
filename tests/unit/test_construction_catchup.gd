extends GutTest

## Unloaded-settlement construction catch-up integration (variable-fidelity
## LOD). See docs/concept/timber_construction.md's "NPC construction: the
## two fidelities" section's own "Unloaded / offscreen fidelity"
## subsection. Mirrors test_chunk_ecology_catchup.gd's own test shape
## exactly, since construction_catchup.gd mirrors chunk_ecology_catchup.gd's
## own advance(state, elapsed_seconds, capacity) -> Dictionary contract.

const ConstructionCatchup = preload("res://src/world/construction_catchup.gd")
const ChunkEcologyCatchup = preload("res://src/world/chunk_ecology_catchup.gd")

var catchup: ConstructionCatchup


func before_each():
	catchup = ConstructionCatchup.new()


func _state(accumulated: float, required: float) -> Dictionary:
	return {"labor_hours_accumulated": accumulated, "labor_hours_required": required}


func _capacity(builder_count: float) -> Dictionary:
	return {"builder_count": builder_count}


func test_zero_elapsed_returns_unchanged_state():
	var out := catchup.advance(_state(2.0, 100.0), 0.0, _capacity(4.0))
	assert_almost_eq(out["labor_hours_accumulated"], 2.0, 0.0001)


func test_is_pure_does_not_mutate_input():
	var start := _state(2.0, 100.0)
	catchup.advance(start, 1.0e6, _capacity(4.0))
	assert_almost_eq(start["labor_hours_accumulated"], 2.0, 0.0001)


func test_deterministic():
	var start := _state(2.0, 100.0)
	var a := catchup.advance(start, 12345.0, _capacity(4.0))
	var b := catchup.advance(start, 12345.0, _capacity(4.0))
	assert_eq(a, b)


func test_advances_proportionally_to_elapsed_time():
	var short := catchup.advance(_state(0.0, 1000.0), ChunkEcologyCatchup.SECONDS_PER_DAY, _capacity(1.0))
	var long := catchup.advance(_state(0.0, 1000.0), ChunkEcologyCatchup.SECONDS_PER_DAY * 2.0, _capacity(1.0))
	assert_gt(long["labor_hours_accumulated"], short["labor_hours_accumulated"])


func test_advances_proportionally_to_builder_count():
	var one := catchup.advance(_state(0.0, 1000.0), ChunkEcologyCatchup.SECONDS_PER_DAY, _capacity(1.0))
	var four := catchup.advance(_state(0.0, 1000.0), ChunkEcologyCatchup.SECONDS_PER_DAY, _capacity(4.0))
	assert_almost_eq(four["labor_hours_accumulated"], one["labor_hours_accumulated"] * 4.0, 0.001)


func test_zero_builders_makes_no_progress_regardless_of_elapsed_time():
	var out := catchup.advance(_state(0.0, 1000.0), 1.0e9, _capacity(0.0))
	assert_almost_eq(out["labor_hours_accumulated"], 0.0, 0.0001)


## Pins HOURS_PER_BUILDER_PER_DAY directly -- the calibration this constant
## needs per the project's no-manual-tuning rule.
func test_one_builder_working_a_full_day_accumulates_the_pinned_hours_per_day():
	var out := catchup.advance(_state(0.0, 1000.0), ChunkEcologyCatchup.SECONDS_PER_DAY, _capacity(1.0))
	assert_almost_eq(out["labor_hours_accumulated"], ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY, 0.001)


## A project cannot "overshoot" done -- capped at its own requirement even
## with far more elapsed builder-hours available than it needs.
func test_never_exceeds_labor_hours_required():
	var out := catchup.advance(_state(0.0, 10.0), ChunkEcologyCatchup.SECONDS_PER_DAY * 50.0, _capacity(10.0))
	assert_almost_eq(out["labor_hours_accumulated"], 10.0, 0.0001)


## The doc's own "no amount of elapsed wall-clock time skips [the
## minimum-build-time floor] faster than builder_count many NPCs' worth of
## hours can accumulate" -- a genuinely huge elapsed-time jump must still be
## safe, deterministic, and bounded by MAX_CATCHUP_DAYS in ONE call, the
## same precedent EarthChunkManager.MAX_CATCHUP_DAYS already establishes for
## ecology/decay catch-up.
func test_huge_elapsed_time_jump_is_safe_and_bounded_in_one_call():
	var out := catchup.advance(_state(0.0, 1.0e12), 1.0e15, _capacity(3.0))
	assert_false(is_nan(out["labor_hours_accumulated"]))
	assert_false(is_inf(out["labor_hours_accumulated"]))
	var max_possible := ConstructionCatchup.MAX_CATCHUP_DAYS * ConstructionCatchup.HOURS_PER_BUILDER_PER_DAY * 3.0
	assert_almost_eq(out["labor_hours_accumulated"], max_possible, 0.001)


func test_negative_elapsed_seconds_treated_as_zero():
	var out := catchup.advance(_state(5.0, 1000.0), -100.0, _capacity(4.0))
	assert_almost_eq(out["labor_hours_accumulated"], 5.0, 0.0001)


func test_labor_hours_required_passes_through_state_unchanged():
	var out := catchup.advance(_state(0.0, 42.0), 100.0, _capacity(1.0))
	assert_almost_eq(out["labor_hours_required"], 42.0, 0.0001)


## A state dict missing a key (e.g. a fresh project with nothing
## accumulated yet) defaults sanely rather than crashing.
func test_missing_state_keys_default_to_zero():
	var out := catchup.advance({}, 100.0, _capacity(1.0))
	assert_almost_eq(out["labor_hours_accumulated"], 0.0, 0.0001)
	assert_almost_eq(out["labor_hours_required"], 0.0, 0.0001)
