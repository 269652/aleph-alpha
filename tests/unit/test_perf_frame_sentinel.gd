extends GutTest

## PerfFrameSentinel (src/gameplay/perf_frame_sentinel.gd): the node World
## adds under itself only behind --perf-report, whose one job is to be the
## LAST thing processed each frame and stamp that moment into the report
## (see test_perf_report.gd's "tree" section). Godot orders the whole
## process group by process_priority, so a priority far above anything the
## game sets puts it after every marker, the player and every UI node.

const PerfReport = preload("res://src/gameplay/perf_report.gd")
const PerfFrameSentinel = preload("res://src/gameplay/perf_frame_sentinel.gd")


func test_it_asks_to_be_processed_after_everything_else():
	var sentinel := PerfFrameSentinel.new(PerfReport.new())
	autofree(sentinel)
	assert_eq(sentinel.process_priority, PerfFrameSentinel.PROCESS_PRIORITY)
	assert_gt(PerfFrameSentinel.PROCESS_PRIORITY, 100_000, "far above any priority game code uses")


func test_each_process_stamps_the_frame_end_into_its_report():
	var report := PerfReport.new()
	var sentinel := PerfFrameSentinel.new(report)
	autofree(sentinel)
	report.mark_frame_start(Time.get_ticks_usec())

	sentinel._process(1.0 / 60.0)
	report.tick(PerfReport.REPORT_INTERVAL_SECONDS * 2.0)

	assert_true(report.take_sections().has("tree"), "the sentinel's stamp closes the frame span")
