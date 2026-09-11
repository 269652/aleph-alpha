extends RefCounted

## The driver that takes LOD-throttled creature markers out of the engine's
## own per-node _process dispatch entirely (see docs/concept/
## ecosystem_dynamics.md "Per-creature update rate inside loaded chunks",
## and soil_fauna.md "FPS regression round 11").
##
## Round 10's SimulationLodClock bounded the WORK a distant creature does per
## frame, but not the cost of its _process callback existing: ~7us per marker
## per frame for the engine to dispatch into GDScript, tick the clock and
## return, times ~2,500 live markers -- 10-17ms of every frame spent on
## creatures doing nothing.
##
## So a marker is ADOPTED on its first real step: its own engine _process is
## switched off exactly once, and from then on this scheduler calls its
## _process itself -- every frame while its clock says "due next frame"
## (near the player), otherwise only on the frame it is due, with the clock
## primed with the real time it waited (SimulationLodClock.resume), so the
## clock's whole contract (at most interval + one frame per update, distance
## re-read on wake) holds exactly as if the engine had ticked it every frame.
## World advances the scheduler once per frame, first thing in its own
## _process. A marker freed while adopted is dropped when next encountered.
##
## Why adopt once, rather than park and wake with set_process(false)/(true)
## around every skip: the first cut did exactly that and measured WORSE live
## (median 6 fps against 9). Every toggle is an O(nodes) erase or insert in
## the SceneTree's process group plus a re-sort of that ~24,000-node group on
## every frame in which anything toggled -- and with ~170 toggles a frame,
## that was every frame. Adoption changes each marker's processing flag once
## in its life; the wheel below never touches the tree at all.
##
## One static "current" scheduler rather than per-class world plumbing: the
## nine LOD-throttled marker classes reach their world three different ways
## (AmbientFlyerMarker not at all), while every one of them shares the same
## clock -- the same static-shared-state shape DecomposerMarker's and
## FishMarker's round-5/7 caches already use. World publishes its own in
## _ready and withdraws it when it leaves the tree. Nothing is adopted when
## no scheduler is current: every unit test that never sets one, and a world
## with nobody to be far from, behave exactly as before.

static var _current = null

var _frame := 0
var _elapsed_seconds := 0.0
## Instance id -> marker, for everything currently stepped every frame: near
## markers, and woken ones until their own next real step re-places them.
var _in_hand: Dictionary = {}
## A snapshot of _in_hand's keys for the per-frame loop, rebuilt only after a
## change so the common case is one plain iteration.
var _in_hand_ids: Array = []
var _in_hand_dirty := false
## Due frame -> Array of [marker, clock, elapsed seconds when parked, id].
var _due: Dictionary = {}
var _parked := 0
## Instance id -> true for every marker taken over from the engine.
var _adopted: Dictionary = {}


static func current():
	return _current


static func set_current(scheduler) -> void:
	_current = scheduler


## A marker calls this right after every real step (every LOD-throttled
## marker's _lod_step does). First call: the marker is adopted -- its engine
## _process switched off for good. Every call: placed by what its clock just
## committed to -- due next frame, so stepped every frame from here; or due
## in N frames, so parked on the wheel until then. A no-op when no scheduler
## is current.
static func adopt_or_park(marker: Node, clock) -> void:
	if _current == null:
		return
	_current._place(marker, clock)


func _place(marker: Node, clock) -> void:
	var id := marker.get_instance_id()
	if not _adopted.has(id):
		_adopted[id] = true
		marker.set_process(false)
	var frames: int = clock.frames_until_next()
	if frames <= 1:
		if not _in_hand.has(id):
			_in_hand[id] = marker
			_in_hand_dirty = true
		return
	if _in_hand.has(id):
		_in_hand.erase(id)
		_in_hand_dirty = true
	var due_frame := _frame + frames
	if not _due.has(due_frame):
		_due[due_frame] = []
	_due[due_frame].append([marker, clock, _elapsed_seconds, id])
	_parked += 1


## Once per frame, before any creature is processed (World._process). Wakes
## every marker due this frame -- its clock gets the real seconds that passed
## since it parked, excluding this frame's own delta (that one arrives
## through the marker's ordinary tick), and it is taken in hand -- then steps
## everything in hand with this frame's delta. A woken marker stays in hand,
## stepped every frame, until its own next real step re-places it: that is
## what keeps one whose seconds gate is not open yet (above the reference
## frame rate) from ever being lost.
func advance(delta: float) -> void:
	_frame += 1
	var elapsed_before_this_frame := _elapsed_seconds
	_elapsed_seconds += delta
	if _due.has(_frame):
		var bucket: Array = _due[_frame]
		_due.erase(_frame)
		for entry in bucket:
			_parked -= 1
			var marker = entry[0]
			if not _alive(marker):
				_adopted.erase(entry[3])
				continue
			entry[1].resume(elapsed_before_this_frame - entry[2])
			_in_hand[entry[3]] = marker
			_in_hand_dirty = true
	if _in_hand_dirty:
		_in_hand_ids = _in_hand.keys()
		_in_hand_dirty = false
	for id in _in_hand_ids:
		if not _in_hand.has(id):
			continue  # re-placed on the wheel earlier this frame
		# Never compare a possibly-freed reference to null: a freed Object
		# stored as a value comes back as a "previously freed" Variant, not
		# null, and must still be swept below.
		var marker = _in_hand[id]
		if not _alive(marker):
			_in_hand.erase(id)
			_adopted.erase(id)
			_in_hand_dirty = true
			continue
		marker._process(delta)


static func _alive(marker) -> bool:
	return is_instance_valid(marker) and not marker.is_queued_for_deletion()


## How many markers are stepped every frame right now (near, or woken and
## waiting on their seconds gate) -- a diagnostic, and what the tests pin.
func active_count() -> int:
	return _in_hand.size()


## How many markers are parked on the wheel right now.
func parked_count() -> int:
	return _parked


func frame() -> int:
	return _frame
