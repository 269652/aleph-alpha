extends GutTest

## World._step_path_scarring wiring for the trail tier (docs/concept/
## infrastructure.md's "path -> trail -> road", PathScarring.is_trail/
## trail_tiles, EarthChunkManager.record_trail_formed_if_new/
## record_trail_reclaimed, TerrainRenderer.TRAIL_TILE_ID).
##
## The trail tier itself is fully covered where it actually lives --
## PathScarring (test_path_scarring.gd), TerrainRenderer
## (test_terrain_renderer.gd), and EarthChunkManager's own event recorders
## (test_earth_chunk_manager.gd) -- every one of those is a real
## behavioural test. What is left here is pure orchestration glue:
## _step_path_scarring resolves multiplayer.get_unique_id()/_players
## internally instead of taking an already-resolved local_player parameter
## the way _step_ecology_batch/_maybe_update_interaction_prompt do, so
## calling it on a bare, deliberately-not-add_child()'d World (the
## convention test_world_ecology_batch_farm_plots.gd and
## test_world_interaction_prompt_throttle.gd both use) would hit
## `multiplayer` outside a tree -- not worth faking a whole SceneTree
## multiplayer stack for. Same call test_world_simulation_ownership.gd
## already made for _step_ecology_batch's own wiring: a source-contract
## test on the function body, not a behavioural one.

const World = preload("res://scenes/world.gd")


func _step_path_scarring_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _step_path_scarring")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_step_path_scarring_still_exists():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_gt(source.find("func _step_path_scarring"), -1, "the step must still be called that")


## The premise every other assertion here builds on: a trail is actually
## painted, distinctly from an ordinary worn path.
func test_trail_tiles_are_painted_with_the_trail_tile_id():
	var body := _step_path_scarring_body()
	assert_true(body.contains("_path_scarring.trail_tiles()"), "must read the trail tier")
	assert_true(body.contains("TerrainRenderer.TRAIL_TILE_ID"), "must paint the trail tile id")


## A tile becoming a trail is exactly as much a real, why-inspectable event
## as one becoming an ordinary worn path (record_path_worn_if_new) -- see
## EarthChunkManager.record_trail_formed_if_new's own doc comment.
func test_forming_a_trail_records_a_real_event():
	var body := _step_path_scarring_body()
	assert_true(body.contains("record_trail_formed_if_new(tile)"))


## And tapering back down is recorded too, distinctly from a full reclaim
## (EarthChunkManager.record_trail_reclaimed's own doc comment: it must NOT
## chain into ruin formation the way record_path_reclaimed does), and
## repaints the tile as ordinary trampled earth rather than leaving the
## trail texture behind.
func test_tapering_a_trail_records_a_real_event_and_repaints_as_earth():
	var body := _step_path_scarring_body()
	assert_true(body.contains("record_trail_reclaimed(tile)"))
	var trail_paint_at := body.find("TerrainRenderer.TRAIL_TILE_ID")
	var taper_repaint_at := body.find("TerrainRenderer.EARTH_TILE_ID", trail_paint_at)
	assert_gt(trail_paint_at, -1)
	assert_gt(
		taper_repaint_at, trail_paint_at, "tapering repaints earth after the trail is first painted"
	)
	assert_gt(
		body.find("record_trail_reclaimed(tile)"),
		taper_repaint_at,
		"records the taper alongside its repaint"
	)


## Ordering matters: a tile must already be recorded/painted as an ordinary
## worn path before it can ever show as a trail. PathScarring.trail_tiles()
## being a strict subset of worn_tiles() only guarantees the DATA is a
## subset -- this guarantees the RENDER/EVENT ordering respects it too, so
## _scarred_tiles already has an entry for every tile the trail loop is
## about to touch.
func test_the_worn_loop_runs_before_the_trail_loop():
	var body := _step_path_scarring_body()
	var worn_loop_at := body.find("_path_scarring.worn_tiles()")
	var trail_loop_at := body.find("_path_scarring.trail_tiles()")
	assert_gt(worn_loop_at, -1)
	assert_gt(trail_loop_at, -1)
	assert_gt(trail_loop_at, worn_loop_at, "the trail loop must run after the worn loop")


## The taper loop must run before the final full-reclaim loop below it: a
## tile that skips straight through the trail tier to bare ground in one
## gap relies on the taper loop's own _trailed_tiles bookkeeping (erasing
## the tile once it is no longer a trail) having already happened before
## the final loop decides whether the tile is fully reclaimed.
func test_the_taper_loop_runs_before_the_final_reclaim_loop():
	var body := _step_path_scarring_body()
	var taper_at := body.find("_trailed_tiles.keys().duplicate()")
	var reclaim_at := body.find("_scarred_tiles.keys().duplicate()")
	assert_gt(taper_at, -1)
	assert_gt(reclaim_at, -1)
	assert_gt(reclaim_at, taper_at, "the final reclaim loop must run after the taper loop")
