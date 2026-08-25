extends RefCounted

## Pure state machine for a Builder worker -- the piece the doc's own NPC
## construction section names as the last missing loop stage (see
## docs/concept/timber_construction.md: the Lumberjack's own loop stops at
## DEPOSIT; CARRY_MATERIAL/PLACE_PIECE, an NPC actually building a structure
## piece by piece, did not exist yet). Mirrors LumberjackBehavior/
## LogisticsBehavior's own split exactly: this decides WHEN things happen;
## BuilderMarker owns the actual world effect (finding the target piece,
## withdrawing its real cost from Storage, walking, placing). A deliberately
## SIMPLER real slice than the doc's own full SEEK_FOREST->WALK_TO_TREE->
## FELL->CARRY_LOG->SHAPE chain: raw-material sourcing is already covered by
## the real Sägewerk/Storage/Logistics chain that exists today, so a Builder
## does not re-fell trees itself.
##
## SEEKING -> WITHDRAWING -> CARRYING -> PLACING -> SEEKING.
##
## WITHDRAWING and PLACING are each ONE real-world phase covering BOTH a walk
## leg AND its own timed action -- a deliberately simpler 4-phase shape than
## LogisticsBehavior's separate APPROACHING/COLLECTING split, per this pass's
## own brief. The caller (BuilderMarker) only calls advance_withdraw/
## advance_place once it has ALREADY arrived (tracked marker-side via real
## distance, the same "the caller decides arrival" discipline every other
## behavior file in this codebase already uses for its own walk legs), so the
## timed clock never starts ticking before the worker is actually there.
## Mirrors LumberjackBehavior's own two-separate-timed-methods precedent
## (advance() for FELLING, advance_deposit() for DEPOSIT) rather than
## LogisticsBehavior's single always-ticking advance() -- both real
## precedents already in this codebase, this file picks the one that fits a
## caller-gated-on-arrival timed phase.

enum Phase { SEEKING, WITHDRAWING, CARRYING, PLACING }

## How long an idle worker waits before picking a new target piece -- the
## same short "an idle worker checks again shortly" coordination pause
## LumberjackBehavior.REHUNT_SECONDS/LogisticsBehavior.REHUNT_SECONDS already
## use, kept as its own independently-pinned constant here rather than a
## cross-file reference, matching how those two files each keep their own
## copy rather than importing one another's.
const REHUNT_SECONDS := 2.0

## How long withdrawing one piece's own real cost_of material from Storage
## takes, once physically at the Storage -- the same "long enough to read as
## a real action" pacing LogisticsBehavior.COLLECT_SECONDS already uses for
## an analogous real action (loading a producer's accumulated output onto a
## hand-cart); pinned independently here rather than cross-file-shared, the
## same "each file keeps its own timing constants" convention
## LumberjackBehavior/LogisticsBehavior already establish.
const WITHDRAW_SECONDS := 3.0

## How long fitting one real piece into the build takes, once physically at
## the build site -- the same real-action pacing LogisticsBehavior.
## DEPOSIT_SECONDS already uses for unloading cargo at Storage, independently
## pinned here.
const PLACE_SECONDS := 2.0

var phase := Phase.SEEKING

var _phase_elapsed := 0.0


## Whether this Builder is willing to commit to a newly-picked target piece
## right now: seeking, and past the re-hunt interval.
func can_commit() -> bool:
	return phase == Phase.SEEKING and _phase_elapsed >= REHUNT_SECONDS


## Commits to the piece the caller has already picked. Returns false (a
## no-op) if not yet willing to commit, so a caller can just offer a target
## and let this decide -- the same shape LumberjackBehavior.begin_approach/
## LogisticsBehavior.begin_approach already use.
func begin_withdraw() -> bool:
	if not can_commit():
		return false
	_enter(Phase.WITHDRAWING)
	return true


## Ticks the coordination-pause clock during SEEKING -- the same "no-op
## outside the relevant phase, just ticks the rehunt clock" contract
## LumberjackBehavior.advance already documents for its own SEEKING usage.
## Call this from SEEKING only; WITHDRAWING/PLACING have their own dedicated
## timed-tick methods below (advance_withdraw/advance_place), not ticked from
## here.
func advance(delta: float) -> void:
	if phase == Phase.SEEKING:
		_phase_elapsed += delta


## Ticks the timed withdrawal while WITHDRAWING -- call ONLY once the caller
## has confirmed real arrival at Storage (see this file's own header). Returns
## true exactly once, the tick the timed pickup completes; a no-op (false)
## outside WITHDRAWING, mirroring LumberjackBehavior.advance_deposit's own
## "no-op outside its own phase" contract. Reports completion of the TIMER
## only -- the caller still has to confirm the real withdrawal itself
## succeeded (see start_carry) before actually moving on, the same
## "the timer's own say-so isn't enough" discipline LogisticsMarker's own
## COLLECTED-outcome handling already models.
func advance_withdraw(delta: float) -> bool:
	if phase != Phase.WITHDRAWING:
		return false
	_phase_elapsed += delta
	return _phase_elapsed >= WITHDRAW_SECONDS


## The real withdrawal succeeded -- move to CARRYING with the material in
## hand. Returns false (a no-op) outside WITHDRAWING.
func start_carry() -> bool:
	if phase != Phase.WITHDRAWING:
		return false
	_enter(Phase.CARRYING)
	return true


## Arrived at the build site with material in hand -- caller decides
## "arrived" by real distance, not a timer, the same as every other walk leg
## in this codebase.
func arrive_at_site() -> bool:
	if phase != Phase.CARRYING:
		return false
	_enter(Phase.PLACING)
	return true


## Ticks the timed placement while PLACING -- call ONLY once the caller has
## confirmed real arrival at the build site. Returns true exactly once, the
## tick the timed placement action completes; a no-op (false) outside
## PLACING. Reports completion of the TIMER only -- the caller still attempts
## the real placement (BuildingPlacement.can_place, then build_at_global) in
## between this returning true and calling finish_place below.
func advance_place(delta: float) -> bool:
	if phase != Phase.PLACING:
		return false
	_phase_elapsed += delta
	return _phase_elapsed >= PLACE_SECONDS


## The placement attempt is over -- whether the real piece actually landed or
## was refused (BuildingPlacement said no floor beneath it, or the cell was
## no longer clear) makes no difference to the state machine: either way
## returns to SEEKING with a fresh rehunt clock, ready to pick the next
## target. A refused piece is simply left unplaced in the caller's own target
## dict -- the caller's own round-robin cell selection (see BuilderMarker) is
## what makes "skipped, retried later" real, not a special phase here.
func finish_place() -> void:
	_enter(Phase.SEEKING)


## Gives up on the current attempt (no Storage in range, insufficient real
## stock to withdraw, the target vanished) and returns to SEEKING with a
## fresh coordination pause -- valid from WITHDRAWING or CARRYING, mirroring
## LumberjackBehavior.abort/LogisticsBehavior.abort exactly.
func abort() -> void:
	_enter(Phase.SEEKING)


func _enter(next_phase: int) -> void:
	phase = next_phase
	_phase_elapsed = 0.0
