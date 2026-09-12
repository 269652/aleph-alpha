extends RefCounted

## The round-robin clock behind World's batched ecology steps (FPS
## regression round 13; docs/concept/ecosystem_dynamics.md "Ecology steps
## run at a cadence, not a frame rate"; pinned by test_step_cadence.gd).
##
## Every label runs once per INTERVAL_SECONDS and is handed the seconds
## accumulated since it last ran -- so a step's simulated time never
## depends on the frame rate, only on the wall clock, exactly the contract
## these steps already had (each takes delta_seconds and moves on world
## time). At or below 1 / INTERVAL_SECONDS fps a frame is already an
## interval and every label runs every frame, as before: the cadence only
## ever REMOVES work, at high frame rates, where the same per-chunk walks
## would otherwise repeat sixty times a second for no change anyone could
## see.
##
## Labels are staggered: label i is granted a head start of i / N of the
## interval toward its FIRST due -- a phase, never simulated time, so what
## it is handed is only the seconds that really passed -- and the first
## interval spreads N labels across its frames instead of stacking them on
## one; with equal deltas thereafter they stay spread. Within one frame, due labels come back in the order given,
## so two steps that happen to run on the same frame keep their relative
## order; across frames the stagger decides, and the only step that truly
## must see the others' freshest state -- quest reconciliation -- stays
## outside the cadence, after it, every frame (World._step_ecology_batch).

const INTERVAL_SECONDS := 0.25
const DUE_EPSILON_SECONDS := 0.000001

var _labels: Array[String]
var _accumulated: Dictionary = {}
## Label -> head start toward its first due, spent on that first firing.
var _phase: Dictionary = {}


func _init(labels: Array[String]) -> void:
	_labels = labels.duplicate()
	var count := maxi(_labels.size(), 1)
	for i in _labels.size():
		_accumulated[_labels[i]] = 0.0
		_phase[_labels[i]] = INTERVAL_SECONDS * float(i) / float(count)


## Advances every label by `delta` and returns [[label, elapsed_seconds], ...]
## for each one that is due this frame, in the order the labels were given.
func advance(delta: float) -> Array:
	var due: Array = []
	for label in _labels:
		var accumulated: float = _accumulated[label] + delta
		# Fifteen 1/60 s frames sum to a hair under 0.25 in floating point;
		# within a microsecond of due is due.
		if accumulated + float(_phase[label]) + DUE_EPSILON_SECONDS >= INTERVAL_SECONDS:
			due.append([label, accumulated])
			accumulated = 0.0
			_phase[label] = 0.0
		_accumulated[label] = accumulated
	return due
