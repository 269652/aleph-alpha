extends GutTest

## Player._resolve_water_state must notice a real curated river (see
## docs/concept/rivers.md, river_depth.gd) -- before this, it only checked
## real elevation-below-sea-level (BiomeClassifier.depth_at), which every
## river tile fails by construction (a river never changes biome_at_global's
## own elevation-derived result), so a player could walk straight through a
## river with no wading/swimming, no submersion tint (SubmersionShader,
## already fully wired for ocean via character_view.gd), and no water
## ripples at all.
##
## Kept as its own small file, anchored at the real Dreisam/Gaskugel point,
## rather than living in test_player.gd: that file's shared before_each
## already loads chunks around tile (0, 0) (the north pole/date line, nowhere
## near any curated river), and test_player.gd is itself already one of the
## slowest files in the suite (see project_godot_test_execution memory) --
## adding one more real EarthChunkManager.update() there would only make
## that worse for a fixture every other test in the file would have to pay
## for and not use.

const PlayerScene = preload("res://scenes/player.tscn")
const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

const TILE_SIZE := TerrainRenderer.TILE_SIZE

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var chunk_manager: EarthChunkManager
var player: Player
var river_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	chunk_manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	var geo := GeoCoordinates.new()
	river_tile = geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	chunk_manager.update(river_tile)

	player = PlayerScene.instantiate()
	player.name = str(multiplayer.get_unique_id())
	add_child(player)
	player.position = Vector2(river_tile) * TILE_SIZE
	player.setup(chunk_manager, TILE_SIZE)


func after_each():
	remove_child(player)
	player.free()
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## Sanity: the fixture really is standing on the Dreisam's own curated
## waypoint -- if this stops being true the test itself needs
## re-examining, not just the fix it's checking.
func test_sanity_the_fixture_tile_really_is_a_river():
	assert_true(chunk_manager.is_river_at_global(river_tile.x, river_tile.y))


## Was `assert_eq(result.mode, "swimming")`, back when river depth was an
## AUTHORED 2.5 m taper chosen so a curated river would cross the swim
## threshold. Depth is now solved from the Dreisam's real curated discharge
## (see EarthChunkGenerator.river_hydraulics_at_global), and the real answer
## at Freiburg is ~0.3 m -- a wadeable stream, which is what the real
## Dreisam is and why a town grew at that crossing.
##
## So the claim worth pinning is no longer "you swim here" (which was only
## ever true of an invented number) but "the river is real water you have to
## deal with, not dry ground" -- with the swim path itself proved against a
## genuinely deep river below.
func test_standing_at_the_river_centerline_puts_the_player_in_real_water():
	var result := player._resolve_water_state(river_tile, 0.1)
	assert_ne(result.mode, "walking", "a river must not read as dry ground")
	assert_true(
		result.mode == "wading" or result.mode == "swimming",
		"expected real water movement, got %s" % result.mode
	)


## The other end of the real range, so the depth -> movement-mode chain is
## pinned across it rather than at one point. The Rhine at Cologne carries
## ~267x the Dreisam's discharge in a ~560 m channel; a river that large is
## unambiguously not wadeable, so a real big-river cell must still produce
## real swimming. (Deliberately a BIG river rather than a merely deep spot:
## depth varies with local slope along any one course, so picking a large
## discharge is what makes this robust to which waypoint gets sampled.)
func test_a_genuinely_large_river_still_resolves_to_swimming():
	var geo := GeoCoordinates.new()
	var rhine_tile := geo.tile_for_coordinate(
		50.93639, 6.95278, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	chunk_manager.update(rhine_tile)
	assert_gt(
		chunk_manager.river_depth_meters_at_global(rhine_tile.x, rhine_tile.y), 1.5,
		"the Rhine at Cologne is nowhere near wadeable; if this drops, the hydraulics changed"
	)
	assert_eq(player._resolve_water_state(rhine_tile, 0.1).mode, "swimming")


func test_standing_at_the_river_centerline_reports_real_nonzero_depth_driven_speed():
	var result := player._resolve_water_state(river_tile, 0.1)
	assert_lt(result.speed_multiplier, 1.0, "swimming/wading must be slower than a dry walk")
	# The raw depth _update_character_view feeds to CharacterView.
	# set_submersion_depth (see character_view.gd) -- this used to be
	# computed right here and discarded once collapsed into mode/
	# speed_multiplier alone, leaving wading with no visual signature.
	assert_gt(result.water_depth, 0.0, "a real river tile should report real, nonzero depth")
