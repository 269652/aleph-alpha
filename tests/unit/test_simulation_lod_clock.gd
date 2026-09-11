extends GutTest

## SimulationLodClock (src/gameplay/simulation_lod_clock.gd) -- one creature's
## own update clock, the single home of the rule every LOD-throttled marker's
## _lod_step used to carry as its own private copy of an accumulated-seconds
## gate (nine copies, in nine marker classes).
##
## Why it exists (FPS regression round 10, docs/concept/soil_fauna.md): a
## seconds-based interval alone INVERTS under load. At 4 fps a frame is
## 0.25s, so a distant creature's 0.5s interval elapses every second frame
## instead of every thirtieth -- the throttle meant to keep ~1,500 off-screen
## creatures cheap collapses to a 2x saving exactly when the frame needs it
## most, and every slow frame makes the next one slower. Measured live: ant
## foragers, fish and pollinators alone at 38 + 29 + 26 ms per frame at 4 fps.
##
## The rule: a creature updates only once BOTH its seconds interval AND that
## same interval expressed in frames at SimulationLod.REFERENCE_FPS have
## elapsed. At or above the reference rate the seconds gate is the stricter
## one and nothing changes; below it the frame gate takes over, so per-frame
## work is bounded regardless of frame rate. Each update hands over at most
## the creature's own interval of simulated time (or this frame's delta, if a
## single frame was itself longer) -- a stretch skipped under load is time a
## distant creature does NOT live through, rather than one giant step no
## behaviour was written to survive.

const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
const SimulationLodClock = preload("res://src/gameplay/simulation_lod_clock.gd")

const FAR_PX := 100000.0
const REFERENCE_FRAME := 1.0 / 60.0
const SLOW_FRAME := 0.25  # 4 fps -- the rate the regression was measured at


## Drives `clock` for `frames` frames of `delta` at a fixed distance, the way
## a marker's _process does, and collects every step the creature was handed.
func _updates_over(clock, frames: int, delta: float, distance_px: float) -> Array[float]:
	var steps: Array[float] = []
	for frame in frames:
		if not clock.tick(delta):
			continue
		var step: float = clock.take_step(distance_px)
		if step >= 0.0:
			steps.append(step)
	return steps


func test_frames_between_updates_is_the_seconds_interval_at_the_reference_frame_rate():
	assert_eq(SimulationLod.frames_between_updates(0.0), 1, "on screen: every frame")
	var far_frames: int = SimulationLod.frames_between_updates(FAR_PX)
	assert_eq(far_frames, roundi(SimulationLod.MAX_INTERVAL_SECONDS * SimulationLod.REFERENCE_FPS))
	assert_eq(far_frames, 30, "0.5s at 60fps is thirty frames -- pinned so the size of the saving stays visible")


func test_frames_between_updates_never_shortens_with_distance():
	var previous := 0
	for step in 40:
		var frames: int = SimulationLod.frames_between_updates(float(step) * 60.0)
		assert_gte(frames, previous, "a more distant creature must not cost more")
		previous = frames


func test_at_the_reference_frame_rate_a_distant_creature_updates_exactly_as_before():
	# The rule this replaces, restated here verbatim: accumulate every frame,
	# update on the first frame the accumulated seconds reach the interval,
	# hand over everything accumulated. Frame for frame, the clock must be
	# indistinguishable from it at the reference rate -- including the
	# floating-point detail that 30 x (1/60) lands just short of 0.5.
	var interval := SimulationLod.update_interval(FAR_PX)
	var seconds_only_accumulated := 0.0
	var seconds_only_steps: Array[float] = []
	var clock = SimulationLodClock.new()
	var clock_steps: Array[float] = []
	for frame in 300:
		seconds_only_accumulated += REFERENCE_FRAME
		if seconds_only_accumulated >= interval:
			seconds_only_steps.append(seconds_only_accumulated)
			seconds_only_accumulated = 0.0
		if clock.tick(REFERENCE_FRAME):
			var step: float = clock.take_step(FAR_PX)
			if step >= 0.0:
				clock_steps.append(step)
	assert_gt(seconds_only_steps.size(), 5, "the premise: several updates over five seconds")
	assert_eq(clock_steps.size(), seconds_only_steps.size(), "the same number of updates as the seconds-only gate")
	for i in clock_steps.size():
		assert_almost_eq(clock_steps[i], seconds_only_steps[i], 0.0001, "update %d must hand over the same time" % i)


func test_above_the_reference_frame_rate_the_seconds_gate_still_rules():
	# 150 frames at 144fps: the frame gate opens after 30 frames (0.21s), but
	# the creature still waits out its full 0.5s -- never MORE updates than
	# the seconds interval alone ever allowed.
	var steps := _updates_over(SimulationLodClock.new(), 150, 1.0 / 144.0, FAR_PX)
	assert_eq(steps.size(), 2)


