extends GutTest

## The builder on a construction site (docs/concept/building.md, "Somebody
## is working on it"). Asked for directly: *"the construction site should
## show a builder working on it"*.
##
## A small purpose-built walker, like the Farmer and the Lumberjack and for
## the same reason -- so what it owes is small and exact: he works his own
## plot, he moves about it rather than standing like a prop, and he never
## walks off the site, because the site is the job.

const ConstructionWorkerMarker = preload("res://src/rendering/construction_worker_marker.gd")

const PLOT := Rect2(Vector2(100.0, 200.0), Vector2(32.0, 32.0))
const FRAME := 1.0 / 60.0

var worker: ConstructionWorkerMarker


func before_each():
	worker = ConstructionWorkerMarker.new()
	worker.plot = PLOT
	worker.seed_value = 4242
	worker.position = PLOT.position + PLOT.size * 0.5
	add_child(worker)


func after_each():
	remove_child(worker)
	worker.free()


func _work(seconds: float) -> Array:
	var seen: Array = []
	for i in int(seconds / FRAME):
		worker._process(FRAME)
		seen.append(worker.position)
	return seen


func test_a_builder_never_leaves_the_site_he_is_working():
	for point in _work(60.0):
		assert_true(
			PLOT.has_point(point as Vector2),
			"%s is off the plot %s -- the site is the job" % [point, PLOT]
		)


func test_a_builder_moves_about_the_site_rather_than_standing_like_a_prop():
	var seen := _work(30.0)
	var furthest := 0.0
	for point in seen:
		furthest = maxf(furthest, (point as Vector2).distance_to(seen[0] as Vector2))
	assert_gt(furthest, 4.0, "a builder who never moves is a statue on a plot")


## And he stops to work: a figure gliding continuously about a building
## site is a patrol, not a workman.
func test_a_builder_stops_to_work_between_moves():
	var seen := _work(30.0)
	var still := 0
	for i in range(1, seen.size()):
		if (seen[i] as Vector2).is_equal_approx(seen[i - 1] as Vector2):
			still += 1
	assert_gt(still, seen.size() / 10, "a builder spends real time working, not only walking")


func test_two_builders_with_the_same_seed_work_the_same_way():
	var twin := ConstructionWorkerMarker.new()
	twin.plot = PLOT
	twin.seed_value = worker.seed_value
	twin.position = worker.position
	add_child(twin)
	for i in 600:
		worker._process(FRAME)
		twin._process(FRAME)
	assert_almost_eq(worker.position.x, twin.position.x, 0.001)
	assert_almost_eq(worker.position.y, twin.position.y, 0.001)
	remove_child(twin)
	twin.free()


## A worker with no site given to him stays exactly where he was put,
## rather than walking off toward the world's origin.
func test_a_builder_with_no_plot_stays_put():
	var stray := ConstructionWorkerMarker.new()
	stray.position = Vector2(10.0, 20.0)
	add_child(stray)
	for i in 120:
		stray._process(FRAME)
	assert_eq(stray.position, Vector2(10.0, 20.0))
	remove_child(stray)
	stray.free()
