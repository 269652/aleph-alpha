extends GutTest

## World's wiring of PerfReport (src/gameplay/perf_report.gd, the
## `--perf-report` frame-split diagnostic) -- a source-contract test on the
## function bodies, the same shape test_world_simulation_scheduler_wiring.gd
## uses and for the same reason: World resolves its world state internally,
## so standing one up headlessly to drive _ready/_process live is not worth
## the fight. Three things must be true: nothing is reported unless the flag
## was given (a plain launch pays nothing), the renderer is told to measure
## its own time when it is (or render_* reads as 0 forever), and _process
## prints exactly one line per due tick built from the scheduler's census.

const World = preload("res://scenes/world.gd")


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_a_world_has_no_report_until_the_flag_asks_for_one():
	var world := World.new()
	autofree(world)
	assert_null(world._perf_report)


func test_ready_enables_the_report_and_render_timing_only_behind_the_flag():
	var body := _body_of("_ready")
	var gate_at := body.find("if PerfReport.requested(args):")
	assert_gt(gate_at, -1, "the report must be opt-in via the user args")
	var enabled_at := body.find("_perf_report = PerfReport.new()", gate_at)
	var measured_at := body.find(
		"RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)", gate_at
	)
	assert_gt(enabled_at, gate_at, "the report object is created inside the gate")
	assert_gt(measured_at, gate_at, "and the renderer is told to measure, inside the same gate")


func test_process_prints_one_line_per_due_tick_from_the_schedulers_census():
	var body := _body_of("_process")
	assert_true(body.contains("_perf_report.tick(delta)"), "the report is advanced once per frame")
	assert_true(
		body.contains("print(PerfReport.format_line(PerfReport.sample(get_viewport().get_viewport_rid(), _simulation_scheduler.census())))"),
		"one printed line, built from the live scheduler census"
	)
	assert_eq(body.count("_perf_report.tick("), 1, "exactly once per frame")
