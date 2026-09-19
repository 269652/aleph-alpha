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
## The flow overlay's own layer. Without one registered,
## _paint_river_flow_overlay returns immediately -- and that paint is the
## ONLY thing that collects natural river boulders, so a fixture without
## this layer can only ever exercise the dropped-piece path (see the
## natural-boulder tests at the bottom of this file).
var river_flow_layer: TileMapLayer
var manager: EarthChunkManager
var river_tile: Vector2i


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	river_flow_layer = TileMapLayer.new()
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager.set_river_flow_layer(river_flow_layer)

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
	river_flow_layer.free()


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


# -- the crest/impoundment walk must use the MEMOIZED river lookup ----------
#
# Reported live: the game dropped to ~6fps standing at/near the spawn point
# (this fixture's own river_tile) -- every player physics tick calls
# river_depth_meters_at_global, which (once a boulder or dam is anywhere
# nearby) walks _impounded_depth_at's crest check up to
# DamImpoundment.MAX_BACKWATER_TILES * 2 + 1 times, and EACH of those calls
# used to reach straight into generator.river_catalog().nearest_river_at
# directly -- the raw, ~44-segment-test lookup RiverCatalog's OWN doc
# comment says is exactly why generator.nearest_river_at's memoized wrapper
# (see EarthChunkGenerator) exists in the first place. Every OTHER hot path
# in earth_chunk_manager.gd already goes through that wrapper; the crest
# walk was the one place that didn't, so it paid the ~44-segment cost fresh
# on every physics tick, 60 times a second, for as long as a player stood
# in or near water -- which the spawn point always does.
#
# Pinned by the one signal that actually tells the two paths apart: only
# the memoized wrapper ever writes into generator's own
# _nearest_river_cache, so a crest/impoundment query that never touches it
# is provably still on the slow path, whatever answer it returns.

func test_crest_check_populates_the_memoized_river_cache():
	manager.generator._nearest_river_cache.clear()
	manager.crest_blocks_at_global(river_tile.x, river_tile.y)
	assert_gt(
		manager.generator._nearest_river_cache.size(), 0,
		"crest_blocks_at_global must resolve rivers through the memoized wrapper, not the raw catalog"
	)


func test_boulder_row_check_populates_the_memoized_river_cache():
	manager.generator._nearest_river_cache.clear()
	manager.boulder_row_blocks_at_global(river_tile.x, river_tile.y)
	assert_gt(
		manager.generator._nearest_river_cache.size(), 0,
		"boulder_row_blocks_at_global must resolve rivers through the memoized wrapper, not the raw catalog"
	)


func test_river_depth_at_a_water_tile_populates_the_memoized_river_cache():
	manager.generator._nearest_river_cache.clear()
	manager.river_depth_meters_at_global(river_tile.x, river_tile.y)
	assert_gt(
		manager.generator._nearest_river_cache.size(), 0,
		"the depth/impoundment walk must resolve rivers through the memoized wrapper, not the raw catalog"
	)


## A second query for the SAME tile must not grow the cache further -- if it
## did, the "memoized" lookup would just be relocating the same uncached
## cost one call downstream rather than actually avoiding it.
func test_a_repeated_crest_check_hits_the_warm_cache():
	manager.crest_blocks_at_global(river_tile.x, river_tile.y)
	var warm_size: int = manager.generator._nearest_river_cache.size()
	manager.crest_blocks_at_global(river_tile.x, river_tile.y)
	assert_eq(
		manager.generator._nearest_river_cache.size(), warm_size,
		"a repeated crest check at the same tile should hit the warm cache, not grow it further"
	)


# -- a NATURAL boulder is a rock of its own size too -------------------------
#
# Reported live: "the boulders in the river doesn't affect hydrology whirls
# and such correctly". Every boulder test above drives the DROPPED piece,
# which reaches the shader through _sync_flow_boulder carrying its real
# diameter. The natural rocks -- the overwhelming majority, and the only
# ones a fresh session has at all -- are collected by the flow-overlay
# PAINT instead, and that path stored a plain `true` in the tile->diameter
# dictionary the feed reads back with `float(...)`. `float(true)` is 1.0, a
# one-CENTIMETRE rock, so boulder_radius_px_for floored every natural
# boulder at MIN_BOULDER_RADIUS_PX however big the rock the player sees.
#
# Radius sizes every single thing the water does around a rock -- the
# shader's own doc comment lists the push reach, the eyot, the shoal, the
# foam and the wake, all scaled from boulder_radius[b] -- so the whole set
# came out identical and minimal. That is exactly "doesn't affect the
# whirls correctly".
#
# These assert over the boulders the paint ACTUALLY collected rather than
# over a tile picked by scanning, because the two sets are not the same
# (see test_..._only_collects_what_it_paints_as_flowing below).

