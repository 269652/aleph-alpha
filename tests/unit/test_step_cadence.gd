extends GutTest

## StepCadence (src/gameplay/step_cadence.gd): the round-robin clock behind
## World's batched ecology steps (FPS regression round 13, docs/concept/
## ecosystem_dynamics.md "Ecology steps run at a cadence, not a frame rate").
##
## ~25 chunk-manager steps -- tall grass, leaf litter, tree growth, ants,
## bees, flowers, footprints, ground food, worms, fruiting... -- used to run
## every frame, each walking every loaded chunk: ~25 ms of a 6 fps frame,
## and at 60 fps the same 25 ms of EVERY frame. Every one of them is a
## population, growth or economy step that takes the seconds elapsed and
## moves on world time; none needs a frame's freshness. So each label runs
## once per INTERVAL_SECONDS with the time accumulated since it last ran,
## and the labels are staggered so the first interval spreads them across
## its frames instead of stacking them on one.

const StepCadence = preload("res://src/gameplay/step_cadence.gd")

const FRAME := 1.0 / 60.0
const LABELS: Array[String] = ["a", "b", "c", "d", "e", "f"]


func test_the_interval_is_exactly_pinned():
	assert_eq(StepCadence.INTERVAL_SECONDS, 0.25)


func test_at_the_reference_frame_rate_each_label_runs_once_per_interval_with_the_time_it_waited():
	var cadence := StepCadence.new(LABELS)
	var runs := {}
	var frames := roundi(StepCadence.INTERVAL_SECONDS / FRAME) * 4  # four intervals
	for frame in frames:
		for due in cadence.advance(FRAME):
			runs[due[0]] = runs.get(due[0], []) + [due[1]]
	for label in LABELS:
		assert_true(runs.has(label), "%s must have run" % label)
		assert_between(runs[label].size(), 3, 4, "%s: about once per interval over four intervals" % label)
		for elapsed in runs[label].slice(1):
			assert_almost_eq(elapsed, StepCadence.INTERVAL_SECONDS, FRAME * 1.01, "%s is handed the interval it waited, give or take a frame" % label)


func test_the_first_interval_spreads_the_labels_across_its_frames():
	var cadence := StepCadence.new(LABELS)
	var per_frame: Array[int] = []
	var frames := roundi(StepCadence.INTERVAL_SECONDS / FRAME)
	for frame in frames:
		per_frame.append(cadence.advance(FRAME).size())
	var busiest: int = per_frame.max()
	assert_lte(busiest, ceili(float(LABELS.size()) / float(frames)) + 1, "no frame carries much more than its share: %s" % [per_frame])
	assert_eq(per_frame.reduce(func(sum, n): return sum + n, 0), LABELS.size(), "and every label ran exactly once in the first interval")


func test_a_frame_as_long_as_the_interval_runs_every_label_every_frame():
	# 4 fps: a frame is the interval, so nothing is throttled below what the
	# frame already gave -- the low frame-rate case stays exactly as it was.
	var cadence := StepCadence.new(LABELS)
	cadence.advance(StepCadence.INTERVAL_SECONDS)  # the stagger's first pass
	var due := cadence.advance(StepCadence.INTERVAL_SECONDS)
	assert_eq(due.size(), LABELS.size())
	for entry in due:
		assert_almost_eq(entry[1], StepCadence.INTERVAL_SECONDS, 0.0001, "the whole frame, nothing lost")


func test_no_simulated_time_is_ever_lost():
	var cadence := StepCadence.new(LABELS)
	var handed := {}
	var total := 0.0
	for frame in 500:
		var delta := FRAME if frame % 7 != 0 else 0.3  # an uneven frame every so often
		total += delta
		for due in cadence.advance(delta):
			handed[due[0]] = handed.get(due[0], 0.0) + due[1]
	for label in LABELS:
		assert_almost_eq(handed[label], total, StepCadence.INTERVAL_SECONDS + 0.3 + 0.0001, "%s: everything it was ever due, minus at most one interval still accumulating" % label)
		assert_lte(handed[label], total + 0.0001, "%s never runs ahead of the wall clock" % label)


func test_labels_due_on_the_same_frame_come_back_in_the_order_they_were_given():
	var cadence := StepCadence.new(LABELS)
	var due := cadence.advance(1.0)  # one long frame: everything is due at once
	var order: Array[String] = []
	for entry in due:
		order.append(entry[0])
	assert_eq(order, LABELS, "two steps that run on the same frame keep their relative order")
