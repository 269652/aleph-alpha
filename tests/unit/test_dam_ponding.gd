extends GutTest

## A built stone dam actually ponds the river behind it -- the wiring that
## turns DamImpoundment's physics into something the player can see and
## swim in. See docs/concept/rivers.md's "Dams" section.
##
## Its own small file rather than living in test_earth_chunk_manager.gd,
## which already takes ten-plus minutes: this needs one real
## EarthChunkManager.update() at the real spawn area, and every other test
## in that file would have to pay for a fixture it does not use.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const DamImpoundment = preload("res://src/world/dam_impoundment.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var river_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)

	var geo := GeoCoordinates.new()
	# The Gaskugel on the Dreisam -- this game's own spawn point, and a real
	# curated river cell.
	river_tile = geo.tile_for_coordinate(
		48.007669, 7.805657, EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)
	manager.update(river_tile)


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


func test_the_fixture_really_is_an_undammed_river_cell():
	assert_true(manager.is_river_at_global(river_tile.x, river_tile.y))
	assert_false(manager.has_dam_at_global(river_tile.x, river_tile.y))


func test_building_a_dam_registers_it():
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "stone_dam"))
	assert_true(manager.has_dam_at_global(river_tile.x, river_tile.y))


## The whole point: water backs up BEHIND the dam. An upstream cell must
## get measurably deeper than it was before the dam existed.
func test_a_dam_ponds_the_river_upstream_of_it():
	var upstream := manager.upstream_river_tile(river_tile, 2)
	assert_ne(upstream, river_tile, "expected to find a real upstream cell to measure")

	var before := manager.river_depth_meters_at_global(upstream.x, upstream.y)
	manager.build_at_global(river_tile.x, river_tile.y, "stone_dam")
	var after := manager.river_depth_meters_at_global(upstream.x, upstream.y)

	assert_gt(after, before, "a dam must pond the water upstream of it")


## A dam raises water; it never lowers it. Nowhere on the river may get
## shallower because a dam was built.
func test_a_dam_never_makes_any_cell_shallower():
	var samples: Array[Vector2i] = []
	for back in range(0, 6):
		samples.append(manager.upstream_river_tile(river_tile, back))

	var before: Array[float] = []
	for tile in samples:
		before.append(manager.river_depth_meters_at_global(tile.x, tile.y))

	manager.build_at_global(river_tile.x, river_tile.y, "stone_dam")

	for i in samples.size():
		var after := manager.river_depth_meters_at_global(samples[i].x, samples[i].y)
		assert_gte(after, before[i] - 0.0001, "cell %s got shallower after damming" % samples[i])


## Removing the dam must release the pool -- the impoundment is derived from
## the dam's presence, so destroying it has to restore the natural river
## rather than leaving a permanent puddle.
func test_destroying_the_dam_releases_the_pool():
	var upstream := manager.upstream_river_tile(river_tile, 2)
	var natural := manager.river_depth_meters_at_global(upstream.x, upstream.y)

	manager.build_at_global(river_tile.x, river_tile.y, "stone_dam")
	assert_gt(manager.river_depth_meters_at_global(upstream.x, upstream.y), natural)

	manager.destroy_at_global(river_tile.x, river_tile.y)
	assert_false(manager.has_dam_at_global(river_tile.x, river_tile.y))
	assert_almost_eq(
		manager.river_depth_meters_at_global(upstream.x, upstream.y), natural, 0.0001
	)


## The pooling is bounded -- far enough upstream, the river is its natural
## self again. An unbounded backwater is exactly what a chunk-streamed world
## cannot afford.
func test_the_pool_does_not_reach_indefinitely_upstream():
	var far := manager.upstream_river_tile(river_tile, DamImpoundment.MAX_BACKWATER_TILES + 8)
	var natural := manager.river_depth_meters_at_global(far.x, far.y)
	manager.build_at_global(river_tile.x, river_tile.y, "stone_dam")
	assert_almost_eq(
		manager.river_depth_meters_at_global(far.x, far.y), natural, 0.0001,
		"pooling reached past its own bound"
	)


