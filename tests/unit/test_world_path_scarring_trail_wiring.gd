extends GutTest

## World._step_path_scarring's trail-tier wiring (see PathScarring.is_trail,
## TerrainRenderer.TRAIL_TILE_ID, EarthChunkManager.record_trail_formed_if_new/
## record_trail_reclaimed) and its snow gate (see PathScarring, EarthChunk
## Manager.snow_depth) -- a source-contract test on the function body rather
## than a live one: _step_path_scarring resolves multiplayer internally
## rather than taking an already-resolved player the way its siblings do, so
## standing up a whole World node headlessly to drive it live is not worth
## the fight. Same spirit as test_world_simulation_ownership.gd's own
## _step_ecology_batch source-contract test, which this codebase already
## accepts for things a headless run cannot otherwise see.

const World = preload("res://scenes/world.gd")


func _step_path_scarring_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _step_path_scarring")
	assert_gt(start, -1, "the premise: this function must still exist and be named that")
	var body_end := source.find("\nfunc ", start + 1)
	return source.substr(start, body_end - start)


func test_the_premise_the_other_tests_rely_on():
	var body := _step_path_scarring_body()
	assert_true(body.contains("_path_scarring.worn_tiles()"), "must still diff against worn tiles at all")


## Sustained, heavier use of an already-worn path repaints it as the deeper
## Trail tile -- otherwise a tile crossed once looks identical to one walked
## to the ground, the exact "doesn't deepen" complaint this tier fixes.
func test_a_trail_tile_is_painted_for_a_tile_worn_to_the_trail_ceiling():
	var body := _step_path_scarring_body()
	assert_true(body.contains("_path_scarring.trail_tiles()"))
	assert_true(body.contains("TerrainRenderer.TRAIL_TILE_ID"))


## The same real state transition that renders a trail also records it as a
## real, `/why`-inspectable event -- the same composition every other
## emergence-substrate transition in this codebase already has.
func test_forming_a_trail_records_a_real_event():
	var body := _step_path_scarring_body()
	assert_true(body.contains("record_trail_formed_if_new"))


## Tapering from Trail back down to an ordinary worn Path is a real,
## distinct transition from a full reclaim -- the ground is still a path,
## just no longer compacted to the ceiling, so it repaints as EARTH_TILE_ID
## rather than being destroyed.
func test_tapering_off_the_trail_ceiling_repaints_as_the_ordinary_earth_tile():
	var body := _step_path_scarring_body()
	assert_true(body.contains("record_trail_reclaimed"))
	# Both TRAIL_TILE_ID (the paint-up branch) and EARTH_TILE_ID (the taper-
	# down branch) must appear in the body -- a body containing only one
	# would mean either painting or tapering is missing entirely.
	assert_true(body.contains("TerrainRenderer.EARTH_TILE_ID"))


## Ordering matters: a tile must already be tracked as an ordinary worn path
## BEFORE it can ever become a trail (PathScarring.trail_tiles() is a subset
## of worn_tiles()) -- painting the trail loop before the worn-tiles loop
## would risk a tile skipping straight to Trail without ever having been
## recorded/painted as Path first.
func test_the_worn_tiles_loop_runs_before_the_trail_loop():
	var body := _step_path_scarring_body()
	var worn_loop_at := body.find("_path_scarring.worn_tiles()")
	var trail_loop_at := body.find("_path_scarring.trail_tiles()")
	assert_gt(worn_loop_at, -1)
	assert_gt(trail_loop_at, -1)
	assert_lt(worn_loop_at, trail_loop_at, "the worn-tiles loop must run before the trail loop")


