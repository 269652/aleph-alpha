extends GutTest

## Pure state machine for the Farm's Farmer NPC (see
## docs/concept/npc_farm_production.md). Mirrors LumberjackBehavior's own
## split: this decides WHEN things happen (SEEKING -> APPROACHING ->
## WORKING -> SEEKING); FarmerMarker owns the actual world effect (which
## FarmPlot needs attention, walking to it, performing the till/water/
## harvest action, crediting the Farm's own StructureStock). Simpler than
## LumberjackBehavior's own 5-phase loop -- a Farm's plots are its own fixed
## fixtures, so there's no separate CARRYING leg back to a distant worksite.

const FarmerBehavior = preload("res://src/gameplay/farmer_behavior.gd")

var behavior: FarmerBehavior


func before_each():
	behavior = FarmerBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, FarmerBehavior.Phase.SEEKING)


# -- SEEKING -> APPROACHING ---------------------------------------------------

func test_cannot_commit_before_the_rehunt_interval():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_passes():
	behavior.advance(FarmerBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_approach_fails_before_it_can_commit():
	assert_false(behavior.begin_approach())
	assert_eq(behavior.phase, FarmerBehavior.Phase.SEEKING)


func test_begin_approach_succeeds_once_it_can_commit():
	behavior.advance(FarmerBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_approach())
	assert_eq(behavior.phase, FarmerBehavior.Phase.APPROACHING)


# -- APPROACHING -> WORKING ---------------------------------------------------

func _approaching() -> void:
	behavior.advance(FarmerBehavior.REHUNT_SECONDS)
	behavior.begin_approach()


func test_arrive_fails_outside_approaching():
	assert_false(behavior.arrive())


func test_arrive_enters_working():
	_approaching()
	assert_true(behavior.arrive())
	assert_eq(behavior.phase, FarmerBehavior.Phase.WORKING)


func test_abort_from_approaching_returns_to_seeking():
	_approaching()
	behavior.abort()
	assert_eq(behavior.phase, FarmerBehavior.Phase.SEEKING)


# -- WORKING: a single timed dwell, not a repeated swing ----------------------

func _working() -> void:
	_approaching()
	behavior.arrive()


func test_advance_is_a_no_op_outside_working():
	assert_false(behavior.advance(100.0))


func test_no_completion_before_work_seconds_elapse():
	_working()
	assert_false(behavior.advance(FarmerBehavior.WORK_SECONDS * 0.5))
	assert_eq(behavior.phase, FarmerBehavior.Phase.WORKING)


func test_work_completes_once_work_seconds_elapse():
	_working()
	assert_true(behavior.advance(FarmerBehavior.WORK_SECONDS))


func test_abort_from_working_returns_to_seeking():
	_working()
	behavior.abort()
	assert_eq(behavior.phase, FarmerBehavior.Phase.SEEKING)


# -- WORKING -> SEEKING --------------------------------------------------------

func test_finish_work_returns_to_seeking():
	_working()
	behavior.advance(FarmerBehavior.WORK_SECONDS)
	behavior.finish_work()
	assert_eq(behavior.phase, FarmerBehavior.Phase.SEEKING)


## Full loop: a fresh SEEKING phase after finish_work has its own rehunt
## clock reset -- no leftover state leaks between one tended plot and the
## next.
func test_the_full_loop_can_repeat():
	_working()
	behavior.advance(FarmerBehavior.WORK_SECONDS)
	behavior.finish_work()
	assert_false(behavior.can_commit(), "a fresh SEEKING phase should have its own rehunt clock")
	behavior.advance(FarmerBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())
