extends GutTest

## SimulationScheduler (src/gameplay/simulation_scheduler.gd) -- the driver
## that takes distant AND near creature markers out of the engine's own
## per-node _process dispatch entirely, stepping near ones every frame and
## far ones only on the frame their SimulationLodClock says they are due.
##
## Why it exists (FPS regression round 11, docs/concept/soil_fauna.md): round
## 10's clock bounded the WORK a distant creature does per frame, but not
## the cost of its _process callback existing -- ~7us per marker per frame
## for the engine to dispatch into GDScript, tick the clock and return, x
## ~2,500 live markers = 10-17ms of every frame spent on creatures doing
## nothing.
##
## Why it adopts a marker ONCE rather than parking/waking it with
## set_process(false)/(true) around every skip -- the first cut did exactly
## that and measured WORSE live (median 6 fps against 9): every toggle is an
## O(nodes) erase/insert in the SceneTree's process group plus a re-sort of
## that ~24,000-node group on every frame in which anything toggled, which
## with ~170 toggles a frame was every frame. So a marker's own engine
## _process is switched off exactly once, on its first real step, and from
## then on the scheduler calls its _process itself: every frame while its
## clock says "due next frame", otherwise on its due frame with the clock
## primed with the real time it waited -- the clock's whole contract (cap,
## distance re-read on wake) holds exactly as before. Nothing is adopted
## when no scheduler is current: every unit test that never sets one, and
## a world with nobody to be far from, behave exactly as before.

const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const SimulationLodClock = preload("res://src/gameplay/simulation_lod_clock.gd")
const SimulationScheduler = preload("res://src/gameplay/simulation_scheduler.gd")

const FRAME := 1.0 / 60.0
const SLOW_FRAME := 0.25
const FAR_PX := 100000.0
const MID_PX := 700.0  # inside the falloff: a multi-frame skip at 60fps


## The smallest thing that behaves like a LOD-throttled marker: ticks its
## clock in _process, steps when the gate opens, and hands itself to the
## scheduler after every real step -- the exact shape every marker's
## _lod_step now has.
class _Marker extends Node2D:
	var clock = SimulationLodClock.new()
	var distance_px := 0.0
	var steps := 0
	var last_step := -1.0
	func _process(delta: float) -> void:
		if not clock.tick(delta):
			return
		var step: float = clock.take_step(distance_px)
		if step < 0.0:
			return
		steps += 1
		last_step = step
		SimulationScheduler.adopt_or_park(self, clock)


var scheduler


func before_each():
	scheduler = SimulationScheduler.new()
	SimulationScheduler.set_current(scheduler)


func after_each():
	SimulationScheduler.set_current(null)


## A marker in the tree with engine processing on, that has just taken its
## first real step (one tick of the longest interval satisfies the seconds
## gate at any distance) -- so it has just been adopted.
func _adopted_marker(distance_px: float) -> _Marker:
	var marker := _Marker.new()
	marker.distance_px = distance_px
	add_child_autofree(marker)
	marker.set_process(true)
	marker._process(SimulationLod.MAX_INTERVAL_SECONDS)
	assert_eq(marker.steps, 1, "precondition: one real step, and with it the hand-off")
	return marker


func test_an_adopted_marker_never_receives_the_engines_process_again():
	var near := _adopted_marker(0.0)
	var far := _adopted_marker(FAR_PX)
	assert_false(near.is_processing(), "near or far, the scheduler drives it from now on")
	assert_false(far.is_processing())
	for frame in 40:
		scheduler.advance(FRAME)
	assert_false(near.is_processing(), "and that never flips back -- no process-group churn")
	assert_false(far.is_processing())


func test_a_near_marker_is_stepped_by_the_scheduler_every_frame():
	var near := _adopted_marker(0.0)
	for frame in 10:
		scheduler.advance(FRAME)
	assert_eq(near.steps, 1 + 10, "one step per frame, exactly as the engine gave it")
	assert_almost_eq(near.last_step, FRAME, 0.0001, "with the frame's own delta")
	assert_eq(scheduler.active_count(), 1)
	assert_eq(scheduler.parked_count(), 0)