## Tile -> real diameter for every boulder currently in the shader feed.
func _fed_boulders() -> Dictionary:
	manager.sync_river_flow_boulders()
	var positions := manager.river_flow_boulder_positions()
	var radii := manager.river_flow_boulder_radii()
	var fed := {}
	for i in positions.size():
		var tile := Vector2i(
			int((positions[i].x - 8.0) / 16.0), int((positions[i].y - 8.0) / 16.0)
		)
		fed[tile] = {"radius": radii[i], "diameter": manager.flow_boulder_diameter_cm_at_global(tile.x, tile.y)}
	return fed


func test_the_fixture_really_collects_natural_flow_boulders():
	var fed := _fed_boulders()
	assert_gt(fed.size(), 0, "the premise: this river must roll natural boulders")
	var above_floor := 0
	for tile in fed:
		if RiverFlowShader.boulder_radius_px_for(fed[tile]["diameter"]) > RiverFlowShader.MIN_BOULDER_RADIUS_PX:
			above_floor += 1
	assert_gt(
		above_floor, 0,
		"at least one must be big enough that its own radius clears the floor, or this proves nothing"
	)


## The whole bug, stated directly: what the shader is told about a rock has
## to be that rock's own size.
func test_every_natural_boulder_feeds_its_own_radius():
	var fed := _fed_boulders()
	assert_gt(fed.size(), 0, "the premise: this river must roll natural boulders")
	for tile in fed:
		assert_almost_eq(
			fed[tile]["radius"],
			RiverFlowShader.boulder_radius_px_for(fed[tile]["diameter"]),
			1e-6,
			"the rock at %s is %.1fcm across" % [str(tile), fed[tile]["diameter"]]
		)


## The property the player actually sees -- a bigger rock parting more
## water -- and the one a single stored `true` destroys outright, because
## it makes every rock in the river exactly the same size.
func test_natural_boulders_of_different_sizes_feed_different_radii():
	var fed := _fed_boulders()
	var distinct_diameters := {}
	var distinct_radii := {}
	for tile in fed:
		distinct_diameters[snappedf(fed[tile]["diameter"], 0.01)] = true
		distinct_radii[snappedf(fed[tile]["radius"], 0.01)] = true
	if distinct_diameters.size() < 2:
		pending("this river's rocks all rolled one size; nothing to compare")
		return
	assert_gt(
		distinct_radii.size(), 1,
		"%d distinct real sizes reached the shader as %d distinct radii"
			% [distinct_diameters.size(), distinct_radii.size()]
	)


## Once more rocks are in the loaded world than the shader has slots, WHICH
## rocks get one matters: the player sees the water bend around the boulders
## in front of them, not around twenty-four arbitrary rocks somewhere in the
## loaded span. The feed filled its slots in Dictionary insertion order --
## i.e. whichever chunk happened to paint first -- so a cap that binds could
## spend every slot on rocks off screen and leave the ones underfoot doing
## nothing.
##
## Nearest-first is this file's own established answer to a capped
## resource: _budgeted_load_order sorts the pending chunk set "NEAREST
## FIRST and then capped", and SimulationScheduler wakes by distance to
## the player. The centre is the tile update() was last called with -- the
## same one record_water_disturbance already culls wakes against.
func test_the_boulder_feed_keeps_the_nearest_rocks_when_slots_run_out():
	var all_tiles: Array = manager._river_flow_boulder_tiles.keys()
	if all_tiles.size() <= EarthChunkManager.RIVER_FLOW_BOULDER_SLOTS:
		pending("this fixture rolls fewer rocks than slots; nothing is dropped")
		return

	var fed := _fed_boulders()
	assert_eq(fed.size(), EarthChunkManager.RIVER_FLOW_BOULDER_SLOTS, "every slot is used")
	var worst_fed := 0.0
	for tile in fed:
		worst_fed = maxf(worst_fed, Vector2(tile - river_tile).length())
	for tile in all_tiles:
		if fed.has(tile):
			continue
		assert_gte(
			Vector2(tile - river_tile).length(), worst_fed,
			"a rock at %s was dropped while a farther one kept its slot" % str(tile)
		)



