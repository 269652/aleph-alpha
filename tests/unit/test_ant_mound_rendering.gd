extends GutTest

## Ant mounds and their traffic, on the ground (see docs/concept/soil_fauna.md's
## "What the player sees").
##
## `AntColony` has seeded ~10 mounds per chunk since it was written and drawn
## none of them. This is the half that puts them on screen: a mound sprite per
## colony entrance, and the workers coming and going on it.
##
## What lives here rather than in test_procedural_ant_mound_sprite.gd is the
## PLACEMENT -- which mounds are drawn, where their workers are in the world,
## and what happens when a chunk leaves decoration range.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const AntTraffic = preload("res://src/gameplay/ant_traffic.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const ProceduralAntMoundSprite = preload("res://src/rendering/procedural_ant_mound_sprite.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var geo_coordinates := GeoCoordinates.new()
var _berlin_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	_berlin_tile = Vector2i(
		geo_coordinates.tile_for_longitude(13.405, EarthChunkGenerator.WORLD_WIDTH_TILES),
		geo_coordinates.tile_for_latitude(52.52, EarthChunkGenerator.WORLD_HEIGHT_TILES)
	)
	manager.update(_berlin_tile)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func _mound_sprite_count() -> int:
	var total := 0
	for sprites in manager._mound_sprites.values():
		total += sprites.size()
	return total


# -- the mounds --------------------------------------------------------------


## The whole point: a colony that simulates and draws nothing is a colony the
## player cannot know exists.
func test_a_loaded_chunk_draws_a_sprite_for_every_mound_it_simulates():
	var simulated := 0
	for chunk_coord in manager._ant_colonies:
		if manager._decorates(chunk_coord):
			simulated += manager._ant_colonies[chunk_coord].mound_cells().size()
	assert_gt(simulated, 0, "the test world seeded no mounds at all")
	assert_eq(_mound_sprite_count(), simulated)