func test_a_far_marker_is_parked_for_exactly_the_frames_its_clock_would_skip():
	var far := _adopted_marker(FAR_PX)
	var skip: int = far.clock.frames_until_next()
	assert_eq(skip, SimulationLod.frames_between_updates(FAR_PX), "precondition")
	assert_eq(scheduler.parked_count(), 1)
	assert_eq(scheduler.active_count(), 0)
	for frame in skip - 1:
		scheduler.advance(FRAME)
		assert_eq(far.steps, 1, "untouched on frame %d of %d" % [frame + 1, skip])
	scheduler.advance(FRAME)
	if far.steps == 1:
		# 30 x 1/60 can land a hair under 0.5 in float, in which case the
		# clock's seconds gate (rightly) takes one more frame -- exactly what
		# the old per-frame gate did too (see test_simulation_lod_clock.gd).
		scheduler.advance(FRAME)
	assert_eq(far.steps, 2, "stepped on its due frame")
	assert_eq(scheduler.parked_count(), 1, "and, still far, parked again for the next skip")


func test_a_woken_marker_gets_the_time_it_waited_and_the_clocks_cap_still_applies():
	var mid := _adopted_marker(MID_PX)
	var skip: int = mid.clock.frames_until_next()
	for frame in skip:
		scheduler.advance(FRAME)
	assert_eq(mid.steps, 2)
	assert_almost_eq(mid.last_step, skip * FRAME, 0.0001, "exactly the frames it waited, the wake-up frame included")

	var far := _adopted_marker(FAR_PX)
	var far_skip: int = far.clock.frames_until_next()
	for frame in far_skip:
		scheduler.advance(SLOW_FRAME)  # 4fps: 7.5 real seconds pass
	assert_eq(far.steps, 2)
	assert_almost_eq(
		far.last_step, SimulationLod.update_interval(FAR_PX) + SLOW_FRAME, 0.0001,
		"parked or not, a creature never simulates more than its interval plus one frame at once"
	)


func test_a_marker_that_comes_close_moves_from_the_wheel_to_every_frame_and_back():
	var marker := _adopted_marker(FAR_PX)
	var skip: int = marker.clock.frames_until_next()
	marker.distance_px = 0.0  # the player arrived while it was parked
	for frame in skip:
		scheduler.advance(FRAME)
	assert_eq(marker.steps, 2, "woken on its due frame, where it re-reads its distance")
	assert_eq(scheduler.active_count(), 1, "near now: stepped every frame")
	assert_eq(scheduler.parked_count(), 0)
	for frame in 5:
		scheduler.advance(FRAME)
	assert_eq(marker.steps, 7)
	marker.distance_px = FAR_PX  # the player left again
	# Far now, its next step waits for its seconds interval to accumulate
	# (it is stepped -- and refused -- every frame until then, never lost),
	# and only that step puts it back on the wheel.
	var frames_until_parked := 0
	var far_interval_frames := SimulationLod.frames_between_updates(FAR_PX)
	while scheduler.active_count() > 0 and frames_until_parked < far_interval_frames + 2:
		scheduler.advance(FRAME)
		frames_until_parked += 1
	assert_eq(scheduler.active_count(), 0, "far again: back on the wheel")
	assert_eq(scheduler.parked_count(), 1)
	assert_lte(frames_until_parked, SimulationLod.frames_between_updates(FAR_PX) + 1, "within one far interval")


func test_a_woken_marker_whose_seconds_gate_is_not_yet_open_is_retried_every_frame_not_lost():
	# Above the reference frame rate the frame gate opens before the seconds
	# gate does (see SimulationLodClock): the woken marker must keep being
	# stepped every frame until it can take its step, never dropped.
	var far := _adopted_marker(FAR_PX)
	var skip: int = far.clock.frames_until_next()
	var fast_frame := 1.0 / 144.0
	for frame in skip:
		scheduler.advance(fast_frame)
	assert_eq(far.steps, 1, "precondition: the frame gate opened but 0.5s has not passed")
	assert_eq(scheduler.active_count(), 1, "kept in hand, retried every frame")
	var retries := 0
	while far.steps < 2 and retries < 200:
		scheduler.advance(fast_frame)
		retries += 1
	assert_eq(far.steps, 2, "it steps once its seconds interval really has elapsed")
	assert_eq(scheduler.parked_count(), 1, "and goes back on the wheel")


func test_a_marker_freed_while_parked_or_active_is_dropped_without_error():
	var far := _adopted_marker(FAR_PX)
	var near := _adopted_marker(0.0)
	var skip: int = far.clock.frames_until_next()
	for marker in [far, near]:
		remove_child(marker)
		marker.free()
	for frame in skip + 1:
		scheduler.advance(FRAME)
	assert_eq(scheduler.parked_count(), 0)
	assert_eq(scheduler.active_count(), 0)
	pass_test("no error touching the freed markers")


