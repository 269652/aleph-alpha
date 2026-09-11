extends RefCounted

## The due-frame scheduler that lets a distant creature marker stop receiving
## _process at all for the frames its SimulationLodClock was going to skip
## anyway (see docs/concept/ecosystem_dynamics.md "Per-creature update rate
## inside loaded chunks", and soil_fauna.md "FPS regression round 11").
##
## Round 10's clock bounded the WORK a distant creature does per frame, but
## not the cost of its _process callback existing: ~7us per marker per frame
## for the engine to dispatch into GDScript, tick the clock and return, times
## ~2,500 live markers -- 10-17ms of every frame, most of a 60fps budget,
## spent on creatures doing nothing. So a marker that has just stepped and
## knows it will skip the next N frames parks itself here instead:
## set_process(false), and an entry in the bucket for frame now + N. Each
## frame, World advances the scheduler once, and only the markers in THAT
## frame's bucket are touched -- woken with set_process(true) and their clock
## primed with the real time they were parked, so the clock's own contract
## (at most interval + one frame per update, distance re-read on wake) holds
## exactly as if they had ticked every frame. Nothing is parked when no
## scheduler is current: every unit test that never sets one, and a world
## with nobody to be far from, behave exactly as before.
##
## One static "current" scheduler rather than per-class world plumbing: the
## nine LOD-throttled marker classes reach their world in three different
## ways (and AmbientFlyerMarker not at all), while every one of them shares
## the same clock -- the same static-shared-state shape DecomposerMarker's
## and FishMarker's round-5/7 caches already use. World publishes its own in
## _ready and withdraws it when it leaves the tree.

static var _current = null

var _frame := 0
var _elapsed_seconds := 0.0
## Due frame -> Array of [marker, clock, elapsed seconds when parked].
var _due: Dictionary = {}
var _parked := 0


static func current():
	return _current


static func set_current(scheduler) -> void:
	_current = scheduler


## Parks `marker` for the frames its `clock` has just committed to skipping
## (SimulationLodClock.frames_until_next after a real step). A marker due
## next frame anyway, or one with no current scheduler to park in, is left
## processing exactly as before.
static func park_if_far(marker: Node, clock) -> void:
	var frames: int = clock.frames_until_next()
	if frames <= 1 or _current == null:
		return
	marker.set_process(false)
	_current._park(marker, clock, frames)


func _park(marker: Node, clock, frames: int) -> void:
	var due_frame := _frame + frames
	if not _due.has(due_frame):
		_due[due_frame] = []
	_due[due_frame].append([marker, clock, _elapsed_seconds])
	_parked += 1


## Once per frame, before any creature is processed (World._process). Wakes
## every marker due this frame: its clock gets the real seconds that passed
## since it parked, excluding this frame's own delta (that one arrives
## through the marker's ordinary tick), and its _process is switched back
## on. A marker freed while parked is simply dropped.
func advance(delta: float) -> void:
	_frame += 1
	var elapsed_before_this_frame := _elapsed_seconds
	_elapsed_seconds += delta
	if not _due.has(_frame):
		return
	var bucket: Array = _due[_frame]
	_due.erase(_frame)
	for entry in bucket:
		_parked -= 1
		var marker = entry[0]
		if not is_instance_valid(marker) or marker.is_queued_for_deletion():
			continue
		entry[1].resume(elapsed_before_this_frame - entry[2])
		marker.set_process(true)


## How many markers are parked right now -- a diagnostic, and what the tests
## pin.
func parked_count() -> int:
	return _parked


func frame() -> int:
	return _frame