## A mound sits on its own cell, not near it: it is a hole in the ground at a
## specific place, and its workers are measured from it.
func test_a_mound_sprite_stands_on_its_own_tile():
	for chunk_coord in manager._mound_sprites:
		var origin: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE
		for cell in manager._mound_sprites[chunk_coord]:
			var sprite: Sprite2D = manager._mound_sprites[chunk_coord][cell]
			var tile_centre := Vector2(
				(origin.x + cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + cell.y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			assert_almost_eq(sprite.position.x, tile_centre.x, 0.01)
			assert_almost_eq(sprite.position.y, tile_centre.y, 0.01)


## Decoration LOD is not optional here -- `DecorationLod` exists because ~2,900
## decorative sprites measurably decayed the frame rate, and mounds seed at ten
## per chunk across every soil biome.
func test_mounds_are_dropped_when_their_chunk_leaves_decoration_range():
	assert_gt(_mound_sprite_count(), 0, "nothing was drawn to begin with")
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	for chunk_coord in manager._mound_sprites:
		if not manager._decorates(chunk_coord):
			assert_eq(
				manager._mound_sprites[chunk_coord].size(),
				0,
				"a chunk out of decoration range is still carrying mound sprites"
			)


# -- the traffic on them -----------------------------------------------------


## Workers are drawn where the colony is, not scattered over the map.
func test_every_drawn_worker_is_within_its_own_colony_s_reach():
	var workers := manager.visible_ant_workers()
	assert_gt(workers.size(), 0, "no ant traffic was drawn at all")
	var entrances: Array[Vector2] = []
	for chunk_coord in manager._mound_sprites:
		for cell in manager._mound_sprites[chunk_coord]:
			entrances.append(manager._mound_sprites[chunk_coord][cell].position)
	for worker in workers:
		var nearest := INF
		for entrance in entrances:
			nearest = minf(nearest, entrance.distance_to(worker))
		assert_lt(
			nearest,
			AntTraffic.MAX_RANGE_PX + ProceduralAntMoundSprite.world_scale() * 16.0,
			"a worker was drawn nowhere near a mound"
		)


## A mound with three motionless dots on it reads as a rock with specks. The
## movement is the entire reason this layer exists.
func test_workers_walk():
	var before := manager.visible_ant_workers()
	manager.step_ants(2.0)
	var after := manager.visible_ant_workers()
	assert_eq(before.size(), after.size(), "the roster changed size between frames")
	var moved := 0
	for index in before.size():
		if before[index].distance_to(after[index]) > 0.5:
			moved += 1
	assert_gt(moved, before.size() / 2, "the ants are standing still")


## Every mound in view carries a full crew.
func test_each_drawn_mound_carries_its_whole_crew():
	assert_eq(
		manager.visible_ant_workers().size(),
		_mound_sprite_count() * AntTraffic.WORKERS_PER_MOUND
	)


## ...and nothing is drawn where there is no colony.
func test_no_traffic_is_drawn_once_every_mound_is_out_of_range():
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	for chunk_coord in manager._mound_sprites.keys().duplicate():
		manager._mound_sprites[chunk_coord].clear()
	assert_eq(manager.visible_ant_workers().size(), 0)


## Walking away drops a chunk's mounds; walking back has to bring them back.
##
## Decoration range is not the same thing as load range -- a chunk stays loaded
## and simulating well past the radius it stops being drawn at -- so a layer
## that only builds its sprites in _load_chunk goes permanently blank the first
## time the player steps away and returns. The worm layer avoids this by
## re-syncing every chunk on its own step; so does this one.
func test_mounds_come_back_when_the_player_returns():
	var before := _mound_sprite_count()
	assert_gt(before, 0, "nothing was drawn to begin with")
	# Far enough to leave decoration range, close enough that the chunks are
	# not evicted and reloaded -- which would hide the bug behind a fresh load.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 2, 0))
	manager.step_ants(0.1)
	manager.update(_berlin_tile)
	manager.step_ants(0.1)
	assert_eq(_mound_sprite_count(), before, "the mounds never came back")


## Neighbouring mounds must not come out as the same stamp.
##
## Worth its own test rather than trusting the seed: art seeds here are hashed
## with Godot's `hash`, which CORRELATES neighbouring inputs rather than
## spreading them -- the clustering bug this project has hit five times, and the
## reason every per-cell ROLL in the sim layer uses `PixelNoise` instead. It is
## the right tool for an art variant (the same way `_sync_scrub_sprites` and
## `_sync_worm_sprites` use it) only as long as the sprite it feeds really does
## decorrelate it. Mounds already shipped one bug of exactly this shape: every
## mound in a chunk wearing an identical grain pattern.
func test_mounds_on_neighbouring_tiles_do_not_share_a_stamp():
	var generator := ProceduralAntMoundSprite.new()
	var drawn := {}
	for dy in 4:
		for dx in 4:
			var image := generator.generate_image(
				manager._mound_seed(Vector2i.ZERO, Vector2i(dx, dy))
			)
			var signature := ""
			for y in image.get_height():
				for x in image.get_width():
					signature += "1" if image.get_pixel(x, y).a > 0.0 else "0"
			drawn[signature] = true
	assert_gt(drawn.size(), 12, "neighbouring tiles are drawing the same mound")


## Dropping a chunk's mounds must free them THERE AND THEN, the way
## _unload_chunk already frees the very same sprites -- not defer to the end
## of a frame.
##
## The two teardown paths disagreed: _unload_chunk called free() and the
## decoration drop called queue_free(). Nothing processes a frame between a
## chunk leaving decoration range and coming back, so the old sprites were
## still in the tree when the new ones were made, and the world briefly held
## two mounds per mound. Caught by
## test_a_spread_tree_survives_unloading_and_reloading_its_chunk, which counts
## entities_parent's children across an evict/reload cycle and is exactly the
## invariant a deferred free breaks.
func test_dropping_a_chunks_mounds_frees_them_immediately():
	manager.update(_berlin_tile)
	var with_mounds := entities_parent.get_child_count()
	assert_gt(with_mounds, 0, "precondition: something was drawn")

	# Out of decoration range and straight back, with no frame in between --
	# exactly what an evict/reload does.
	var far := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far)
	manager.update(_berlin_tile)

	assert_eq(
		entities_parent.get_child_count(), with_mounds,
		"the old mounds are still in the tree alongside the new ones"
	)