func test_nothing_is_adopted_when_no_scheduler_is_current():
	SimulationScheduler.set_current(null)
	var marker := _Marker.new()
	marker.distance_px = FAR_PX
	add_child_autofree(marker)
	marker.set_process(true)
	marker._process(SimulationLod.MAX_INTERVAL_SECONDS)
	assert_eq(marker.steps, 1)
	assert_true(marker.is_processing(), "no scheduler: the engine keeps driving it, exactly as before")


## PerfReport's census (src/gameplay/perf_report.gd): a point-in-time count
## of everything this scheduler has taken over, split into stepped-every-
## frame and parked-on-the-wheel -- the one place the live creature
## population is actually known per frame.
func test_census_counts_adopted_in_hand_and_parked():
	_adopted_marker(0.0)
	_adopted_marker(FAR_PX)

	assert_eq(scheduler.census(), {"adopted": 2, "in_hand": 1, "parked": 1})


## Step profiling for PerfReport: with profiling on, advance() times every
## marker step it makes and take_step_profile() hands back usec and step
## counts per marker class since the last take -- off by default, so a
## plain game pays nothing for it.
func test_step_profile_is_empty_unless_profiling_is_on():
	_adopted_marker(0.0)
	scheduler.advance(FRAME)

	assert_eq(scheduler.take_step_profile(), {})


func test_step_profile_counts_and_times_every_step_per_class_then_resets():
	scheduler.set_step_profiling(true)
	_adopted_marker(0.0)
	_adopted_marker(0.0)
	scheduler.advance(FRAME)

	var profile: Dictionary = scheduler.take_step_profile()

	assert_eq(profile.size(), 1, "both markers share one class")
	var entry: Dictionary = profile.values()[0]
	assert_eq(entry["steps"], 2, "one step per in-hand marker this frame")
	assert_true(entry["usec"] >= 0, "wall time is recorded, never negative")
	assert_eq(scheduler.take_step_profile(), {}, "taking resets the profile")



## The proximity sweep (FPS regression round 13): with the far interval at
## two seconds, a creature the player walks up to must not sit frozen until
## its due frame. Every frame the scheduler looks at one slice of the parked
## wheel and wakes anything now within WAKE_RADIUS_PX of the focus (the
## local player), so the whole wheel is swept every PARKED_SWEEP_FRAMES
## frames -- a bounded, small cost, and a bounded reaction lag.
func test_the_wake_radius_covers_the_full_rate_radius_with_a_margin():
	assert_gt(SimulationScheduler.WAKE_RADIUS_PX, SimulationLod.FULL_RATE_RADIUS_PX)
	assert_lte(SimulationScheduler.WAKE_RADIUS_PX, SimulationLod.FULL_RATE_RADIUS_PX * 2.0)
	assert_eq(SimulationScheduler.PARKED_SWEEP_FRAMES, 10)


func test_a_parked_marker_the_focus_reaches_is_woken_within_one_sweep():
	scheduler.set_focus_position(Vector2.ZERO)
	var far := _adopted_marker(FAR_PX)
	far.position = Vector2(FAR_PX, 0.0)
	var due_in: int = far.clock.frames_until_next()
	assert_gt(due_in, SimulationScheduler.PARKED_SWEEP_FRAMES + 1, "precondition: parked well beyond one sweep")

	far.position = Vector2(SimulationScheduler.WAKE_RADIUS_PX * 0.5, 0.0)  # the player walked up
	far.distance_px = far.position.length()
	var frames_until_step := 0
	for frame in SimulationScheduler.PARKED_SWEEP_FRAMES + 1:
		scheduler.advance(FRAME)
		frames_until_step += 1
		if far.steps == 2:
			break

	assert_eq(far.steps, 2, "woken and stepped before its original due frame")
	assert_lte(frames_until_step, SimulationScheduler.PARKED_SWEEP_FRAMES + 1)
	assert_eq(scheduler.active_count(), 1, "now near, it stays in hand")


func test_a_parked_marker_still_far_from_the_focus_is_left_parked():
	scheduler.set_focus_position(Vector2.ZERO)
	var far := _adopted_marker(FAR_PX)
	far.position = Vector2(FAR_PX, 0.0)
	for frame in SimulationScheduler.PARKED_SWEEP_FRAMES + 1:
		scheduler.advance(FRAME)
	assert_eq(far.steps, 1, "no wake without proximity")
	assert_eq(scheduler.parked_count(), 1)


func test_without_a_focus_the_sweep_wakes_nothing():
	var far := _adopted_marker(FAR_PX)
	far.position = Vector2.ZERO
	for frame in SimulationScheduler.PARKED_SWEEP_FRAMES + 1:
		scheduler.advance(FRAME)
	assert_eq(far.steps, 1)
