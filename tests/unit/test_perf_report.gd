extends GutTest

## PerfReport is the permanent, opt-in frame-split diagnostic behind the
## `--perf-report` launch flag (docs/concept/ecosystem_dynamics.md "Frame
## budget accounting"): one printed line every REPORT_INTERVAL_SECONDS with
## the engine's OWN monitors -- script process time, physics time, the
## renderer's measured CPU/GPU time, node/draw-call counts -- plus the
## simulation scheduler's census. Twelve FPS rounds only ever timed
## GDScript brackets; nothing ever said how much of a frame was NOT script.
## This is that number, as a real feature rather than temporary
## instrumentation stripped before every merge.

const PerfReport = preload("res://src/gameplay/perf_report.gd")

const INTERVAL := PerfReport.REPORT_INTERVAL_SECONDS


func test_the_report_interval_is_exactly_pinned():
	assert_eq(INTERVAL, 2.0)


func test_requested_only_when_the_flag_is_among_the_user_args():
	assert_true(PerfReport.requested(PackedStringArray(["--solo", "--perf-report"])))
	assert_false(PerfReport.requested(PackedStringArray(["--solo"])))
	assert_false(PerfReport.requested(PackedStringArray([])))


func test_two_ticks_within_the_interval_are_not_due():
	var report := PerfReport.new()
	assert_false(report.tick(INTERVAL * 0.4))
	assert_false(report.tick(INTERVAL * 0.4))


func test_crossing_the_interval_is_due_exactly_once_and_then_waits_again():
	var report := PerfReport.new()
	report.tick(INTERVAL * 0.4)
	report.tick(INTERVAL * 0.4)
	assert_true(report.tick(INTERVAL * 0.4), "1.2x the interval must fire")
	assert_false(report.tick(INTERVAL * 0.4), "the accumulator must have reset after firing")


func test_a_single_large_delta_is_due():
	var report := PerfReport.new()
	assert_true(report.tick(INTERVAL * 3.0))


func test_sample_carries_every_field_the_line_prints_and_the_census():
	var census := {"adopted": 7, "in_hand": 3, "parked": 4}
	var sample: Dictionary = PerfReport.sample(get_viewport().get_viewport_rid(), census)
	for key in PerfReport.FIELDS:
		assert_true(sample.has(key), "sample must carry '%s'" % key)
		assert_true(
			typeof(sample[key]) == TYPE_FLOAT or typeof(sample[key]) == TYPE_INT,
			"'%s' must be numeric, got %s" % [key, type_string(typeof(sample[key]))]
		)
	assert_eq(sample["sched_adopted"], 7)
	assert_eq(sample["sched_in_hand"], 3)
	assert_eq(sample["sched_parked"], 4)


func test_format_line_prints_every_field_in_a_fixed_order_with_units():
	var sample := {
		"fps": 12, "frame_ms": 83.3, "process_ms": 40.26, "physics_ms": 1.5, "nav_ms": 0.0,
		"render_cpu_ms": 9.76, "render_gpu_ms": 3.0, "nodes": 23456, "orphans": 2,
		"draw_calls": 1234, "objects": 5678, "primitives": 90123, "phys_active": 11,
		"phys_pairs": 5, "mem_static_mb": 512.6, "sched_adopted": 2500, "sched_in_hand": 300,
		"sched_parked": 2200,
	}
	assert_eq(
		PerfReport.format_line(sample),
		"PERF fps=12 frame=83.3ms process=40.3ms physics=1.5ms nav=0.0ms render_cpu=9.8ms "
		+ "render_gpu=3.0ms nodes=23456 orphans=2 draw_calls=1234 objects=5678 "
		+ "primitives=90123 phys_active=11 phys_pairs=5 mem=512.6MB "
		+ "sched_adopted=2500 sched_in_hand=300 sched_parked=2200"
	)


func test_a_missing_census_reads_as_zero_not_a_crash():
	var sample: Dictionary = PerfReport.sample(get_viewport().get_viewport_rid(), {})
	assert_eq(sample["sched_adopted"], 0)
	assert_eq(sample["sched_in_hand"], 0)
	assert_eq(sample["sched_parked"], 0)