# -- a dug pond is water with a real depth -----------------------------------
#
# Reported live: "there's no real pond with river / lake water physics".
# A pond answered is_water_at_global from the day it was dug -- so nothing
# was ever built or grown on one -- but carried no DEPTH, and the player's
# own water state is the maximum of ocean, river and lake depth, three
# sources a pond is not one of. So a fisher's pond was water a player
# walked over on dry feet.

const VillagePond = preload("res://src/gameplay/village_pond.gd")
const WaterMovementModel = preload("res://src/gameplay/water_movement_model.gd")


## A dry tile well away from the fixture's own river, so the depth measured
## is the pond's and nothing else's.
func _dry_tile() -> Vector2i:
	for dx in range(20, 200):
		var tile := river_tile + Vector2i(dx, 0)
		if not manager.is_water_at_global(tile.x, tile.y) and manager.is_chunk_loaded(
			manager._chunk_coord_for_tile(tile)
		):
			return tile
	return Vector2i.MAX


func test_dry_ground_has_no_pond_depth():
	var tile := _dry_tile()
	assert_ne(tile, Vector2i.MAX, "the premise: a dry loaded tile must be findable")
	assert_eq(manager.pond_depth_meters_at_global(tile.x, tile.y), 0.0)


func test_a_dug_pond_is_water_deep_enough_to_swim_in():
	var tile := _dry_tile()
	assert_ne(tile, Vector2i.MAX, "the premise: a dry loaded tile must be findable")
	assert_true(manager.build_at_global(tile.x, tile.y, VillagePond.POND_TILE_ID))

	assert_true(manager.is_water_at_global(tile.x, tile.y), "a dug pond is water")
	assert_almost_eq(
		manager.pond_depth_meters_at_global(tile.x, tile.y), VillagePond.DEPTH_METERS, 1e-6
	)
	assert_gt(
		manager.pond_depth_meters_at_global(tile.x, tile.y),
		WaterMovementModel.WADE_DEPTH_METERS,
		"deep enough that the player swims rather than walks across it"
	)


## The wiring itself: the player's water depth has to ASK for the pond, or
## the depth above never reaches the swim decision. A source-contract check,
## the same shape test_world_perf_report_wiring.gd uses, because standing a
## real Player up headlessly is not worth the fight.
func test_the_players_water_state_asks_for_the_pond_depth():
	var source := FileAccess.get_file_as_string("res://scenes/player.gd")
	var start := source.find("func _resolve_water_state(")
	assert_gt(start, -1, "the premise: _resolve_water_state must still exist")
	var body := source.substr(start, source.find("\nfunc ", start + 1) - start)
	assert_true(
		body.contains("_chunk_manager.pond_depth_meters_at_global(tile.x, tile.y)"),
		"the player's water depth must include a dug pond"
	)
	assert_true(
		body.contains("pond_depth"),
		"and fold it into the water_depth the swim decision is made from"
	)


## Reported live: "it's a procedural entity layn over and not properly dug
## / built pond". The blue a player sees on a pond is the `pond_water`
## MODIFICATION tile and nothing else -- a flat square laid over the grass.
##
## Every other kind of water in this game rides one surface: "ONE WATER
## SURFACE (docs/concept/hydrology.md): rivers, lakes and the sea all ride
## this overlay", which is what gives them a waterline, an ink edge, a
## shore feather and ripples. _paint_river_flow_overlay works that out from
## `generator.hydrology_at_global` and `generator.nearest_river_at` -- and
## the generator is the one thing that cannot know about a dug pond, since
## a pond is a player/village modification. So a pond fell through to the
## "nothing is water here" branch and had its overlay cell ERASED.
func test_a_dug_pond_is_painted_on_the_water_surface():
	# Ground the surface does not paint at all -- past the river's own shore
	# bleed, so the cell really is empty before the pond is dug.
	var tile := Vector2i.MAX
	for dx in range(20, 300):
		var candidate := river_tile + Vector2i(dx, 0)
		if not manager.is_chunk_loaded(manager._chunk_coord_for_tile(candidate)):
			continue
		if manager.is_water_at_global(candidate.x, candidate.y):
			continue
		if river_flow_layer.get_cell_source_id(candidate) == -1:
			tile = candidate
			break
	assert_ne(tile, Vector2i.MAX, "the premise: unpainted dry ground must be findable")
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(tile)

	assert_true(manager.build_at_global(tile.x, tile.y, VillagePond.POND_TILE_ID))
	manager._paint_river_flow_overlay(chunk_coord, manager._loaded_chunks[chunk_coord])

	assert_ne(
		river_flow_layer.get_cell_source_id(tile), -1,
		"a dug pond must be painted by the one water surface, not left to a flat tile"
	)
