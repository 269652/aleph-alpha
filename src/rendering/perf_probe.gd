extends RefCounted

## Temporary diagnostic instrument for the round-4 FPS-regression
## investigation (4fps reported live on a long-lived save with unusually
## dense leaf litter -- see docs/concept/soil_fauna.md). NOT game code, NOT
## meant to survive this investigation -- mirrors round 3's own perf_probe.gd
## (same begin/end/count_instance call shape, confirmed from its removal
## diff in commit a999b439; that file itself was never committed, so this is
## a fresh reconstruction, not a resurrection).
##
## Aggregates wall-clock time per labelled call site and instance counts per
## labelled population, printing + resetting every REPORT_INTERVAL_SECONDS
## so a live --solo session's console log shows a rolling per-class cost
## breakdown -- exactly the "aggregate per-class timing" shape round 2/3
## both used to find their own dominant costs.

static var _totals_usec: Dictionary = {}      # label -> total elapsed usec
static var _call_counts: Dictionary = {}      # label -> number of end() calls
static var _instance_counts: Dictionary = {}  # label -> count_instance() calls this window
static var _starts_usec: Dictionary = {}      # label -> in-flight begin() timestamp
static var _gauges: Dictionary = {}           # label -> last-set value (NOT summed)
static var _window_start_usec: int = -1

const REPORT_INTERVAL_SECONDS := 3.0


static func begin(label: String) -> void:
	_starts_usec[label] = Time.get_ticks_usec()


static func end(label: String) -> void:
	if not _starts_usec.has(label):
		return
	var elapsed: int = Time.get_ticks_usec() - int(_starts_usec[label])
	_totals_usec[label] = int(_totals_usec.get(label, 0)) + elapsed
	_call_counts[label] = int(_call_counts.get(label, 0)) + 1


static func count_instance(label: String) -> void:
	_instance_counts[label] = int(_instance_counts.get(label, 0)) + 1


## Adds `amount` to a running per-window total under `label` -- for
## magnitudes rather than event counts (e.g. "how many leaves did we just
## push into a MultiMesh", not "how many times did we push"). Shares the
## same _instance_counts table/report section as count_instance -- both are
## "count", not "time", the report just cares which bucket to sum into.
static func add_count(label: String, amount: int) -> void:
	_instance_counts[label] = int(_instance_counts.get(label, 0)) + amount


## Records a POINT-IN-TIME value (overwrites, never sums) -- for a gauge
## like "how many leaves exist right now", where summing the same
## roughly-constant reading across every frame in the window (what
## add_count would do) would wildly inflate it instead of reporting it.
static func set_gauge(label: String, value: int) -> void:
	_gauges[label] = value


## Call once per frame from a single, well-known site (scenes/world.gd's
## _process, mirroring round 3's own wiring) -- internally throttles itself
## to REPORT_INTERVAL_SECONDS, so callers never need their own timer.
static func maybe_report() -> void:
	var now := Time.get_ticks_usec()
	if _window_start_usec < 0:
		_window_start_usec = now
		return
	var window_usec := now - _window_start_usec
	if window_usec < REPORT_INTERVAL_SECONDS * 1_000_000.0:
		return
	_print_report(window_usec)
	_totals_usec.clear()
	_call_counts.clear()
	_instance_counts.clear()
	_window_start_usec = now
	# _gauges deliberately NOT cleared -- a gauge holds its last-set value
	# across windows (so it still prints even in a window where the setter
	# never happened to run), unlike the per-window accumulators above.


static func _print_report(window_usec: int) -> void:
	print("=== PerfProbe window: %.2fs ===" % (window_usec / 1_000_000.0))
	var labels := _totals_usec.keys()
	labels.sort_custom(func(a, b): return _totals_usec[a] > _totals_usec[b])
	for label in labels:
		var total_ms: float = _totals_usec[label] / 1000.0
		var calls: int = _call_counts.get(label, 0)
		var per_call_ms: float = total_ms / float(max(calls, 1))
		print("  [time] %-40s %8.2fms total  %6d calls  %6.4fms/call" % [label, total_ms, calls, per_call_ms])
	var instance_labels := _instance_counts.keys()
	instance_labels.sort()
	for label in instance_labels:
		print("  [count] %-40s %8d" % [label, _instance_counts[label]])
	var gauge_labels := _gauges.keys()
	gauge_labels.sort()
	for label in gauge_labels:
		print("  [gauge] %-40s %8d" % [label, _gauges[label]])
