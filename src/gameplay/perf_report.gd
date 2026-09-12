extends RefCounted

## The permanent, opt-in frame-split diagnostic behind the `--perf-report`
## launch flag: once every REPORT_INTERVAL_SECONDS, World prints one "PERF"
## line built from the engine's OWN monitors -- how long the frame's script
## process step took, how long physics took, how long the renderer's CPU
## and GPU sides measured, how many nodes/draw calls/objects were in play --
## plus the SimulationScheduler's census of adopted/near/parked markers.
##
## Why this exists as real code rather than another round of temporary
## brackets: twelve FPS-regression rounds (docs/concept/soil_fauna.md,
## rounds 1-12) only ever timed GDScript call sites, and their own closing
## arithmetic never once said how much of a frame was NOT script. A frame
## is script + physics + rendering + engine overhead, and only the engine
## can report the last three. Read `frame - process - physics - render_cpu`
## as "everything else" (tree/notification/canvas overhead). GPU time is
## measured on its own timeline and overlaps the CPU work, so it is NOT
## added to the others.
##
## Usage: `<godot> --path . --rendering-driver opengl3 -- --solo --perf-report`
## and read the PERF lines from stdout (the console binary). The fixed fields
## are point-in-time readings -- and note that Godot's TIME_PROCESS and
## TIME_PHYSICS_PROCESS are the WORST frame of the last second, not the last
## frame -- while every section (s_*) is an average per frame over the
## report window; take medians of many lines, as the perf rounds' own
## methodology already does. s_loop is the exact frame period.
## Pinned by tests/unit/test_perf_report.gd; World's wiring by
## tests/unit/test_world_perf_report_wiring.gd.

const FLAG := "--perf-report"
const REPORT_INTERVAL_SECONDS := 2.0
## How many classes the processing census prints, busiest first.
const PROCESSING_TOP_N := 8

## Every key a sample carries, in the exact order format_line prints them.
const FIELDS: Array[String] = [
	"fps", "frame_ms", "process_ms", "physics_ms", "nav_ms", "render_cpu_ms", "render_gpu_ms",
	"nodes", "orphans", "draw_calls", "objects", "primitives", "phys_active", "phys_pairs",
	"mem_static_mb", "sched_adopted", "sched_in_hand", "sched_parked",
]

var _accumulator := 0.0
## Label -> usec accumulated since the last take_sections(), and the number
## of ticks (frames) they span, so a section reads as ms PER FRAME.
var _section_usec: Dictionary = {}
var _section_frames := 0
## The usec stamp World took at the top of its own _process this frame, or
## -1 when no frame is open; closed by PerfFrameSentinel into the "tree"
## section (the whole idle-process span across every node).
var _frame_started_usec := -1
var _last_frame_started_usec := -1
## Label -> how many times it happened since the last take_counts()
## (scheduler steps per class); reported per frame like the sections, on
## its own frame count so the two takes are independent of each other.
var _counts: Dictionary = {}
var _count_frames := 0


static func requested(args: PackedStringArray) -> bool:
	return FLAG in args


## The same accumulator gate World's own throttles use: true exactly once
## per elapsed interval, never starving on a lag spike (a single delta past
## the interval fires), never firing twice for one crossing.
func tick(delta: float) -> bool:
	_accumulator += delta
	_section_frames += 1
	_count_frames += 1
	if _accumulator < REPORT_INTERVAL_SECONDS:
		return false
	_accumulator = 0.0
	return true


## World brackets its own top-level script blocks with this -- the creature
## scheduler, its ecology steps, the per-client UI pass -- so the report can
## split TIME_PROCESS into the pieces game code actually owns. Zero cost
## when no report is running: the caller guards on the report being null.
func add_section(label: String, usec: int) -> void:
	_section_usec[label] = int(_section_usec.get(label, 0)) + usec


## World stamps the top of its _process (the scene root runs first)...
func mark_frame_start(usec: int) -> void:
	# Consecutive starts are one whole main-loop iteration apart: script,
	# physics, render AND the engine's own work -- the exact frame period,
	# reported as the "loop" section (ms/frame) so the engine's share is
	# loop - tree - physics - render_cpu, not inferred from TIME_PROCESS
	# (which Godot reports as the WORST frame of the last second).
	if _last_frame_started_usec >= 0:
		add_section("loop", usec - _last_frame_started_usec)
	_last_frame_started_usec = usec
	_frame_started_usec = usec


## ...and the PerfFrameSentinel, processed last, closes the span. Without an
## open frame the stamp is ignored rather than inventing a span.
func mark_frame_end(usec: int) -> void:
	if _frame_started_usec < 0:
		return
	add_section("tree", usec - _frame_started_usec)
	_frame_started_usec = -1