## Downstream of a dam the river runs on -- at steady state a dam delays
## water, it does not consume it, so the reach below is unchanged.
func test_the_river_below_a_dam_is_unchanged():
	var downstream := manager.upstream_river_tile(river_tile, -3)
	var before := manager.river_depth_meters_at_global(downstream.x, downstream.y)
	manager.build_at_global(river_tile.x, river_tile.y, "stone_dam")
	assert_almost_eq(
		manager.river_depth_meters_at_global(downstream.x, downstream.y), before, 0.0001
	)


## A dam on dry land is not a dam. It can still be built (it is just stacked
## rock), but it must not invent water where there is no river.
func test_a_dam_away_from_any_river_ponds_nothing():
	var dry := river_tile + Vector2i(0, 40)
	if manager.is_river_at_global(dry.x, dry.y):
		return  # geographic accident; nothing to prove here
	manager.build_at_global(dry.x, dry.y, "stone_dam")
	assert_eq(manager.river_depth_meters_at_global(dry.x, dry.y), 0.0)


# -- boulders shape the flow (see docs/concept/rivers.md) ---------------------

func _nearest_at(tile: Vector2i) -> Dictionary:
	return manager.generator.river_catalog().nearest_river_at(
		tile.x, tile.y,
		EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
	)


## Every wet tile in the channel cross-section -- the manager owns the
## slice (see wet_row_tiles_at_global) so the test builds boulders on
## exactly the tiles the crest check will inspect.
func _wet_row_through(tile: Vector2i) -> Array:
	return manager.wet_row_tiles_at_global(tile.x, tile.y)


## A dropped boulder reaches the shader as a world position, so the water
## can bend around the ROCK, not its tile -- the tile-baked eyot was tried
## and painted square grass holes.
func test_a_dropped_boulder_is_fed_to_the_flow_shader():
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "boulder"))
	manager.sync_river_flow_boulders()
	var positions := manager.river_flow_boulder_positions()
	var expected := Vector2(
		float(river_tile.x) * 16.0 + 8.0, float(river_tile.y) * 16.0 + 8.0
	)
	assert_true(
		positions.has(expected),
		"the dropped boulder's world position must be in the shader feed"
	)


## Every rock in the feed has its own radius, from its own size -- the
## dropped piece is a smashable-stone-sized boulder.
func test_a_dropped_boulder_feeds_its_own_radius():
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "boulder"))
	manager.sync_river_flow_boulders()
	var positions := manager.river_flow_boulder_positions()
	var radii := manager.river_flow_boulder_radii()
	assert_eq(radii.size(), positions.size(), "one radius per fed boulder")
	var expected_pos := Vector2(
		float(river_tile.x) * 16.0 + 8.0, float(river_tile.y) * 16.0 + 8.0
	)
	var index := positions.find(expected_pos)
	assert_gte(index, 0)
	assert_almost_eq(
		radii[index],
		RiverFlowShader.boulder_radius_px_for(EarthChunkManager.DROPPED_BOULDER_DIAMETER_CM), 1e-6
	)
	assert_almost_eq(
		manager.flow_boulder_diameter_cm_at_global(river_tile.x, river_tile.y),
		EarthChunkManager.DROPPED_BOULDER_DIAMETER_CM, 1e-6
	)
	assert_eq(manager.flow_boulder_diameter_cm_at_global(river_tile.x + 40, river_tile.y + 40), 0.0)


## The force balance is computed per rock from the reach's own solved
## current and depth: the dropped boulder at the fixture holds.
func test_a_dropped_boulder_holds_the_fixture_s_current():
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "boulder"))
	assert_true(manager.river_boulder_holds_at_global(river_tile.x, river_tile.y))
	var load: float = manager.river_boulder_load_at_global(river_tile.x, river_tile.y)
	assert_between(load, 0.0, 1.0)
	assert_eq(manager.river_boulder_load_at_global(river_tile.x + 40, river_tile.y + 40), 0.0, "no rock, no load")


## One rock never dams a river: a partial row is not a crest and raises no
## pool.
func test_a_partial_boulder_row_does_not_pond():
	var upstream := manager.upstream_river_tile(river_tile, 2)
	var natural := manager.river_depth_meters_at_global(upstream.x, upstream.y)
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "boulder"))
	assert_false(
		manager.boulder_row_blocks_at_global(river_tile.x, river_tile.y),
		"one boulder must not read as a closed row"
	)
	assert_almost_eq(
		manager.river_depth_meters_at_global(upstream.x, upstream.y), natural, 0.0001,
		"a single boulder must not pond the river"
	)


