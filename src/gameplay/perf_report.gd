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
## and read the PERF lines from stdout (the console binary). Every field is
## a point-in-time or last-frame value, never a window average -- take the
## median of many lines, as the perf rounds' own methodology already does.
## Pinned by tests/unit/test_perf_report.gd; World's wiring by
## tests/unit/test_world_perf_report_wiring.gd.

const FLAG := "--perf-report"
const REPORT_INTERVAL_SECONDS := 2.0

## Every key a sample carries, in the exact order format_line prints them.
const FIELDS: Array[String] = [
	"fps", "frame_ms", "process_ms", "physics_ms", "nav_ms", "render_cpu_ms", "render_gpu_ms",
	"nodes", "orphans", "draw_calls", "objects", "primitives", "phys_active", "phys_pairs",
	"mem_static_mb", "sched_adopted", "sched_in_hand", "sched_parked",
]

var _accumulator := 0.0


static func requested(args: PackedStringArray) -> bool:
	return FLAG in args


## The same accumulator gate World's own throttles use: true exactly once
## per elapsed interval, never starving on a lag spike (a single delta past
## the interval fires), never firing twice for one crossing.
func tick(delta: float) -> bool:
	_accumulator += delta
	if _accumulator < REPORT_INTERVAL_SECONDS:
		return false
	_accumulator = 0.0
	return true


## Reads every monitor once. `viewport` is the RID the renderer measured --
## RenderingServer.viewport_set_measure_render_time(viewport, true) must
## have been called for the render_* fields to be anything but 0. `census`
## is SimulationScheduler.census(); missing keys read as 0.
static func sample(viewport: RID, census: Dictionary) -> Dictionary:
	var fps := Engine.get_frames_per_second()
	return {
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
	return (
		"PERF fps=%d frame=%.1fms process=%.1fms physics=%.1fms nav=%.1fms render_cpu=%.1fms "
		+ "render_gpu=%.1fms nodes=%d orphans=%d draw_calls=%d objects=%d primitives=%d "
		+ "phys_active=%d phys_pairs=%d mem=%.1fMB sched_adopted=%d sched_in_hand=%d sched_parked=%d"
	) % [
		s["fps"], s["frame_ms"], s["process_ms"], s["physics_ms"], s["nav_ms"], s["render_cpu_ms"],
		s["render_gpu_ms"], s["nodes"], s["orphans"], s["draw_calls"], s["objects"], s["primitives"],
		s["phys_active"], s["phys_pairs"], s["mem_static_mb"], s["sched_adopted"], s["sched_in_hand"],
		s["sched_parked"],
	]