## Ordering matters here too: tapering off the trail ceiling must be
## resolved BEFORE the pre-existing full-reclaim loop runs, so a tile that
## decays straight through Trail to bare ground in one gap is still handled
## correctly by the full-reclaim loop's own widened guard rather than the
## taper logic reacting to a tile the reclaim loop already erased.
func test_the_taper_loop_runs_before_the_full_reclaim_loop():
	var body := _step_path_scarring_body()
	var taper_loop_at := body.find("record_trail_reclaimed")
	var reclaim_loop_at := body.find("record_path_reclaimed")
	assert_gt(taper_loop_at, -1)
	assert_gt(reclaim_loop_at, -1)
	assert_lt(taper_loop_at, reclaim_loop_at, "tapering off a trail must be resolved before the full reclaim loop")


## Reported live: "snow scarring should not be brown tint but rather
## transparent without tint". Root cause: PathScarring wore grass/forest
## tiles into permanent brown EARTH_TILE_ID dirt regardless of whether snow
## was currently lying on them -- SnowBombShader's own footprint/tread
## rendering is a transparent GPU overlay with no tint of its own
## (fragment() writes vec4(0.0) wherever it has nothing to draw), so that
## brown dirt tile was always what actually showed through a partially-
## cleared snow overlay. Walking on snow-covered grass should pack down
## snow, not instantly grow a patch of bare dirt underneath it -- so new
## wear is gated on snow_depth() being (effectively) zero.
func test_new_wear_does_not_accumulate_while_snow_is_lying_on_the_ground():
	var body := _step_path_scarring_body()
	assert_true(
		body.contains("_chunk_manager.snow_depth()"),
		"the new-wear branch must consult how much snow is currently lying"
	)


## The snow gate must guard the STEP-ON call (whether NEW wear accumulates),
## never the DECAY/RENDER passes below it -- an already-scarred path must
## still recover/repaint normally in winter, only fresh scarring is what
## snow prevents.
func test_the_snow_gate_guards_stepping_on_not_the_render_or_decay_passes():
	var body := _step_path_scarring_body()
	var advance_at := body.find("_path_scarring.advance(")
	var snow_check_at := body.find("_chunk_manager.snow_depth()")
	var step_on_at := body.find("_path_scarring.step_on(")
	var worn_tiles_at := body.find("_path_scarring.worn_tiles()")
	assert_gt(advance_at, -1)
	assert_gt(snow_check_at, -1)
	assert_gt(step_on_at, -1)
	assert_gt(worn_tiles_at, -1)
	# advance() (decay) must not be behind the snow gate.
	assert_lt(advance_at, snow_check_at, "wear must still decay/recover normally in winter")
	# The snow check must sit between advance() and step_on() -- guarding
	# the one call that adds NEW wear.
	assert_lt(snow_check_at, step_on_at, "the snow check must guard the step_on call")
	# The render/reclaim diff pass (worn_tiles) must not be behind the gate
	# either -- an already-scarred path still repaints/recovers in winter.
	assert_lt(step_on_at, worn_tiles_at)


## The Road tier (docs/concept/infrastructure.md) is LAID, not worn: a
## village street must never accumulate wear, never be repainted as a
## path/trail, and never be "reclaimed" (destroyed) when its non-existent
## wear decays -- every branch of this function that writes a tile must be
## guarded on the cell not being paved. Reported as the reason the wear
## model needed a ceiling before roads could exist at all.
func test_a_paved_road_cell_is_never_worn_repainted_or_reclaimed():
	var body := _step_path_scarring_body()
	var step_on_at := body.find("_path_scarring.step_on(")
	var pave_gate_before_step_on := body.substr(0, step_on_at).find("_is_paved(")
	assert_gt(pave_gate_before_step_on, -1, "stepping on a paved cell must add no wear at all")
	# Every later loop that writes a tile (worn paint, trail paint, taper,
	# reclaim) guards on the same predicate.
	assert_gte(body.count("_is_paved("), 5, "each tile-writing loop guards on the cell being paved")


func test_is_paved_reads_the_real_road_modification():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _is_paved(")
	assert_gt(start, -1, "the predicate must exist")
	var body_end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, body_end - start)
	assert_true(body.contains("TerrainRenderer.is_road_tile("), "paved means the real Road tile, nothing looser")
	assert_true(body.contains("modification_at_global("), "read from the world's own modifications")
