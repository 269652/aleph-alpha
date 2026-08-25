extends GutTest

## The per-frame chunk-load budget, as the RUNNING GAME actually gets it.
##
## EarthChunkManager grew `max_chunk_loads_per_update` plus the derivation
## `chunks_per_update_for` (pinned in test_earth_chunk_manager.gd), but the
## field defaults to 0 == unbudgeted, so until World hands it a value the
## whole thing is dormant infrastructure with no in-game effect. The bug it
## exists to fix is a walking frame-rate dip: 20-26 FPS falling to 6-8 every
## time a chunk boundary is crossed and update() generates a whole column of
## chunks inside one frame. So the WIRING is what this file pins -- a feature
## that is green in its own unit test and invisible while playing is not done
## (same reasoning as test_world_inventory_wiring.gd).
##
## Kept as its own tiny file (it preloads scripts and builds three bare
## nodes) so it runs in seconds rather than living in
## test_earth_chunk_manager.gd, which takes ten-plus minutes.

const World = preload("res://scenes/world.gd")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const Taming = preload("res://src/gameplay/taming.gd")

var world: World
var manager: EarthChunkManager
var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D


func before_each():
	# Not add_child()'d: _apply_streaming_budget touches one plain
	# (non-@onready) field, the same way test_world_inventory_wiring builds
	# World.
	world = World.new()
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)


func after_each():
	world.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## The body of World._ready, read straight from source -- the authority on
## what the running game actually does at startup. Same technique as
## test_world_backup_paths.gd's _wipe_body().
func _ready_body() -> String:
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	var start := source.find("func _ready()")
	assert_gt(start, -1, "World._ready should still exist")
	var end := source.find("\nfunc ", start + 1)
	if end == -1:
		end = source.length()
	return source.substr(start, end - start)


## The whole point: the manager the game actually streams with is budgeted.
func test_applying_the_streaming_budget_leaves_the_manager_budgeted():
	world._apply_streaming_budget(manager)

	assert_gt(
		manager.max_chunk_loads_per_update, 0,
		"the chunk manager was left unbudgeted, i.e. loading a whole column per frame"
	)


## ...and with the DERIVED number, not a hand-picked one. Re-deriving it here
## from EarthChunkManager's own pure, separately-tested function is what stops
## this from silently becoming an eyeballed literal.
func test_the_budget_is_the_derived_value_not_a_hardcoded_one():
	world._apply_streaming_budget(manager)

	assert_eq(
		manager.max_chunk_loads_per_update,
		EarthChunkManager.chunks_per_update_for(
			World.STREAMING_BUDGET_TILES_PER_SECOND, World.STREAMING_BUDGET_FRAMES_PER_SECOND
		)
	)


## The two inputs, pinned against the real constants they claim to come from
## rather than restated as literals: the fastest pace a player can actually
## travel at (a mount, not a walk -- see Taming.MOUNTED_SPEED), in tiles.
func test_the_speed_input_is_the_fastest_pace_the_player_can_actually_travel():
	assert_eq(
		World.STREAMING_BUDGET_TILES_PER_SECOND,
		Taming.MOUNTED_SPEED / float(TerrainRenderer.TILE_SIZE)
	)
	assert_gt(
		Taming.MOUNTED_SPEED, Player.BASE_SPEED,
		"a mount is the fast case; if that stops being true, re-derive the budget"
	)


## The frame-rate input is the WORST rate the playtest measured (6-8 FPS at a
## chunk boundary), not the smooth 20-26. Sizing against the dip is the
## conservative direction: fewer update() calls per second means MORE chunks
## must be allowed per call, so the budget cannot itself be what makes a
## chunk arrive late.
func test_the_frame_rate_input_is_the_measured_worst_case_not_the_smooth_rate():
	assert_eq(World.STREAMING_BUDGET_FRAMES_PER_SECOND, 6.0)


## And the number that falls out is 1 -- one chunk generated per frame, which
## is exactly the stall being removed.
func test_the_derived_budget_is_one_chunk_per_frame():
	world._apply_streaming_budget(manager)

	assert_eq(manager.max_chunk_loads_per_update, 1)


## The exact constants above are therefore NOT load-bearing: across the whole
## measured frame-rate band, at both the walking and the mounted pace, the
## derivation returns the same 1. That is what makes this a derived value
## rather than a tuned one -- there is no knife edge to sit on.
func test_the_budget_is_one_across_the_whole_measured_frame_rate_band():
	for frames_per_second in [6.0, 8.0, 20.0, 26.0, 30.0, 60.0, 144.0]:
		for speed in [Player.BASE_SPEED, Taming.MOUNTED_SPEED]:
			assert_eq(
				EarthChunkManager.chunks_per_update_for(
					speed / float(TerrainRenderer.TILE_SIZE), frames_per_second
				),
				1,
				"budget changed at %s fps, %s units/s" % [frames_per_second, speed]
			)


## The behaviour tests above prove the helper works; this proves _ready
## actually CALLS it, which is the half that was missing and the only half
## the player can see.
func test_ready_applies_the_streaming_budget_to_the_chunk_manager():
	assert_string_contains(_ready_body(), "_apply_streaming_budget(_chunk_manager)")


## The cold initial load keeps its own coroutine (update_with_progress) and
## must NOT be squeezed through a one-chunk-per-frame budget -- that would
## turn the loading screen into a minute of watching a progress bar crawl.
func test_the_cold_load_coroutine_is_left_alone():
	var source := FileAccess.get_file_as_string("res://scenes/world.gd")
	assert_string_contains(source, "update_with_progress")