## THE feature: close the row -- a boulder on every wet tile across the
## channel -- and the pool rises upstream, from the same real weir physics
## the stone_dam uses.
func test_a_closed_boulder_row_ponds_the_river_upstream():
	var upstream := manager.upstream_river_tile(river_tile, 2)
	var natural := manager.river_depth_meters_at_global(upstream.x, upstream.y)
	var row := _wet_row_through(river_tile)
	assert_gte(row.size(), 2, "expected a real multi-tile wet row to close")
	for tile in row:
		if not manager.flow_boulder_at_global(tile.x, tile.y):
			assert_true(
				manager.build_at_global(tile.x, tile.y, "boulder"),
				"failed to drop a boulder at %s" % tile
			)
	assert_true(
		manager.boulder_row_blocks_at_global(river_tile.x, river_tile.y),
		"the closed row must read as a crest"
	)
	# The verdict must hold from EVERY tile of the wall, not just the tile
	# the wall was planned from: the impound walk follows the smoothed
	# centreline, which can pass any of them (found live: the walk visited
	# a wall tile whose own slice window had slid ~0.7 tiles downstream,
	# traded away half the wall, and read the river as open).
	for tile in row:
		assert_true(
			manager.boulder_row_blocks_at_global(tile.x, tile.y),
			"the wall must read closed from its own tile %s" % tile
		)
	var ponded := manager.river_depth_meters_at_global(upstream.x, upstream.y)
	assert_gt(
		ponded, natural + 0.05,
		"the closed row must pond the river (%.3f m -> %.3f m)" % [natural, ponded]
	)


## THE regression path found live ("current lines don't part around the
## boulder", three natural rocks in frame): the boulder set fills during
## chunk paints, but only layer setup and build/destroy pushed the
## uniform -- a session that loaded its chunks normally never synced, and
## the shader bent around nothing. Both halves pinned below: the built
## boulder surviving a reload, and -- the half that was actually broken --
## NATURAL boulders reaching the uniform with no build call ever made.
func test_a_persisted_boulder_still_bends_the_water_after_reload():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	assert_true(manager.build_at_global(river_tile.x, river_tile.y, "boulder"))
	var far := river_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0)
	manager.update(far)
	manager.update(river_tile)
	var expected := Vector2(
		float(river_tile.x) * 16.0 + 8.0, float(river_tile.y) * 16.0 + 8.0
	)
	assert_true(
		manager.river_flow_boulder_positions().has(expected),
		"the persisted boulder must be re-collected by the chunk repaint"
	)
	var material: ShaderMaterial = flow_layer.material
	var count: int = material.get_shader_parameter("boulder_count")
	assert_gt(count, 0, "the chunk reload must sync the shader uniform itself")
	flow_layer.free()


## The natural half: after nothing but layer setup and chunk loads, every
## collected natural river boulder must already be in the shader uniform.
## No build call, no manual sync -- exactly a fresh play session.
func test_natural_river_boulders_reach_the_shader_without_any_build():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	manager.update(river_tile + Vector2i(EarthChunkManager.CHUNK_SIZE, 0))
	var positions := manager.river_flow_boulder_positions()
	assert_gt(
		positions.size(), 0,
		"expected at least one natural boulder on a river tile near the Dreisam"
	)
	var material: ShaderMaterial = flow_layer.material
	var count: int = material.get_shader_parameter("boulder_count")
	assert_eq(
		count, positions.size(),
		"chunk paints must sync the uniform themselves -- a fresh session never builds"
	)
	flow_layer.free()


## THE aliasing regression pin ("the parts of the stream are mirrored and
## connect wrongly"): the toroidal across map must be strictly larger than
## the WIDEST tile span the manager can transiently hold loaded -- during
## a chunk-row transition the old row is still rendered while the new one
## paints, six rows in flight, and a map exactly one loaded-span wide lets
## the new row alias onto the old one and overwrite its across data with
## another reach entirely.
func test_the_across_map_outsizes_any_transient_loaded_span():
	var RiverFlowShader = load("res://src/rendering/river_flow_shader.gd")
	var widest_transient := (2 * EarthChunkManager.LOAD_RADIUS + 2) * EarthChunkManager.CHUNK_SIZE
	assert_gt(RiverFlowShader.FLOW_MAP_TILES, widest_transient)