func test_a_slow_frame_rate_does_not_update_a_distant_creature_more_often_per_frame():
	# 60 frames at 4fps. The seconds gate alone would fire every second
	# frame (30 updates); the frame gate holds it to the same per-frame
	# share the reference rate gets: once every thirty frames.
	var steps := _updates_over(SimulationLodClock.new(), 60, SLOW_FRAME, FAR_PX)
	assert_eq(steps.size(), 2)


func test_a_skipped_stretch_is_never_handed_over_as_one_giant_step():
	# The clock starts open, so the first update lands as soon as the seconds
	# interval is reached (frame 2 at 4fps); it is the SECOND update that
	# follows a full thirty-frame skip -- 7.5 real seconds.
	var steps := _updates_over(SimulationLodClock.new(), 32, SLOW_FRAME, FAR_PX)
	assert_eq(steps.size(), 2)
	assert_almost_eq(
		steps[1], SimulationLod.update_interval(FAR_PX) + SLOW_FRAME, 0.0001,
		"7.5 real seconds were skipped, but the creature simulates at most its own interval plus one frame -- the most the seconds-only gate ever handed over"
	)


func test_a_creature_on_screen_still_gets_every_frames_full_delta():
	var clock = SimulationLodClock.new()
	for frame in 5:
		assert_true(clock.tick(SLOW_FRAME), "on screen: the gate is open every frame")
		assert_almost_eq(clock.take_step(0.0), SLOW_FRAME, 0.0001)
	# A single long frame passes through whole -- the cap is about piled-up
	# skipped frames, never about one frame's own delta.
	assert_true(clock.tick(2.0))
	assert_almost_eq(clock.take_step(0.0), 2.0, 0.0001)


func test_a_creature_that_came_close_is_back_to_every_frame_after_its_next_update():
	var clock = SimulationLodClock.new()
	_updates_over(clock, 30, SLOW_FRAME, FAR_PX)  # one far update; its next skip is thirty frames
	# Distance is only re-read when the frame gate opens (that is exactly
	# what makes a skipped frame cheap), so the creature finishes the skip
	# it already committed to -- and then, being close, steps every frame.
	var skipped := 0
	while not clock.tick(SLOW_FRAME):
		skipped += 1
		assert_lt(skipped, 60, "the gate must reopen within one far skip")
	assert_almost_eq(clock.take_step(0.0), SLOW_FRAME, 0.0001)
	for frame in 3:
		assert_true(clock.tick(SLOW_FRAME))
		assert_almost_eq(clock.take_step(0.0), SLOW_FRAME, 0.0001)


## The scheduler's side of the contract (FPS regression round 11, see
## test_simulation_scheduler.gd): a parked marker ticks nothing, so on
## wake-up the clock is primed with the real time it was parked and must
## then behave exactly as if it had ticked every one of those frames.
func test_frames_until_next_is_the_skip_the_last_step_committed_to():
	var clock = SimulationLodClock.new()
	assert_eq(clock.frames_until_next(), 1, "fresh: due next frame")
	clock.tick(SimulationLod.MAX_INTERVAL_SECONDS)  # enough for the seconds gate at any distance
	assert_gte(clock.take_step(FAR_PX), 0.0, "precondition: a real step")
	assert_eq(clock.frames_until_next(), SimulationLod.frames_between_updates(FAR_PX))
	clock.tick(REFERENCE_FRAME)  # gate closed, but the commitment stands
	assert_eq(clock.frames_until_next(), SimulationLod.frames_between_updates(FAR_PX))


func test_a_resumed_clock_is_indistinguishable_from_one_that_ticked_every_parked_frame():
	var ticked = SimulationLodClock.new()
	var parked = SimulationLodClock.new()
	for clock in [ticked, parked]:
		clock.tick(SimulationLod.MAX_INTERVAL_SECONDS)  # enough for the seconds gate
		assert_gte(clock.take_step(FAR_PX), 0.0, "precondition: both took a real step")
	var skip: int = ticked.frames_until_next()
	assert_gt(skip, 1, "precondition: a real skip to be parked for")
	# One clock lives through the skip frame by frame; the other is parked
	# for skip - 1 frames (the scheduler's wake-up frame is ticked normally).
	for frame in skip - 1:
		assert_false(ticked.tick(SLOW_FRAME))
	parked.resume((skip - 1) * SLOW_FRAME)
	assert_eq(ticked.tick(SLOW_FRAME), parked.tick(SLOW_FRAME), "both gates open on the same frame")
	assert_almost_eq(ticked.take_step(FAR_PX), parked.take_step(FAR_PX), 0.0001, "and hand over the same (capped) time")


func test_with_nobody_to_be_far_from_the_clock_runs_at_full_rate():
	var clock = SimulationLodClock.new()
	assert_true(clock.tick(SLOW_FRAME))
	assert_almost_eq(clock.take_full_rate_step(), SLOW_FRAME, 0.0001)
	assert_true(clock.tick(SLOW_FRAME), "full rate: the gate stays open every frame")
	assert_almost_eq(clock.take_full_rate_step(), SLOW_FRAME, 0.0001)
