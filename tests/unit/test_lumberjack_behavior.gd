extends GutTest

## Pure state machine for the Sägewerk's Lumberjack NPC (see
## docs/concept/timber_construction.md's NPC construction section). Mirrors
## CarrionForageBehavior's split exactly: this decides WHEN things happen
## (SEEKING -> APPROACHING -> FELLING -> CARRYING -> DEPOSIT -> SEEKING); the
## marker owns the actual world effect (finding/walking to/swinging at a real
## ChoppableTree, dropping items at the Sägewerk).

const LumberjackBehavior = preload("res://src/gameplay/lumberjack_behavior.gd")

var behavior: LumberjackBehavior


func before_each():
	behavior = LumberjackBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, LumberjackBehavior.Phase.SEEKING)


# -- SEEKING -> APPROACHING ---------------------------------------------------

func test_cannot_commit_before_the_rehunt_interval():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_passes():
	behavior.advance(LumberjackBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_approach_fails_before_it_can_commit():
	assert_false(behavior.begin_approach())
	assert_eq(behavior.phase, LumberjackBehavior.Phase.SEEKING)


func test_begin_approach_succeeds_once_it_can_commit():
	behavior.advance(LumberjackBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_approach())
	assert_eq(behavior.phase, LumberjackBehavior.Phase.APPROACHING)


# -- APPROACHING -> FELLING ---------------------------------------------------

func _approaching() -> void:
	behavior.advance(LumberjackBehavior.REHUNT_SECONDS)
	behavior.begin_approach()


func test_arrive_fails_outside_approaching():
	assert_false(behavior.arrive())


func test_arrive_enters_felling():
	_approaching()
	assert_true(behavior.arrive())
	assert_eq(behavior.phase, LumberjackBehavior.Phase.FELLING)


func test_abort_from_approaching_returns_to_seeking():
	_approaching()
	behavior.abort()
	assert_eq(behavior.phase, LumberjackBehavior.Phase.SEEKING)


# -- FELLING: a swing lands every SWING_INTERVAL, only while felling ---------

func _felling() -> void:
	_approaching()
	behavior.arrive()


func test_advance_is_a_no_op_outside_felling_and_deposit():
	assert_false(behavior.advance(100.0))


func test_no_swing_before_the_swing_interval_elapses():
	_felling()
	assert_false(behavior.advance(LumberjackBehavior.SWING_INTERVAL * 0.5))


func test_a_swing_lands_once_the_swing_interval_elapses():
	_felling()
	assert_true(behavior.advance(LumberjackBehavior.SWING_INTERVAL))


func test_swings_keep_landing_on_their_own_interval():
	_felling()
	var swings := 0
	for i in 10:
		if behavior.advance(LumberjackBehavior.SWING_INTERVAL):
			swings += 1
	assert_eq(swings, 10)


func test_abort_from_felling_returns_to_seeking():
	_felling()
	behavior.abort()
	assert_eq(behavior.phase, LumberjackBehavior.Phase.SEEKING)


# -- FELLING -> CARRYING -------------------------------------------------------

func test_start_carry_fails_outside_felling():
	assert_false(behavior.start_carry())


func test_start_carry_enters_carrying():
	_felling()
	assert_true(behavior.start_carry())
	assert_eq(behavior.phase, LumberjackBehavior.Phase.CARRYING)


# -- CARRYING -> DEPOSIT -------------------------------------------------------

func _carrying() -> void:
	_felling()
	behavior.start_carry()


func test_arrive_home_fails_outside_carrying():
	assert_false(behavior.arrive_home())


func test_arrive_home_enters_deposit():
	_carrying()
	assert_true(behavior.arrive_home())
	assert_eq(behavior.phase, LumberjackBehavior.Phase.DEPOSIT)


# -- DEPOSIT -> SEEKING ---------------------------------------------------------

func _depositing() -> void:
	_carrying()
	behavior.arrive_home()


func test_advance_deposit_is_a_no_op_outside_deposit():
	assert_false(behavior.advance_deposit(100.0))


func test_no_deposit_completion_before_deposit_seconds_elapse():
	_depositing()
	assert_false(behavior.advance_deposit(LumberjackBehavior.DEPOSIT_SECONDS * 0.5))
	assert_eq(behavior.phase, LumberjackBehavior.Phase.DEPOSIT)


func test_deposit_completes_once_deposit_seconds_elapse():
	_depositing()
	assert_true(behavior.advance_deposit(LumberjackBehavior.DEPOSIT_SECONDS))


func test_finish_deposit_returns_to_seeking():
	_depositing()
	behavior.advance_deposit(LumberjackBehavior.DEPOSIT_SECONDS)
	behavior.finish_deposit()
	assert_eq(behavior.phase, LumberjackBehavior.Phase.SEEKING)


## Full loop: a fresh SEEKING phase after finish_deposit has its own rehunt
## clock reset, exactly like starting fresh -- no leftover state leaks
## between one felled tree and the next.
func test_the_full_loop_can_repeat():
	_depositing()
	behavior.advance_deposit(LumberjackBehavior.DEPOSIT_SECONDS)
	behavior.finish_deposit()
	assert_false(behavior.can_commit(), "a fresh SEEKING phase should have its own rehunt clock")
	behavior.advance(LumberjackBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())
