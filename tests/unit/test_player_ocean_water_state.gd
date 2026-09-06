extends GutTest

## Player._resolve_water_state's OCEAN depth conversion used the real
## bathymetric scale (EarthChunkGenerator.EARTH_OCEAN_DEPTH_RANGE_METERS,
## 8000.0 -- correct for "real metres of depth", wrong for gameplay/tint
## calibration) all the way through -- unlike river/lake depth, which
## already used a gameplay-scaled figure (see docs/concept/rivers.md,
## RiverDepth). Reported directly: "the players submerged tint should
## gradually fill from the feet upwards as he walks down the shore into
## deeper water based on the elevation and slope", then, once river/lake
## were confirmed already gradual: "ocean depth too".
##
## Anchored at a real, measured near-shore point (see tools/probe_ocean_
## shore_gradient2.gd) rather than a synthetic elevation, mirroring
## test_player_river_water_state.gd's own real-world-anchored convention --
## a real Arctic coastline (lat 75.5849N, lon 40.7207E) whose own measured
## per-tile depth-fraction (~0.0056) sits almost exactly at the MEDIAN of
## 28 real shorelines sampled, so this is a representative case, not a
## cherry-picked outlier.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

## The real shore tile itself (lat 75.5849N, lon 40.7207E) -- measured
## directly (tools/probe_ocean_shore_gradient2.gd) at depth_fraction=0.0124
## right at the shore, rising to ~0.036 (peaking) by 2 tiles further out,
## before receding back toward dry land past 8 tiles -- a real, if noisy
## and non-monotonic (real generated terrain, not an idealised ramp),
## GRADUAL near-shore transition, not an instant jump.
const SHORE_TILE := Vector2i(24500, 1600)

## A real, unambiguously deep mid-Pacific point (lat 0N, lon 150W) --
## measured directly at ~22.5m of depth at OCEAN_DEPTH_RANGE_METERS=50.0,
## comfortably clear of WADE_DEPTH_METERS (1.5m). Guards against the fix
## overcorrecting: a smaller gameplay depth scale must not make genuinely
## deep open ocean read as merely wadeable.
var deep_ocean_tile: Vector2i

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	var geo := GeoCoordinates.new()
	deep_ocean_tile = geo.tile_for_coordinate(
		0.0, -150.0, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	chunk_manager.update(SHORE_TILE)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(SHORE_TILE) * TILE_SIZE
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Sanity: the fixture really is a real, near-sea-level ocean shoreline --
## if this stops being true (e.g. a future elevation/noise change), the
## test itself needs re-examining, not just the fix it checks.
func test_sanity_the_fixture_tile_really_is_a_shallow_ocean_shoreline():
	var elevation := chunk_manager.elevation_at_global(SHORE_TILE.x, SHORE_TILE.y)
	assert_almost_eq(
		elevation, EarthChunkGenerator.EARTH_SEA_LEVEL, 0.02,
		"the fixture tile should sit right at real sea level, not deep inland or far out to sea"
	)


func test_standing_right_at_the_waters_edge_is_not_instantly_full_swimming():
	var result := player._resolve_water_state(SHORE_TILE, 0.1)
	assert_ne(
		result.mode, "swimming",
		"the very first wet tile at a real, measured near-shore slope must not already read as full swimming"
	)
	assert_lt(
		result.water_depth, WaterMovementModel.WADE_DEPTH_METERS,
		"depth right at the water's edge should be well under the wade/swim threshold"
	)


## Walking a few real tiles further out onto the SAME measured transect
## must show a GRADUAL depth increase, not the depth already having
## maxed out at the very first wet tile (the bug this fix closes -- with
## the old 8000.0 scale, this same transect's own +1 tile already reads as
## many metres deep).
func test_walking_a_few_tiles_further_out_is_gradually_deeper_not_already_maxed():
	var at_shore := player._resolve_water_state(SHORE_TILE, 0.1)
	var two_tiles_out := player._resolve_water_state(SHORE_TILE + Vector2i(0, 2), 0.1)
	assert_gt(
		two_tiles_out.water_depth, at_shore.water_depth,
		"depth should keep rising as the player walks further from shore"
	)
	assert_lt(
		at_shore.water_depth, WaterMovementModel.WADE_DEPTH_METERS * 0.9,
		"the water's very edge should read as clearly shallower than the swim threshold, not already at it"
	)


## A real, unambiguously deep open-ocean point must still resolve to real
## swimming under the new, smaller depth scale -- the fix must not
## overcorrect a genuinely deep ocean into reading as merely wadeable.
func test_a_genuinely_deep_open_ocean_point_still_resolves_to_swimming():
	chunk_manager.update(deep_ocean_tile)
	var result := player._resolve_water_state(deep_ocean_tile, 0.1)
	assert_eq(result.mode, "swimming")
	assert_gt(
		result.water_depth, WaterMovementModel.WADE_DEPTH_METERS * 5.0,
		"genuinely deep open ocean should read as far past the wade threshold, not just barely over it"
	)
