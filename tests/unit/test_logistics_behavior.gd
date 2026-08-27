extends GutTest

## Pure state machine for a Logistics worker (see
## docs/concept/timber_construction.md's "Storage, logistics, and the
## autonomous dependency chain" section): moves a production building's
## accumulated output into Storage. Mirrors CarrionForageBehavior's own
## split exactly -- SEEKING/APPROACHING is a walk bracketed by a timed
## action -- except a logistics run has TWO destinations (source, then
## storage), so it needs a second walk leg (CARRYING) a single-destination
## forager never needed.
##
## SEEKING -> APPROACHING -> COLLECTING -> CARRYING -> DEPOSITING -> SEEKING.

const LogisticsBehavior = preload("res://src/gameplay/logistics_behavior.gd")

var behavior: LogisticsBehavior


func before_each():
	behavior = LogisticsBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, LogisticsBehavior.Phase.SEEKING)


func test_cannot_commit_before_the_rehunt_interval_elapses():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_elapses():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_approach_fails_before_the_rehunt_interval():
	assert_false(behavior.begin_approach())
	assert_eq(behavior.phase, LogisticsBehavior.Phase.SEEKING)


func test_begin_approach_succeeds_once_committable():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_approach())
	assert_eq(behavior.phase, LogisticsBehavior.Phase.APPROACHING)


func test_arrive_at_source_moves_to_collecting():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	assert_true(behavior.arrive_at_source())
	assert_eq(behavior.phase, LogisticsBehavior.Phase.COLLECTING)


func test_arrive_at_source_fails_outside_approaching():
	assert_false(behavior.arrive_at_source())


func test_abort_returns_to_seeking_from_approaching():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_eq(behavior.phase, LogisticsBehavior.Phase.SEEKING)


func test_abort_resets_the_rehunt_clock():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.abort()
	assert_false(behavior.can_commit())


func test_advance_returns_none_outside_the_timed_phases():
	assert_eq(behavior.advance(1000.0), LogisticsBehavior.Outcome.NONE)


# -- collecting: a timed pickup action, then straight into CARRYING ----------

func test_collecting_does_not_resolve_before_its_duration():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	assert_eq(behavior.advance(LogisticsBehavior.COLLECT_SECONDS * 0.5), LogisticsBehavior.Outcome.NONE)
	assert_eq(behavior.phase, LogisticsBehavior.Phase.COLLECTING)


func test_collecting_resolves_and_moves_straight_to_carrying():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	assert_eq(behavior.advance(LogisticsBehavior.COLLECT_SECONDS), LogisticsBehavior.Outcome.COLLECTED)
	assert_eq(behavior.phase, LogisticsBehavior.Phase.CARRYING)


# -- carrying: the second walk leg, toward storage ----------------------------

func test_arrive_at_storage_fails_outside_carrying():
	assert_false(behavior.arrive_at_storage())


func test_arrive_at_storage_moves_to_depositing():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	behavior.advance(LogisticsBehavior.COLLECT_SECONDS)
	assert_true(behavior.arrive_at_storage())
	assert_eq(behavior.phase, LogisticsBehavior.Phase.DEPOSITING)


func test_abort_returns_to_seeking_from_carrying():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	behavior.advance(LogisticsBehavior.COLLECT_SECONDS)
	behavior.abort()
	assert_eq(behavior.phase, LogisticsBehavior.Phase.SEEKING)


# -- depositing: a timed drop-off action, then back to SEEKING ---------------

func test_depositing_does_not_resolve_before_its_duration():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	behavior.advance(LogisticsBehavior.COLLECT_SECONDS)
	behavior.arrive_at_storage()
	assert_eq(behavior.advance(LogisticsBehavior.DEPOSIT_SECONDS * 0.5), LogisticsBehavior.Outcome.NONE)
	assert_eq(behavior.phase, LogisticsBehavior.Phase.DEPOSITING)


func test_depositing_resolves_and_returns_to_seeking():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	behavior.advance(LogisticsBehavior.COLLECT_SECONDS)
	behavior.arrive_at_storage()
	assert_eq(behavior.advance(LogisticsBehavior.DEPOSIT_SECONDS), LogisticsBehavior.Outcome.DEPOSITED)
	assert_eq(behavior.phase, LogisticsBehavior.Phase.SEEKING)


## After a full round trip, the worker can't instantly re-commit -- same
## fresh-rehunt-clock reasoning as CarrionForageBehavior.abort.
func test_after_depositing_the_worker_cannot_instantly_recommit():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	behavior.advance(LogisticsBehavior.COLLECT_SECONDS)
	behavior.arrive_at_storage()
	behavior.advance(LogisticsBehavior.DEPOSIT_SECONDS)
	assert_false(behavior.can_commit())


## A single large delta that overshoots COLLECT_SECONDS still resolves the
## collect and lands in CARRYING (not stuck, not double-resolved) -- CARRYING
## is arrival-triggered like APPROACHING, so the overshoot is simply not
## meaningful past this point, rather than needing a carried-remainder chain
## the way GroundForageBehavior's single-destination loop does.
func test_a_large_delta_overshooting_collect_still_resolves_into_carrying():
	behavior.advance(LogisticsBehavior.REHUNT_SECONDS)
	behavior.begin_approach()
	behavior.arrive_at_source()
	assert_eq(behavior.advance(LogisticsBehavior.COLLECT_SECONDS + 10.0), LogisticsBehavior.Outcome.COLLECTED)
	assert_eq(behavior.phase, LogisticsBehavior.Phase.CARRYING)
	behavior.arrive_at_storage()
	# DEPOSITING starts its own fresh clock on arrival -- the overshoot above
	# does not carry through the (arrival-terminated) CARRYING leg.
	assert_eq(behavior.advance(LogisticsBehavior.DEPOSIT_SECONDS * 0.5), LogisticsBehavior.Outcome.NONE)