## How many times something happened this frame -- with the matching
## section's ms, the cost of ONE occurrence becomes readable.
func add_count(label: String, count: int) -> void:
	_counts[label] = int(_counts.get(label, 0)) + count


## Every count as an average per frame over the ticks since the last take;
## taking resets. Independent of take_sections: World reads the two in one
## expression, sections first, and the first wiring had the counts dividing
## by a frame count the sections had just reset -- every c_ field printed
## as nothing for three runs.
func take_counts() -> Dictionary:
	var counts := {}
	if _count_frames > 0:
		for label in _counts:
			counts[label] = float(_counts[label]) / float(_count_frames)
	_counts = {}
	_count_frames = 0
	return counts


## Every section as ms per frame, averaged over the ticks since the last
## take; taking resets both the totals and the frame count.
func take_sections() -> Dictionary:
	var sections := {}
	if _section_frames > 0:
		for label in _section_usec:
			sections[label] = float(_section_usec[label]) / 1000.0 / float(_section_frames)
	_section_usec = {}
	_section_frames = 0
	return sections


## Reads every monitor once. `viewport` is the RID the renderer measured --
## RenderingServer.viewport_set_measure_render_time(viewport, true) must
## have been called for the render_* fields to be anything but 0. `census`
## is SimulationScheduler.census(); missing keys read as 0.
static func sample(viewport: RID, census: Dictionary, sections: Dictionary = {}, processing: Dictionary = {}, counts: Dictionary = {}) -> Dictionary:
	var fps := Engine.get_frames_per_second()
	return {
		"sections": sections,
		"processing": processing,
		"counts": counts,
		"fps": int(fps),
		"frame_ms": 1000.0 / fps if fps > 0.0 else 0.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nav_ms": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"phys_active": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"phys_pairs": int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"mem_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"sched_adopted": int(census.get("adopted", 0)),
		"sched_in_hand": int(census.get("in_hand", 0)),
		"sched_parked": int(census.get("parked", 0)),
	}


static func format_line(s: Dictionary) -> String:
	var line := (
		"PERF fps=%d frame=%.1fms process=%.1fms physics=%.1fms nav=%.1fms render_cpu=%.1fms "
		+ "render_gpu=%.1fms nodes=%d orphans=%d draw_calls=%d objects=%d primitives=%d "
		+ "phys_active=%d phys_pairs=%d mem=%.1fMB sched_adopted=%d sched_in_hand=%d sched_parked=%d"
	) % [
		s["fps"], s["frame_ms"], s["process_ms"], s["physics_ms"], s["nav_ms"], s["render_cpu_ms"],
		s["render_gpu_ms"], s["nodes"], s["orphans"], s["draw_calls"], s["objects"], s["primitives"],
		s["phys_active"], s["phys_pairs"], s["mem_static_mb"], s["sched_adopted"], s["sched_in_hand"],
		s["sched_parked"],
	]
	var sections: Dictionary = s.get("sections", {})
	var labels := sections.keys()
	labels.sort()
	for label in labels:
		line += " s_%s=%.1fms" % [label, sections[label]]
	var counts: Dictionary = s.get("counts", {})
	var count_labels := counts.keys()
	count_labels.sort()
	for label in count_labels:
		line += " c_%s=%.1f" % [label, counts[label]]
	var processing: Dictionary = s.get("processing", {})
	var ranked: Array = []
	for key in processing:
		ranked.append([key, int(processing[key])])
	ranked.sort_custom(func(a, b): return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
	for i in mini(ranked.size(), PROCESSING_TOP_N):
		line += " p_%s=%d" % [ranked[i][0], ranked[i][1]]
	return line


## Every node under `root` the ENGINE still dispatches _process to, counted
## by class -- a scripted node by its script file's basename (what a marker
## class is called in this codebase), anything else by its engine class.
## The scheduler adopts nine marker classes and switches their engine
## _process off, so this is exactly the population behind "TIME_PROCESS
## minus the three sections": whatever it lists is paying ~7us of dispatch
## per node per frame plus its own step, outside every LOD throttle. A
## plain walk of the whole tree (~24k nodes) once per report interval --
## only while --perf-report is on.
static func processing_census(root: Node) -> Dictionary:
	var census := {}
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_processing():
			var key := _class_key(node)
			census[key] = int(census.get(key, 0)) + 1
		for child in node.get_children():
			stack.append(child)
	return census


static func _class_key(node: Node) -> String:
	var script = node.get_script()
	if script != null and not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename()
	return node.get_class()
