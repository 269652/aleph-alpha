extends GutTest

## SimulationScheduler (src/gameplay/simulation_scheduler.gd) -- the due-frame
## scheduler that lets a distant creature marker stop receiving _process at
## all for the frames its SimulationLodClock was going to skip anyway.
##
## Why it exists (FPS regression round 11, docs/concept/soil_fauna.md): round
## 10's clock bounded the WORK a distant creature does per frame, but not
## the cost of its _process callback existing -- measured at ~7us per marker
## per frame just for the engine to dispatch into GDScript, tick the clock
## and return, x ~2,500 live markers = 10-17ms of every frame, most of a 60
## fps budget, spent on creatures doing nothing. Parking a marker
## (set_process(false)) for exactly the frames its clock would skip makes a
## skipped frame cost that marker nothing at all; the scheduler keeps
## buckets keyed by due frame and touches only what is due.
##
## The clock's own contract is preserved end to end: a woken marker's clock
## is primed with the REAL time it spent parked (not the frame count), so
## the very same cap -- at most its interval plus one frame -- applies, and
## the marker's next _process opens the gate exactly as if it had ticked
## every frame. Nothing is parked when no scheduler is current (every unit
## test that never sets one, a dedicated server with nobody to be far from).

const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const SimulationLodClock = preload("res://src/gameplay/simulation_lod_clock.gd")
const SimulationScheduler = preload("res://src/gameplay/simulation_scheduler.gd")

const FRAME := 1.0 / 60.0
const SLOW_FRAME := 0.25
const FAR_PX := 100000.0
const MID_PX := 700.0  # inside the falloff: an 11-frame skip at 60fps

var scheduler


func before_each():
	scheduler = SimulationScheduler.new()
	SimulationScheduler.set_current(scheduler)


func after_each():
	SimulationScheduler.set_current(null)


## A processing node standing in for a marker, with a clock that has just
## taken a real step at `distance_px` -- exactly the state a marker is in
## when it decides whether to park.
func _stepped_marker(distance_px: float) -> Array:
	var marker := Node.new()
	add_child_autofree(marker)
	marker.set_process(true)
	var clock = SimulationLodClock.new()
	# One tick of the longest interval satisfies the seconds gate at any
	# distance, so the very next take_step is a real step that commits to a
	# skip -- the state a marker is in when it decides whether to park.
	assert_true(clock.tick(SimulationLod.MAX_INTERVAL_SECONDS))
	assert_gte(clock.take_step(distance_px), 0.0, "precondition: a real step happened")
	return [marker, clock]


func test_a_distant_marker_is_parked_for_exactly_the_frames_its_clock_would_skip():
	var pair := _stepped_marker(FAR_PX)
	var marker: Node = pair[0]
	var clock = pair[1]
	var skip: int = clock.frames_until_next()
	assert_eq(skip, SimulationLod.frames_between_updates(FAR_PX), "precondition")

	SimulationScheduler.park_if_far(marker, clock)
	assert_false(marker.is_processing(), "parked: no _process at all")
	assert_eq(scheduler.parked_count(), 1)

	for frame in skip - 1:
		scheduler.advance(FRAME)
		assert_false(marker.is_processing(), "still parked on frame %d of %d" % [frame + 1, skip])
	scheduler.advance(FRAME)
	assert_true(marker.is_processing(), "woken on its due frame")
	assert_eq(scheduler.parked_count(), 0)


func test_a_woken_clock_opens_on_its_next_tick_and_hands_over_the_time_it_was_parked():
	var pair := _stepped_marker(MID_PX)
	var clock = pair[1]
	var skip: int = clock.frames_until_next()
	SimulationScheduler.park_if_far(pair[0], clock)
	for frame in skip:
		scheduler.advance(FRAME)
	# The marker's next _process: the gate must be open, and the step must be
	# what a never-parked clock would have accumulated over the same frames.
	assert_true(clock.tick(FRAME), "the gate is open on the wake-up frame")
	var step: float = clock.take_step(MID_PX)
	assert_almost_eq(step, skip * FRAME, 0.0001, "exactly the frames it was parked for, this one included")


func test_the_wake_up_carries_real_time_so_the_clocks_cap_still_applies_under_load():
	var pair := _stepped_marker(FAR_PX)
	var clock = pair[1]
	var skip: int = clock.frames_until_next()
	SimulationScheduler.park_if_far(pair[0], clock)
	for frame in skip:
		scheduler.advance(SLOW_FRAME)  # 4fps: 7.5 real seconds pass
	assert_true(clock.tick(SLOW_FRAME))
	var step: float = clock.take_step(FAR_PX)
	assert_almost_eq(
		step, SimulationLod.update_interval(FAR_PX) + SLOW_FRAME, 0.0001,
		"parked or not, a creature never simulates more than its interval plus one frame at once"
	)


func test_a_near_marker_is_never_parked():
	var pair := _stepped_marker(0.0)
	SimulationScheduler.park_if_far(pair[0], pair[1])
	assert_true(pair[0].is_processing(), "on screen: every frame, untouched")
	assert_eq(scheduler.parked_count(), 0)


func test_nothing_is_parked_when_no_scheduler_is_current():
	SimulationScheduler.set_current(null)
	var pair := _stepped_marker(FAR_PX)
	SimulationScheduler.park_if_far(pair[0], pair[1])
	assert_true(pair[0].is_processing(), "no scheduler: the marker keeps ticking its own clock, exactly as before")


func test_a_marker_freed_while_parked_is_skipped_without_error():
	var pair := _stepped_marker(FAR_PX)
	var marker: Node = pair[0]
	var skip: int = pair[1].frames_until_next()
	SimulationScheduler.park_if_far(marker, pair[1])
	remove_child(marker)
	marker.free()
	for frame in skip:
		scheduler.advance(FRAME)
	assert_eq(scheduler.parked_count(), 0, "the dead entry was dropped on its due frame")
	pass_test("no error touching the freed marker")


func test_markers_due_on_different_frames_wake_independently():
	var far := _stepped_marker(FAR_PX)
	var mid := _stepped_marker(MID_PX)
	SimulationScheduler.park_if_far(far[0], far[1])
	SimulationScheduler.park_if_far(mid[0], mid[1])
	var mid_skip: int = mid[1].frames_until_next()
	var far_skip: int = far[1].frames_until_next()
	assert_lt(mid_skip, far_skip, "precondition: the nearer one is due sooner")
	for frame in mid_skip:
		scheduler.advance(FRAME)
	assert_true(mid[0].is_processing())
	assert_false(far[0].is_processing())
	for frame in far_skip - mid_skip:
		scheduler.advance(FRAME)
	assert_true(far[0].is_processing())
