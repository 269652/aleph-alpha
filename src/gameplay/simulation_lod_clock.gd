extends RefCounted

## One creature's own update clock (see SimulationLod, and docs/concept/
## ecosystem_dynamics.md "Variable-fidelity simulation (LOD)").
##
## Every LOD-throttled marker used to carry its own copy of the same rule --
## accumulate delta, update once the accumulated seconds reach
## SimulationLod.update_interval(distance) -- nine near-identical _lod_step
## functions. This is that rule in one place, corrected for what the
## seconds-only version got wrong under load (SimulationLod.REFERENCE_FPS):
##
## A creature updates only once BOTH its seconds interval AND that same
## interval expressed in frames at the reference rate have elapsed. At or
## above the reference rate the seconds gate is the stricter one and behaviour
## is exactly what it was; below it the frame gate takes over, so a slow
## frame can never turn into MORE updates per frame.
##
## Each update hands the creature at most its own interval plus the current
## frame of simulated time -- exactly the most the seconds-only gate ever
## handed over (it fired on the first frame that crossed the interval, so it
## could overshoot by at most one frame). Under load, a distant creature's
## simulated time therefore runs slower than the wall clock instead of
## arriving as one giant step no behaviour was written to survive. Near the
## player the interval is zero, so an on-screen creature always gets every
## frame's full delta, as before.
##
## Two calls per frame instead of one, on purpose: tick() is the cheap part
## (two adds and an integer compare, no player lookup, no distance) and is
## all a skipped frame ever pays; the distance is only measured -- and the
## next skip length only re-decided -- when the frame gate actually opens.

var _accumulated_seconds := 0.0
var _frames_waited := 0
var _frames_until_next := 1
var _last_frame_delta := 0.0


## Feeds one engine frame. True when the frame gate is open and the caller
## should now measure its distance to the player and call take_step().
func tick(delta: float) -> bool:
	_accumulated_seconds += delta
	_last_frame_delta = delta
	_frames_waited += 1
	return _frames_waited >= _frames_until_next


## Only after tick() returned true. The seconds this creature should simulate
## now, or -1.0 when its seconds interval has not elapsed yet (which can only
## happen above the reference frame rate -- the gate then simply stays open
## and is re-checked next frame).
func take_step(distance_px: float) -> float:
	var interval := SimulationLod.update_interval(distance_px)
	if _accumulated_seconds < interval:
		return -1.0
	_frames_until_next = SimulationLod.frames_for_interval(interval)
	_frames_waited = 0
	var step := minf(_accumulated_seconds, interval + _last_frame_delta)
	_accumulated_seconds = 0.0
	return step


## Only after tick() returned true, when there is nobody to be far from (no
## player in the tree): full rate, every frame, the whole accumulated delta --
## exactly what every marker did in that case before.
func take_full_rate_step() -> float:
	_frames_until_next = 1
	_frames_waited = 0
	var step := _accumulated_seconds
	_accumulated_seconds = 0.0
	return step


## The skip the last take_step() committed to, in frames; 1 means "due next
## frame". Read by SimulationScheduler.park_if_far to know how long a marker
## can go without _process at all (FPS regression round 11).
func frames_until_next() -> int:
	return _frames_until_next


## The scheduler's wake-up: a parked marker ticked nothing while parked, so
## this hands the clock the REAL time that passed (the frames before the
## wake-up frame -- that frame's own delta arrives through the marker's
## ordinary tick()). Afterwards the clock is indistinguishable from one that
## ticked every one of those frames: the gate opens on the next tick, and
## take_step() applies its usual cap to what accumulated.
func resume(elapsed_seconds: float) -> void:
	_accumulated_seconds = elapsed_seconds
	_frames_waited = _frames_until_next


const SimulationLod = preload("res://src/gameplay/simulation_lod.gd")
