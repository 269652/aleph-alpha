extends GutTest

## World's wiring of RiverFlowPass (src/rendering/river_flow_pass.gd) -- a
## source-contract test on the function bodies, the same shape
## test_world_perf_report_wiring.gd uses and for the same reason (standing
## a World up headlessly is not worth the fight). Two things must be true:
## the river layer is adopted into the pass once the chunk manager has been
## handed it (painting keeps going to the same TileMapLayer, wherever it
## lives), and every client frame the pass is synced to the real camera's
## framing so the texel grid follows the view.

const World = preload("res://scenes/world.gd")


func _body_of(function_name: String) -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func %s(" % function_name)
	assert_gt(start, -1, "the premise: %s must still exist" % function_name)
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_ready_adopts_the_river_layer_into_the_pass_after_the_chunk_manager_has_it():
	var body := _body_of("_ready")
	var handed_at := body.find("_chunk_manager.set_river_flow_layer(_river_flow_fx)")
	var adopted_at := body.find("_river_flow_pass.adopt(_river_flow_fx)")
	assert_gt(handed_at, -1, "the premise: the chunk manager still paints the river layer")
	assert_gt(adopted_at, handed_at, "adopted after it is handed over -- the manager keeps the same node either way")


func test_client_process_syncs_the_pass_to_the_cameras_framing_every_frame():
	var body := _body_of("_client_process")
	assert_true(body.contains("get_viewport().get_camera_2d()"), "the real camera, not a remembered one")
	assert_true(body.contains("_river_flow_pass.sync("), "synced once per client frame")
	assert_true(body.contains("get_screen_center_position()"), "from the camera's actual on-screen centre (smoothing included)")
	assert_true(body.contains("DisplayScaling.visible_tiles_across("),
		"the framed world span comes from the same tile-based framing the decoration radius uses, not raw window pixels")
