extends GutTest

## Pure state machine for a Builder worker (see docs/concept/
## timber_construction.md's NPC construction section: the Lumberjack's own
## loop stops at DEPOSIT -- CARRY_MATERIAL/PLACE_PIECE, an NPC actually
## building a structure piece by piece, is what this adds). Mirrors
## LumberjackBehavior/LogisticsBehavior's own split exactly: this decides
## WHEN things happen; BuilderMarker owns the actual world effect (finding
## the target piece, withdrawing its real cost from Storage, walking,
## placing). A deliberately SIMPLER real slice than the doc's own full
## SEEK_FOREST->WALK_TO_TREE->FELL->CARRY_LOG->SHAPE chain: raw-material
## sourcing is already covered by the real Sägewerk/Storage/Logistics chain,
## so a Builder does not re-fell trees itself.
##
## SEEKING -> WITHDRAWING -> CARRYING -> PLACING -> SEEKING.
##
## WITHDRAWING and PLACING are each ONE real-world phase covering BOTH a walk
## leg AND its own timed action (unlike LogisticsBehavior's separate
## APPROACHING/COLLECTING split) -- a deliberately simpler 4-phase shape per
## this pass's own brief. The marker only calls advance_withdraw/
## advance_place once it has ALREADY arrived (tracked on the marker side, the
## same "the caller decides arrival via real distance" discipline every other
## behavior file in this codebase already uses for its own walk legs), so the
## timed clock never starts ticking before the worker is actually there --
## mirroring LumberjackBehavior's own two-separate-timed-methods precedent
## (advance() for FELLING, advance_deposit() for DEPOSIT) rather than
## LogisticsBehavior's single always-ticking advance().

const BuilderBehavior = preload("res://src/gameplay/builder_behavior.gd")

var behavior: BuilderBehavior


func before_each():
	behavior = BuilderBehavior.new()


func test_starts_seeking():
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


# -- SEEKING -> WITHDRAWING ----------------------------------------------------

func test_cannot_commit_before_the_rehunt_interval():
	assert_false(behavior.can_commit())


func test_can_commit_once_the_rehunt_interval_elapses():
	behavior.advance(BuilderBehavior.REHUNT_SECONDS)
	assert_true(behavior.can_commit())


func test_begin_withdraw_fails_before_it_can_commit():
	assert_false(behavior.begin_withdraw())
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


func test_begin_withdraw_succeeds_once_committable():
	behavior.advance(BuilderBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_withdraw())
	assert_eq(behavior.phase, BuilderBehavior.Phase.WITHDRAWING)


func _withdrawing() -> void:
	behavior.advance(BuilderBehavior.REHUNT_SECONDS)
	behavior.begin_withdraw()


# -- WITHDRAWING: a timed pickup, only once the marker says "arrived" --------

func test_advance_withdraw_is_a_no_op_outside_withdrawing():
	assert_false(behavior.advance_withdraw(1000.0))
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


func test_withdrawing_does_not_resolve_before_its_duration():
	_withdrawing()
	assert_false(behavior.advance_withdraw(BuilderBehavior.WITHDRAW_SECONDS * 0.5))
	assert_eq(behavior.phase, BuilderBehavior.Phase.WITHDRAWING)


func test_withdrawing_resolves_once_its_duration_elapses():
	_withdrawing()
	assert_true(behavior.advance_withdraw(BuilderBehavior.WITHDRAW_SECONDS))
	# advance_withdraw only reports completion -- start_carry (below) is the
	# caller's own confirmation that the real withdrawal actually succeeded,
	# mirroring how LogisticsMarker only credits a collection after checking
	# real stock, not on the timer's own say-so.
	assert_eq(behavior.phase, BuilderBehavior.Phase.WITHDRAWING)


# -- start_carry: the caller confirms the real withdrawal succeeded ----------

func test_start_carry_fails_outside_withdrawing():
	assert_false(behavior.start_carry())


func test_start_carry_moves_to_carrying():
	_withdrawing()
	behavior.advance_withdraw(BuilderBehavior.WITHDRAW_SECONDS)
	assert_true(behavior.start_carry())
	assert_eq(behavior.phase, BuilderBehavior.Phase.CARRYING)


