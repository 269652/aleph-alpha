extends GutTest

## World's wiring of the SimulationScheduler (FPS regression round 11, see
## docs/concept/soil_fauna.md and test_simulation_scheduler.gd) -- a
## source-contract test on the function bodies, the same shape and reasoning
## test_world_crush_wiring.gd / test_world_creature_scan_consolidation.gd
## already use: World resolves its world state internally, so standing one
## up headlessly to drive _process live is not worth the fight.
##
## Three things must be true for a parked marker to ever wake up again:
## World owns a scheduler, publishes it as the current one before the world
## can run (markers only park when one is current), and advances it once
## per frame from its own _process -- before the creature steps, so a marker
## woken this frame is processed this frame.

const World = preload("res://scenes/world.gd")


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_world_owns_one_scheduler():
	var world := World.new()
	autofree(world)
	assert_not_null(world._simulation_scheduler)


func test_ready_publishes_the_scheduler_before_the_world_is_marked_ready():
	var body := _body_of("_ready")
	var published_at := body.find("SimulationScheduler.set_current(_simulation_scheduler)")
	var ready_at := body.find("_world_ready = true")
	assert_gt(published_at, -1, "markers only park when a scheduler is current")
	assert_lt(published_at, ready_at, "and it must be current before the first frame the world runs")


func test_process_advances_the_scheduler_once_per_frame_before_any_creature_step():
	var body := _body_of("_process")
	var advance_at := body.find("_simulation_scheduler.advance(delta)")
	var first_step_at := body.find("_chunk_manager.step_water_disturbances(delta)")
	assert_gt(advance_at, -1, "parked markers are only ever woken from here")
	assert_lt(advance_at, first_step_at, "wake-ups come first, so a marker due this frame is processed this frame")
	assert_eq(body.count("_simulation_scheduler.advance("), 1, "exactly once per frame")


func test_the_scheduler_is_withdrawn_when_the_world_goes_away():
	var body := _body_of("_notification")
	assert_true(
		body.contains("SimulationScheduler.set_current(null)"),
		"a scheduler outliving its world would hand stale wake-ups to a new one"
	)
