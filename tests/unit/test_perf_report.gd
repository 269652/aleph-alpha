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


## Sections: World brackets its own top-level script blocks (the creature
## scheduler, its ecology steps, the per-client UI pass) with
## add_section(label, usec) and the report averages each over the frames
## since the last line -- the split TIME_PROCESS alone cannot give.
func test_sections_average_per_frame_over_the_ticks_since_the_last_report():
	var report := PerfReport.new()
	report.add_section("sched", 3000)
	report.tick(INTERVAL * 0.6)
	report.add_section("sched", 5000)
	report.add_section("client", 1000)
	assert_true(report.tick(INTERVAL * 0.6), "precondition: the second tick fires the report")

	var sections: Dictionary = report.take_sections()

	assert_almost_eq(sections["sched"], 4.0, 0.001, "8 ms over 2 frames")
	assert_almost_eq(sections["client"], 0.5, 0.001, "1 ms over 2 frames")
	assert_eq(report.take_sections(), {}, "taking the sections resets them and their frame count")


func test_format_line_appends_sections_in_label_order():
	var sample := {
		"fps": 12, "frame_ms": 83.3, "process_ms": 40.26, "physics_ms": 1.5, "nav_ms": 0.0,
		"render_cpu_ms": 9.76, "render_gpu_ms": 3.0, "nodes": 23456, "orphans": 2,
		"draw_calls": 1234, "objects": 5678, "primitives": 90123, "phys_active": 11,
		"phys_pairs": 5, "mem_static_mb": 512.6, "sched_adopted": 2500, "sched_in_hand": 300,
		"sched_parked": 2200, "sections": {"sched": 4.0, "client": 0.5},
	}
	assert_true(
		PerfReport.format_line(sample).ends_with(" sched_parked=2200 s_client=0.5ms s_sched=4.0ms"),
		"sections follow the fixed fields, sorted by label: %s" % PerfReport.format_line(sample)
	)


func test_sample_carries_the_sections_it_is_handed():
	var sample: Dictionary = PerfReport.sample(get_viewport().get_viewport_rid(), {}, {"sched": 4.0})
	assert_eq(sample["sections"], {"sched": 4.0})


## Processing census: every node the ENGINE still dispatches _process to,
## keyed by class -- the scheduler adopts nine marker classes and switches
## their engine _process off, so this is exactly the population behind
## "TIME_PROCESS minus the three sections". A real marker script stands in
## for "a scripted node": an inner test class has no resource path of its
## own, so it would (correctly) fall back to its engine class.
const BondedCompanionMarker = preload("res://src/rendering/bonded_companion_marker.gd")


func test_processing_census_counts_only_nodes_the_engine_still_processes_keyed_by_class():
	var root := Node.new()
	add_child_autofree(root)
	var on := Node2D.new()
	root.add_child(on)
	on.set_process(true)
	var off := Node2D.new()
	root.add_child(off)
	off.set_process(false)
	var ticker := BondedCompanionMarker.new()
	root.add_child(ticker)

	var census: Dictionary = PerfReport.processing_census(root)

	assert_eq(census.get("Node2D", 0), 1, "only the Node2D whose processing is on")
	assert_eq(census.get("bonded_companion_marker", 0), 1, "a scripted node is keyed by its script file, not its engine class")
	assert_false(census.has("Node"), "the plain root is not processing")


func test_format_line_appends_the_busiest_processing_classes_after_the_sections():
	var sample := {
		"fps": 12, "frame_ms": 83.3, "process_ms": 40.26, "physics_ms": 1.5, "nav_ms": 0.0,
		"render_cpu_ms": 9.76, "render_gpu_ms": 3.0, "nodes": 23456, "orphans": 2,
		"draw_calls": 1234, "objects": 5678, "primitives": 90123, "phys_active": 11,
		"phys_pairs": 5, "mem_static_mb": 512.6, "sched_adopted": 2500, "sched_in_hand": 300,
		"sched_parked": 2200, "sections": {"sched": 4.0},
		"processing": {"npc_marker": 12, "wild_crop_marker": 900, "dropped_item": 40},
	}
	assert_true(
		PerfReport.format_line(sample).ends_with(" s_sched=4.0ms p_wild_crop_marker=900 p_dropped_item=40 p_npc_marker=12"),
		"busiest first, after the sections: %s" % PerfReport.format_line(sample)
	)


func test_format_line_prints_at_most_the_top_processing_classes():
	var processing := {}
	for i in range(PerfReport.PROCESSING_TOP_N + 5):
		processing["class_%02d" % i] = 100 - i
	var line := PerfReport.format_line({
		"fps": 1, "frame_ms": 1.0, "process_ms": 1.0, "physics_ms": 1.0, "nav_ms": 0.0,
		"render_cpu_ms": 1.0, "render_gpu_ms": 1.0, "nodes": 1, "orphans": 0, "draw_calls": 1,
		"objects": 1, "primitives": 1, "phys_active": 0, "phys_pairs": 0, "mem_static_mb": 1.0,
		"sched_adopted": 0, "sched_in_hand": 0, "sched_parked": 0, "processing": processing,
	})
	assert_eq(line.count(" p_class_"), PerfReport.PROCESSING_TOP_N)
	assert_true(line.contains(" p_class_00=100"), "the busiest survives the cut")
	assert_false(line.contains(" p_class_%02d=" % (PerfReport.PROCESSING_TOP_N + 4)), "the quietest does not")


func test_sample_carries_the_processing_census_it_is_handed():
	var sample: Dictionary = PerfReport.sample(get_viewport().get_viewport_rid(), {}, {}, {"npc_marker": 3})
	assert_eq(sample["processing"], {"npc_marker": 3})