# -- abort: give up on the current attempt (insufficient stock, no Storage --
# -- in range, target vanished) and retry later ------------------------------

func test_abort_returns_to_seeking_from_withdrawing():
	_withdrawing()
	behavior.abort()
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


func test_abort_resets_the_rehunt_clock():
	_withdrawing()
	behavior.abort()
	assert_false(behavior.can_commit())


# -- CARRYING -> PLACING: the second walk leg, to the build site -------------

func _carrying() -> void:
	_withdrawing()
	behavior.advance_withdraw(BuilderBehavior.WITHDRAW_SECONDS)
	behavior.start_carry()


func test_arrive_at_site_fails_outside_carrying():
	assert_false(behavior.arrive_at_site())


func test_arrive_at_site_moves_to_placing():
	_carrying()
	assert_true(behavior.arrive_at_site())
	assert_eq(behavior.phase, BuilderBehavior.Phase.PLACING)


func test_abort_returns_to_seeking_from_carrying():
	_carrying()
	behavior.abort()
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


# -- PLACING: a timed placement, then back to SEEKING regardless of ----------
# -- whether the real placement was accepted or refused (see BuilderMarker) --

func _placing() -> void:
	_carrying()
	behavior.arrive_at_site()


func test_advance_place_is_a_no_op_outside_placing():
	assert_false(behavior.advance_place(1000.0))


func test_placing_does_not_resolve_before_its_duration():
	_placing()
	assert_false(behavior.advance_place(BuilderBehavior.PLACE_SECONDS * 0.5))
	assert_eq(behavior.phase, BuilderBehavior.Phase.PLACING)


func test_placing_resolves_once_its_duration_elapses():
	_placing()
	assert_true(behavior.advance_place(BuilderBehavior.PLACE_SECONDS))
	# advance_place only reports completion -- finish_place (below) is what
	# actually returns to SEEKING, mirroring advance_withdraw/start_carry's
	# own split (the caller does the real placement attempt in between).
	assert_eq(behavior.phase, BuilderBehavior.Phase.PLACING)


func test_finish_place_returns_to_seeking():
	_placing()
	behavior.advance_place(BuilderBehavior.PLACE_SECONDS)
	behavior.finish_place()
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)


## A refused placement (BuildingPlacement/statics said no) still calls
## finish_place, not abort -- either way lands back in SEEKING with a fresh
## rehunt clock so a DIFFERENT piece gets a turn next (the caller's own
## round-robin cell selection is what makes "retried later" real, not an
## immediate re-attempt of the exact same refused piece).
func test_finish_place_resets_the_rehunt_clock_the_same_as_abort():
	_placing()
	behavior.advance_place(BuilderBehavior.PLACE_SECONDS)
	behavior.finish_place()
	assert_false(behavior.can_commit())


# -- a full round trip, one piece at a time -----------------------------------

func test_a_full_cycle_returns_to_seeking_ready_for_the_next_piece():
	behavior.advance(BuilderBehavior.REHUNT_SECONDS)
	behavior.begin_withdraw()
	behavior.advance_withdraw(BuilderBehavior.WITHDRAW_SECONDS)
	behavior.start_carry()
	behavior.arrive_at_site()
	behavior.advance_place(BuilderBehavior.PLACE_SECONDS)
	behavior.finish_place()
	assert_eq(behavior.phase, BuilderBehavior.Phase.SEEKING)

	behavior.advance(BuilderBehavior.REHUNT_SECONDS)
	assert_true(behavior.begin_withdraw(), "a fresh piece can start a fresh cycle")


# -- timing constants are real, grounded, test-pinned values, not eyeballed --
# -- (this project's no-manual-tuning rule) -- reusing the SAME real-action --
# -- pacing LogisticsBehavior already established for an analogous real ------
# -- action, rather than a second, freshly-eyeballed magnitude ---------------

func test_rehunt_seconds_is_pinned():
	assert_eq(BuilderBehavior.REHUNT_SECONDS, 2.0)


func test_withdraw_seconds_is_pinned():
	assert_eq(BuilderBehavior.WITHDRAW_SECONDS, 3.0)


func test_place_seconds_is_pinned():
	assert_eq(BuilderBehavior.PLACE_SECONDS, 2.0)
