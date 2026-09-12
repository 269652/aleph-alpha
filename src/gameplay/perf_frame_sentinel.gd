extends Node

## The last node processed each frame, and nothing else: World adds one
## under itself only behind --perf-report, and its one job is to stamp the
## moment the scene tree's idle process pass ends into the PerfReport (see
## PerfReport.mark_frame_end and its "tree" section). Godot orders the
## whole process group by process_priority, so a priority far above
## anything game code sets puts this after every marker, the player and
## every UI node -- and World, the scene root, is processed first, so
## World's own stamp at the top of its _process opens the span. What lies
## between is every node's own _process plus the engine's dispatch into
## them; what TIME_PROCESS still holds beyond that (and the renderer's
## measured draw) is the engine's own work outside any node.

const PROCESS_PRIORITY := 1_000_000

var _report


func _init(report) -> void:
	_report = report
	process_priority = PROCESS_PRIORITY


func _process(_delta: float) -> void:
	_report.mark_frame_end(Time.get_ticks_usec())
