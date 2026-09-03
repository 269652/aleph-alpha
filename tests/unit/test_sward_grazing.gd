extends GutTest

## The grazing lawn as a closed loop (docs/concept/ground_cover.md, "The
## grazing lawn is food").
##
## `FOOD_UNDERFOOT` was a free lunch: a hungry animal standing on grassland
## was fed, the world lost nothing, and a meadow therefore had no carrying
## capacity at all -- the sward was a picture of grazing rather than a
## participant in it.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const GroundCover = preload("res://src/world/ground_cover.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	var geo := GeoCoordinates.new()
	manager.update(Vector2i(
		geo.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	))


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


## A grassland tile with real sward on it, in world pixels.
func _a_sward_tile() -> Vector2:
	for chunk_coord in manager._ground_cover_sims:
		var sward: GroundCover = manager._ground_cover_sims[chunk_coord]
		var origin: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE
		for y in 16:
			for x in 16:
				var cell := Vector2i(x, y)
				if sward.can_crop(cell, 0.0):
					return Vector2(
						(origin.x + x + 0.5) * TerrainRenderer.TILE_SIZE,
						(origin.y + y + 0.5) * TerrainRenderer.TILE_SIZE
					)
	return Vector2.INF


func test_the_test_world_has_a_sward_to_graze():
	assert_ne(_a_sward_tile(), Vector2.INF, "no grassland sward loaded to test against")


func test_an_animal_can_take_a_bite_of_sward():
	assert_true(manager.crop_sward_at(_a_sward_tile()))


## The loop: the bite costs the world something.
func test_a_bite_leaves_less_sward_behind():
	var at := _a_sward_tile()
	var before := manager.sward_cover_at(at)
	manager.crop_sward_at(at)
	assert_lt(manager.sward_cover_at(at), before)


## Carrying capacity, and the whole reason this closes a loop: a patch eaten
## bare stops feeding, so an animal has to move on and a meadow can be
## overstocked.
func test_a_patch_eaten_bare_stops_feeding():
	var at := _a_sward_tile()
	var bites := 0
	while manager.crop_sward_at(at) and bites < 200:
		bites += 1
	assert_gt(bites, 0, "the patch never fed anything")
	assert_lt(bites, 200, "an animal fed forever on one tile")
	assert_false(manager.crop_sward_at(at), "bare ground is still offering bites")


## ...and it comes back, so this is a pasture rather than a desert.
func test_an_eaten_patch_recovers():
	var at := _a_sward_tile()
	while manager.crop_sward_at(at):
		pass
	manager.step_ground_cover(EarthChunkManager.GRASS_REFRESH_INTERVAL * 200.0)
	assert_true(manager.crop_sward_at(at), "an eaten meadow never grew back")


## Nothing to crop where nothing grows -- ocean, rock, sand.
func test_bare_ground_offers_no_bite():
	assert_false(manager.crop_sward_at(Vector2(-9_000_000.0, -9_000_000.0)))


# -- the redraw, and how often it happens -----------------------------------


## A bite has to show on the frame the player watched it happen -- the same
## reasoning graze_grass_at and take_worm_at give for their own immediate
## resyncs. But `_sync_sward` rebuilds EVERY visible rosette in the tile
## window, and a herd grazing means several of those a second for one bite
## each.
##
## So the bite marks the layer dirty and the next step redraws it once,
## however many animals bit in between: same frame, one rebuild.
func test_a_bite_does_not_rebuild_the_whole_sward_by_itself():
	var at := _a_sward_tile()
	var before := manager.sward_rebuild_count()
	manager.crop_sward_at(at)
	manager.crop_sward_at(at)
	manager.crop_sward_at(at)
	assert_eq(manager.sward_rebuild_count(), before, "each mouthful redrew the whole meadow")


## ...and the redraw really does happen, on the very next step, without
## waiting for the throttle.
func test_a_bite_is_redrawn_on_the_next_step():
	var at := _a_sward_tile()
	manager.crop_sward_at(at)
	var before := manager.sward_rebuild_count()
	manager.step_ground_cover(0.001)  # far inside the refresh throttle
	assert_eq(manager.sward_rebuild_count(), before + 1)


## A herd of animals grazing in one frame costs ONE rebuild between them.
func test_a_whole_herd_grazing_costs_one_redraw():
	var at := _a_sward_tile()
	for animal in 12:
		manager.crop_sward_at(at)
	var before := manager.sward_rebuild_count()
	manager.step_ground_cover(0.001)
	assert_eq(manager.sward_rebuild_count(), before + 1)


## Nothing grazed, nothing redrawn: an idle meadow does not churn the layer.
func test_an_ungrazed_meadow_is_not_redrawn():
	manager.step_ground_cover(0.001)
	var before := manager.sward_rebuild_count()
	manager.step_ground_cover(0.001)
	assert_eq(manager.sward_rebuild_count(), before)
