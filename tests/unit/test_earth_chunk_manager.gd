extends GutTest

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const AntForagerMarker = preload("res://src/rendering/ant_forager_marker.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const RiverFlowShader = preload("res://src/rendering/river_flow_shader.gd")
const OpenChannelFlow = preload("res://src/world/open_channel_flow.gd")
const ProceduralRiverFlowSprite = preload("res://src/rendering/procedural_river_flow_sprite.gd")
const RiverCatalog = preload("res://src/world/river_catalog.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const SnowTrail = preload("res://src/world/snow_trail.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const FlowerEstablishment = preload("res://src/world/flower_establishment.gd")
const MeadowSpread = preload("res://src/world/meadow_spread.gd")
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
const SeedDispersal = preload("res://src/world/seed_dispersal.gd")
const SquirrelNutCaching = preload("res://src/gameplay/squirrel_nut_caching.gd")
const IllustratedGrassPatch = preload("res://src/rendering/illustrated_grass_patch.gd")
const DecorationLod = preload("res://src/rendering/decoration_lod.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Item = preload("res://src/gameplay/item.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")
const EntityRef = preload("res://src/emergence/entity_ref.gd")
const MemoryRecord = preload("res://src/emergence/memory_record.gd")
const InstitutionFormation = preload("res://src/emergence/institution_formation.gd")
const Event = preload("res://src/emergence/event.gd")
const WorldBossFitness = preload("res://src/gameplay/world_boss_fitness.gd")
const WorldBoss = preload("res://src/emergence/world_boss.gd")
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const FlowerPatch = preload("res://src/world/flower_patch.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const Strata = preload("res://src/world/strata.gd")
const PlayerIdentity = preload("res://src/emergence/player_identity.gd")
const Shop = preload("res://src/gameplay/shop.gd")
const BuildingStatics = preload("res://src/gameplay/building_statics.gd")
const Chunk = preload("res://src/world/chunk.gd")
const LeafLitterField = preload("res://src/world/leaf_litter_field.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var manager: EarthChunkManager
var tree_placement := TreePlacement.new()
var geo_coordinates := GeoCoordinates.new()

# Berlin -- same spawn point world.gd uses; reliably inland (non-ocean,
# non-mountain), so the surrounding loaded chunks are guaranteed to sustain
# some vegetation/population rather than depending on an arbitrary tile that
# might land in open ocean.
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


func after_each():
	tile_map_layer.free()
	entities_parent.free()
	creatures_parent.free()


# -- why this file is slow, and how to iterate on it quickly -----------------
#
# This is the largest test file in the project (492 tests, `grep -c '^func
# test_'`). EarthChunkManager.update() is a genuinely expensive real
# operation -- it synchronously generates the whole LOAD_RADIUS of chunks
# (see update_with_progress's own doc comment, which already measures a full
# load at "~39-90s+ per call"; measured directly at ~101s/call in a headless
# GUT run of this file, 2026-09-03). There is no before_all/after_all in
# this file, only before_each/after_each, so every test below that needs
# loaded state calls manager.update(_berlin_tile) itself -- roughly 237 of
# the 492 do, with that exact same tile. A complete pass of just this one
# file can therefore run for hours; this is inherent to the real generation
# algorithm, not a bug to fix before merging (see CONTRIBUTING.md's test
# section for the same note).
#
# When iterating, scope to one test rather than waiting on the whole file:
#   <godot> --headless -s addons/gut/gut_cmdln.gd -gconfig= \
#     -gtest=res://tests/unit/test_earth_chunk_manager.gd \
#     -gunit_test_name=<substring_of_the_test_name> -gexit


## Reported directly after playtesting: rivers were "still treated like
## normal biome... grass and trees grow in rivers" -- the exact "trees
## standing in a lake" bug class _can_root_at's own doc comment already
## names (from when seed-spread first started travelling far enough to
## matter), now recurring for rivers because a river's own biome is
## untouched land (docs/concept/rivers.md's Rendering section) and
## TreeRooting.can_root_in alone can't see it. Berlin sits on the Spree's
## own curated course, so this is a real, not hypothetical, river cell.
func test_a_seed_spread_sapling_cannot_root_in_a_real_river_cell():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if not manager.is_river_at_global(global_x, global_y):
					continue
				var chunk: Chunk = manager._loaded_chunks[chunk_coord]
				var position := (Vector2(global_x, global_y) + Vector2(0.5, 0.5)) * TerrainRenderer.TILE_SIZE
				assert_false(
					manager._can_root_at(chunk, chunk_coord, position),
					"(%d, %d) is a real river cell -- a sapling must not root there" % [global_x, global_y]
				)
				return  # one real, confirmed river cell is enough to pin the fix
	fail_test("expected at least one real river cell near Berlin (the Spree)")


## Reported from a screenshot: near a river, the snow/water boundary showed
## a jagged staircase instead of the river's own smoothly curved bank. Root
## cause was THIS exclusion -- a whole tile lost its snow presence cell
## whenever Chunk.blocks_ground_cover (river OR lake) was true, at the
## coarse, binary, RIVER_HALF_WIDTH_TILES-distance granularity a tile is
## flagged "river" at, while the river's own visible edge is a smooth,
## continuous, sub-tile curve (see river_flow_shader.gd's |across|==1
## feathered edge). Those two boundaries don't coincide except by
## accident, and the mismatch is what reads as a staircase along any
## curved or diagonal reach.
##
## Unlike grass/trees (which draw as a LATER sibling than RiverFlowFx, so
## nothing else would hide one standing in the river -- see tall_grass.gd/
## tree_renderer.gd's own river exclusions), SnowFx is an EARLIER sibling
## (test_world_ground_layer_order.gd), so the river overlay already draws
## on top of it every frame -- a river/lake tile can safely keep its snow
## presence cell. See docs/concept/snow_cover.md#snow-under-a-river-reads-
## as-a-staircase. Berlin sits on the Spree's own curated course, so this
## is a real, not hypothetical, river cell.
func test_snow_covers_a_real_river_cell_so_the_overlay_can_hide_it_seamlessly():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)
	manager.set_snow_depth(1.0)  # fully covered -- the strongest case

	var found_a_river_cell := false
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if not manager.is_river_at_global(global_x, global_y):
					continue
				found_a_river_cell = true
				assert_true(
					snow_layer.get_used_cells().has(Vector2i(global_x, global_y)),
					(
						"river cell (%d, %d) should still get a snow presence cell -- " +
						"the river overlay hides it, an exclusion should not"
					) % [global_x, global_y]
				)
	assert_true(found_a_river_cell, "expected at least one real river cell near Berlin (the Spree)")
	snow_layer.free()


## Pure passthrough, same shape as gradient_at_global -- needs no loaded
## chunk at all, so this is cheap (see docs/concept/rivers.md).
func test_is_river_at_global_delegates_to_the_generator():
	assert_eq(
		manager.is_river_at_global(_berlin_tile.x, _berlin_tile.y),
		manager.generator.is_river_at_global(_berlin_tile.x, _berlin_tile.y)
	)


## The GPU water overlay (see WaterShader): every loaded ocean OR river cell
## gets a marker cell on the dedicated water layer (which carries the
## animated water material); unloading erases them again. Berlin itself is
## one of the Spree's own curated waypoints (docs/concept/rivers.md), so
## this region is guaranteed to exercise both the ocean and the river path,
## not just ocean.
## Ocean ONLY -- rivers used to be painted here too, and that translucent
## per-tile overlay is exactly what kept square water tiles visible under
## the flow layer's smooth bank curve. The flow overlay is now the river's
## entire water surface.
func test_water_overlay_marks_exactly_the_loaded_ocean_cells_and_no_river():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	var ocean_cells := 0
	var river_cells := 0
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if manager.is_river_at_global(global_x, global_y):
					river_cells += 1
				if manager.biome_at_global(global_x, global_y) == "ocean":
					ocean_cells += 1
	assert_eq(water_layer.get_used_cells().size(), ocean_cells)
	assert_gt(river_cells, 0, "Berlin sits on the Spree's own curated course -- expected at least one river cell here")
	assert_true(water_layer.material is ShaderMaterial, "water layer should carry the animated water material")

	# Moving far away unloads the original chunks -- their overlay cells go too.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	for cell in water_layer.get_used_cells():
		var still_loaded_chunk := _chunk_coord_for_tile(cell)
		var new_center := _chunk_coord_for_tile(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
		var delta := (still_loaded_chunk - new_center).abs()
		assert_true(
			maxi(delta.x, delta.y) <= EarthChunkManager.LOAD_RADIUS,
			"overlay cells outside the loaded radius must be erased on unload"
		)
	water_layer.free()


## Each ocean cell's overlay tile matches its OWN land-direction mask (the
## GPU shore-distance data), not one flat marker for every cell -- a cell
## touching land directly must get a visibly different overlay tile than one
## that doesn't. (Whether this specific test region also has a cell a full
## RING_MAX tiles from any shore is a geographic accident of Berlin's actual
## lake sizes, not something this test should depend on -- see the dedicated
## ring-distance test below for multi-tile variation instead.)
func test_water_overlay_marks_shore_cells_differently_from_non_touching_cells():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	var terrain_renderer := TerrainRenderer.new()
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var found_touching := false
	var found_non_touching := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if manager.biome_at_global(global_x, global_y) != "ocean":
					continue
				var cell := Vector2i(global_x, global_y)
				var coords := water_layer.get_cell_atlas_coords(cell)
				# Ring-0 direction-mask tiles occupy atlas columns 1..
				# DIRECTION_MASK_COUNT (see atlas_coords_for_water_overlay);
				# column 0 is "not touching land directly" (open water or a
				# ring tile), columns beyond DIRECTION_MASK_COUNT are rings.
				var is_touching := coords.y == 0 and coords.x >= 1 and coords.x <= TerrainRenderer.DIRECTION_MASK_COUNT
				if is_touching:
					found_touching = true
				else:
					found_non_touching = true
	assert_true(found_touching, "expected at least one shore overlay cell (ocean bordering land) in this test region")
	assert_true(found_non_touching, "expected at least one overlay cell not directly touching land in this test region")
	water_layer.free()


## Shore influence now extends several tiles into open water (see
## TerrainRenderer.RING_MAX), not just the single tile touching land -- gives
## the water shader's wave-interference band room to actually be visible.
## Real Earth data around the fixed Berlin test region should have at least
## one water body wide enough to have cells a couple of tiles from shore.
func test_water_overlay_uses_ring_tiles_for_cells_a_few_tiles_from_shore():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	var terrain_renderer := TerrainRenderer.new()
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var found_ring := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if manager.biome_at_global(global_x, global_y) != "ocean":
					continue
				var coords := water_layer.get_cell_atlas_coords(Vector2i(global_x, global_y))
				for ring in range(1, TerrainRenderer.RING_MAX):
					if coords == terrain_renderer.atlas_coords_for_water_overlay([], ring):
						found_ring = true
	assert_true(found_ring, "expected at least one ring-distance overlay cell in this test region")
	water_layer.free()


## Weather-reactive water: set_rain now drives a continuous shader uniform on
## the shared water material instead of repainting any tiles.
func test_set_rain_updates_the_water_materials_rain_intensity_uniform():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	manager.set_rain(true)
	assert_eq((water_layer.material as ShaderMaterial).get_shader_parameter("rain_intensity"), 1.0)

	manager.set_rain(false)
	assert_eq((water_layer.material as ShaderMaterial).get_shader_parameter("rain_intensity"), 0.0)
	water_layer.free()


## Water is no longer wind-driven (see WaterShader's class doc) -- kept as a
## harmless no-op rather than removed so world.gd's existing call site
## doesn't need touching.
func test_set_wind_strength_is_a_harmless_no_op():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)
	manager.set_wind_strength(1.4)  # must not error
	water_layer.free()


# -- hillshade overlay: real slope/aspect shading (see docs/concept/terrain_relief.md) -

func test_set_hillshade_layer_assigns_a_real_tile_set():
	var hillshade_layer := TileMapLayer.new()
	manager.set_hillshade_layer(hillshade_layer)
	assert_not_null(hillshade_layer.tile_set)
	hillshade_layer.free()


func test_set_hillshade_layer_assigns_the_shared_shader_material():
	var hillshade_layer := TileMapLayer.new()
	manager.set_hillshade_layer(hillshade_layer)
	assert_true(hillshade_layer.material is ShaderMaterial)
	hillshade_layer.free()


func test_set_sun_position_updates_the_hillshade_materials_uniforms():
	var hillshade_layer := TileMapLayer.new()
	manager.set_hillshade_layer(hillshade_layer)
	manager.set_sun_position(62.0, 210.0)
	var material := hillshade_layer.material as ShaderMaterial
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), 62.0)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), 210.0)
	hillshade_layer.free()


## Entity relief shading (see EntityHillshadeShader, StoneRenderer's
## mountain-vein sprites) shares the SAME live sun position as the ground
## overlay -- one set_sun_position call must re-shade both, not just the
## ground layer. No layer registration needed here (unlike the ground
## overlay test above): entity shading has no TileMapLayer of its own, only
## the shared material StoneRenderer's vein sprites point their `material`
## at directly.
func test_set_sun_position_also_updates_the_entity_hillshade_materials_uniforms():
	manager.set_sun_position(62.0, 210.0)
	var material := manager._entity_hillshade_shader.shared_material()
	assert_eq(material.get_shader_parameter("sun_elevation_deg"), 62.0)
	assert_eq(material.get_shader_parameter("sun_azimuth_deg"), 210.0)


## set_sun_position is also this manager's only live source of "what is the
## sun doing right now" for a settlement chunk streaming in later (see
## VillageRenderer.spawn_village's own sun_elevation_deg -- night village
## window lighting, docs/concept/housing.md#night-lighting-ambient). Stored
## here rather than re-derived, so a house lit at the moment its chunk loads
## reflects the SAME real elevation this exact call already pushed into the
## hillshade materials above, not a second, separately-computed value.
func test_set_sun_position_stores_the_elevation_for_village_night_lighting():
	manager.set_sun_position(-12.0, 210.0)
	assert_eq(manager._current_sun_elevation_deg, -12.0)


## Same shape as test_water_overlay_marks_exactly_the_loaded_ocean_cells,
## but hillshade is a GENERAL mechanism (docs/concept/terrain_relief.md:
## "not mountain-specific code") -- every loaded cell gets a real tile, not
## just ocean or just mountain ones.
func test_hillshade_overlay_paints_a_real_tile_for_every_loaded_cell():
	var hillshade_layer := TileMapLayer.new()
	manager.set_hillshade_layer(hillshade_layer)
	manager.update(_berlin_tile)

	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var expected_cells := manager.chunks_in_radius(
		center_chunk, EarthChunkManager.LOAD_RADIUS
	).size() * EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE
	assert_eq(hillshade_layer.get_used_cells().size(), expected_cells)

	# Moving far away unloads the original chunks -- their overlay cells go too.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	for cell in hillshade_layer.get_used_cells():
		var still_loaded_chunk := _chunk_coord_for_tile(cell)
		var new_center := _chunk_coord_for_tile(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
		var delta := (still_loaded_chunk - new_center).abs()
		assert_true(
			maxi(delta.x, delta.y) <= EarthChunkManager.LOAD_RADIUS,
			"overlay cells outside the loaded radius must be erased on unload"
		)
	hillshade_layer.free()


# -- river flow overlay (docs/concept/rivers.md) -----------------------------
#
# Rivers previously looked exactly like still ocean water (reported:
# "rivers should flow"). Unlike the water/hillshade overlays above, this
# layer is deliberately SPARSE: only river cells get a tile at all (see
# _paint_river_flow_overlay's own doc comment for why -- it reuses
# is_river_at_global the same way _paint_water_overlay already does, never
# touching chunk.biome). Berlin sits on the Spree's own curated course
# (river_catalog.gd), so this fixture is guaranteed to exercise real river
# cells, not just a hypothetical one.

func test_set_river_flow_layer_assigns_a_real_tile_set():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	assert_not_null(flow_layer.tile_set)
	flow_layer.free()


func test_set_river_flow_layer_assigns_the_shared_shader_material():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	assert_true(flow_layer.material is ShaderMaterial)
	flow_layer.free()


## "a player walking through the stream should cause realistic current
## displacement ... animals should also cause water displacement like the
## player" -- world.gd hands over EVERY candidate (player + creatures) each
## frame; the manager filters to the ones actually standing in river water
## and feeds the survivors to the shared material as an array.
func test_set_river_flow_waders_feeds_positions_and_count():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	var fed := PackedVector2Array([Vector2(320.0, 176.0), Vector2(400.0, 208.0)])
	manager.set_river_flow_waders(fed)
	var material: ShaderMaterial = flow_layer.material
	assert_eq(int(material.get_shader_parameter("wader_count")), 2)
	var positions: PackedVector2Array = material.get_shader_parameter("waders")
	assert_eq(positions[0], Vector2(320.0, 176.0))
	assert_eq(positions[1], Vector2(400.0, 208.0))
	manager.set_river_flow_waders(PackedVector2Array())
	assert_eq(int(material.get_shader_parameter("wader_count")), 0)
	flow_layer.free()


func test_river_wader_positions_keeps_only_candidates_in_river_water():
	manager.update(_berlin_tile)
	var wet_tile := Vector2i.ZERO
	var found := false
	for dy in range(-40, 41):
		if found:
			break
		for dx in range(-40, 41):
			var tile := _berlin_tile + Vector2i(dx, dy)
			if manager.is_river_at_global(tile.x, tile.y):
				wet_tile = tile
				found = true
				break
	assert_true(found, "expected a Spree river tile near Berlin")
	var tile_px := float(TerrainRenderer.TILE_SIZE)
	var wet_pos := (Vector2(wet_tile) + Vector2(0.5, 0.5)) * tile_px
	var dry_tile := _berlin_tile
	while manager.is_river_at_global(dry_tile.x, dry_tile.y):
		dry_tile += Vector2i(1, 1)
	var dry_pos := (Vector2(dry_tile) + Vector2(0.5, 0.5)) * tile_px
	var kept := manager.river_wader_positions([dry_pos, wet_pos, dry_pos])
	assert_eq(kept.size(), 1, "only the in-river candidate may displace the water")
	assert_eq(kept[0], wet_pos)


## The flow texel carries the whole reconstruction frame now -- across,
## the course's downstream unit vector, and the real solved current speed
## -- so the shader interpolates ALL of them bilinearly between tiles and
## no per-tile quantity is left to draw the tile grid.
## "Only around bends and where the water is deeper at the edge": traced
## with a real line-probe to every chunk cell getting a texel written even
## when it is genuinely far from any river -- EarthChunkGenerator.
## nearest_river_at then falls back to whichever curated river is nearest
## ANYWHERE ON THE PLANET, which can be hundreds of tiles away with a
## totally unrelated width, so across_fraction (that distance divided by
## an unrelated river's width) can run into the hundreds. Bilinearly
## blended against a real neighbouring texel a few tiles away, that is an
## unbounded cliff. The write must clamp it, regardless of how the
## extreme value arose.
func test_the_written_across_is_always_bounded():
	manager._write_flow_across_texel(Vector2i(500, 500), 900.0, 45.0, 0.0, 2.0)
	var side := RiverFlowShader.FLOW_MAP_TILES
	var texel: Color = manager._flow_across_image.get_pixel(500 % side, 500 % side)
	assert_almost_eq(texel.r, EarthChunkManager.CLAMP_MAGNITUDE, 1e-6)

	manager._write_flow_across_texel(Vector2i(501, 501), -900.0, 45.0, 0.0, 2.0)
	var negative_texel: Color = manager._flow_across_image.get_pixel(501 % side, 501 % side)
	assert_almost_eq(negative_texel.r, -EarthChunkManager.CLAMP_MAGNITUDE, 1e-6)

	# An ordinary in-channel value must pass through completely unclamped.
	manager._write_flow_across_texel(Vector2i(502, 502), 0.4, 45.0, 1.0, 2.0)
	var ordinary_texel: Color = manager._flow_across_image.get_pixel(502 % side, 502 % side)
	assert_almost_eq(ordinary_texel.r, 0.4, 1e-6)


## The reach's drift speed rides the scale map's G channel, and the shader
## gets that texture twice: once linear (half-width), once NEAREST (drift
## speed), so no interpolation ramp between two reaches can diverge over
## TIME.
func test_the_scale_texel_carries_the_reach_drift_speed_and_the_drift_map_is_bound():
	manager._write_flow_across_texel(Vector2i(503, 503), 0.1, 45.0, 1.0, 2.0, 0.8)
	var side := RiverFlowShader.FLOW_MAP_TILES
	var scale_texel: Color = manager._flow_scale_image.get_pixel(503 % side, 503 % side)
	assert_almost_eq(scale_texel.r, 2.0, 1e-6, "R stays the half-width")
	assert_almost_eq(scale_texel.g, 0.8, 1e-6, "G carries the reach's drift speed")
	manager._push_flow_across_map()
	var material := manager._river_flow_shader.shared_material()
	assert_true(
		material.get_shader_parameter("flow_drift_map") == material.get_shader_parameter("flow_scale_map"),
		"the drift map is the scale texture bound a second time"
	)


func test_the_flow_texel_carries_direction_and_speed():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	manager.update(_berlin_tile)
	var painted := flow_layer.get_used_cells()
	assert_gt(painted.size(), 0)
	# Probe a genuinely WET cell: painted apron cells past the half-width
	# solve zero hydraulic speed (banks are slower -- the bilinear blend
	# toward them is physically right), so the speed claim needs a cell
	# inside the channel.
	var cell := Vector2i.ZERO
	var nearest := {}
	var found_wet := false
	for candidate in painted:
		var candidate_nearest := manager.generator.river_catalog().nearest_river_at(
			candidate.x, candidate.y,
			EarthChunkGenerator.WORLD_WIDTH_TILES, EarthChunkGenerator.WORLD_HEIGHT_TILES
		)
		if candidate_nearest.distance_tiles <= RiverCatalog.RIVER_HALF_WIDTH_TILES:
			cell = candidate
			nearest = candidate_nearest
			found_wet = true
			break
	assert_true(found_wet, "expected at least one wet channel cell among the painted set")
	var side := RiverFlowShader.FLOW_MAP_TILES
	var texel: Color = manager._flow_across_image.get_pixel(
		posmod(cell.x, side), posmod(cell.y, side)
	)
	var radians := deg_to_rad(nearest.course_bearing_deg)
	assert_almost_eq(texel.g, sin(radians), 0.001, "G must carry the downstream x")
	assert_almost_eq(texel.b, -cos(radians), 0.001, "B must carry the downstream y")
	assert_gt(texel.a, 0.0, "A must carry the real current speed in m/s")

	# The real local half-width lives on its OWN scalar map, never packed
	# into GB's magnitude: bilinear filtering blends a vector by ordinary
	# addition, and two texels whose bearings differ (exactly what
	# neighbouring texels do on a bend) partially cancel when summed,
	# collapsing a magnitude riding that vector toward zero regardless of
	# either texel's real width -- reported live as "this huge zigzag
	# still persists" once width first rode the direction vector.
	var scale_texel: Color = manager._flow_scale_image.get_pixel(
		posmod(cell.x, side), posmod(cell.y, side)
	)
	assert_almost_eq(scale_texel.r, RiverCatalog.RIVER_HALF_WIDTH_TILES, 0.001, "the scale map must carry the real local half-width")
	flow_layer.free()


func test_river_flow_overlay_paints_only_channel_and_apron_cells():
	var flow_layer := TileMapLayer.new()
	manager.set_river_flow_layer(flow_layer)
	manager.update(_berlin_tile)

	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var total_loaded_cells := manager.chunks_in_radius(
		center_chunk, EarthChunkManager.LOAD_RADIUS
	).size() * EarthChunkManager.CHUNK_SIZE * EarthChunkManager.CHUNK_SIZE

	var painted_cells := flow_layer.get_used_cells()
	assert_gt(painted_cells.size(), 0, "expected at least one real river cell near Berlin (the Spree)")
	assert_lt(painted_cells.size(), total_loaded_cells, "flow must not paint every loaded cell -- it is sparse, not general like hillshade")

	var terrain_renderer := TerrainRenderer.new()
	var apron := RiverCatalog.RIVER_HALF_WIDTH_TILES + RiverCatalog.RIVER_BANK_APRON_TILES
	# Painted out past the bank line by the apron, and past THAT again by
	# SHORE_BLEED_TILES -- a wader's wake or a boulder's shore band reaching
	# just past the apron needs a real tile to draw its fade on, or it
	# cuts off mid-stride ("the bulge when a player walks out is not
	# clipped"). Nothing farther than the bleed may be painted.
	#
	# Measured against the generator's UNIFIED hit and that channel's OWN
	# half width, not the curated catalog's fixed RIVER_HALF_WIDTH_TILES.
	# The painter serves baked channels too, and a baked channel's width
	# comes from its own discharge, so it is routinely wider than the
	# curated constant: a real tile 5.80 from a baked channel of half
	# width 2.11 (reach 5.86) was failing against a bound of 5.75 built
	# from the curated 2.0, while the curated catalog put the nearest
	# river 32.40 tiles away and made the message say so.
	for cell in painted_cells:
		var nearest := manager.generator.nearest_river_at(cell.x, cell.y)
		var paint_reach: float = (
			float(nearest.get("half_width_tiles", RiverCatalog.RIVER_HALF_WIDTH_TILES))
			+ RiverCatalog.RIVER_BANK_APRON_TILES
			+ RiverFlowShader.SHORE_BLEED_TILES
		)
		assert_lte(
			nearest.distance_tiles, paint_reach,
			"(%d, %d) painted but %f tiles from a channel of half width %f (reach %f)" % [
				cell.x, cell.y, nearest.distance_tiles,
				nearest.get("half_width_tiles", -1.0), paint_reach
			]
		)
		# Every painted tile must carry that cell's OWN real data --
		# direction from the course's downstream tangent (water follows its
		# CHANNEL, not the local hillside), the signed across-offset the
		# per-fragment reconstruction runs on, and the fast flag from the
		# real solved current. Recomputed independently here and compared
		# against what was painted.
		var hydraulics := manager.generator.river_hydraulics_at_global(cell.x, cell.y)
		assert_eq(
			flow_layer.get_cell_atlas_coords(cell),
			terrain_renderer.atlas_coords_for_river_flow(
				nearest.course_bearing_deg,
				RiverFlowShader.is_fast_flow(hydraulics.velocity_m_s)
			),
			"(%d, %d) flow tile must reflect its own real flow data" % [cell.x, cell.y]
		)

	# And the apron genuinely extends the paint past the strict channel:
	# somewhere near Berlin there must be a painted cell whose centre sits
	# beyond the half-width -- that is where the smooth waterline lives.
	var apron_cells := 0
	var bled_cells := 0
	for cell in painted_cells:
		if not manager.is_river_at_global(cell.x, cell.y):
			apron_cells += 1
		var nearest := manager.generator.nearest_river_at(cell.x, cell.y)
		if nearest.distance_tiles > apron:
			bled_cells += 1
	assert_gt(apron_cells, 0, "no apron cells painted -- the bank curve would clip at tile edges")
	assert_gt(
		bled_cells, 0,
		"no cell past the plain apron was painted -- SHORE_BLEED_TILES must genuinely widen the paint"
	)

	# Moving far away unloads the original chunks -- their overlay cells go too.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	for cell in flow_layer.get_used_cells():
		var still_loaded_chunk := _chunk_coord_for_tile(cell)
		var new_center := _chunk_coord_for_tile(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
		var delta := (still_loaded_chunk - new_center).abs()
		assert_true(
			maxi(delta.x, delta.y) <= EarthChunkManager.LOAD_RADIUS,
			"overlay cells outside the loaded radius must be erased on unload"
		)
	flow_layer.free()


## RULE-9 pin for the hillshade painter's halved elevation sampling: EVERY
## painted cell must still be exactly the atlas coordinate the old
## slope_at_global + aspect_at_global pair produced. The painter now takes
## ONE gradient per tile and derives both readings from it (see
## TerrainRelief.gradient_at) -- four elevation samples per tile instead of
## eight, on what is the largest per-chunk cost in the running game.
##
## Counts mismatches and asserts once rather than asserting 25,600 times:
## the coverage is every loaded cell either way, but GUT's per-assert
## bookkeeping across a full load radius is itself minutes of runtime.
func test_hillshade_tiles_are_exactly_the_slope_and_aspect_atlas_coords():
	var hillshade_layer := TileMapLayer.new()
	manager.set_hillshade_layer(hillshade_layer)
	manager.update(_berlin_tile)

	var renderer := TerrainRenderer.new()
	var mismatches := 0
	var first_mismatch := ""
	for cell in hillshade_layer.get_used_cells():
		var expected := renderer.atlas_coords_for_hillshade(
			manager.slope_at_global(cell.x, cell.y), manager.aspect_at_global(cell.x, cell.y)
		)
		if hillshade_layer.get_cell_atlas_coords(cell) != expected:
			mismatches += 1
			if first_mismatch == "":
				first_mismatch = "%s painted %s, expected %s" % [
					cell, hillshade_layer.get_cell_atlas_coords(cell), expected
				]
	assert_eq(mismatches, 0, "hillshade tiles must be unchanged; first: %s" % first_mismatch)
	assert_gt(hillshade_layer.get_used_cells().size(), 0, "and there must be cells to check")
	hillshade_layer.free()


## The manager-level delegate the painter uses, mirroring slope_at_global /
## aspect_at_global's own always-delegates-to-the-generator shape. Must agree
## exactly with both, since it is the single source they are now derived from.
func test_gradient_at_global_matches_the_generator_and_derives_slope_and_aspect():
	var relief := manager.generator.terrain_relief()
	for tile in [_berlin_tile, _berlin_tile + Vector2i(37, -21), Vector2i(12345, 6789)]:
		var gradient := manager.gradient_at_global(tile.x, tile.y)
		assert_eq(gradient, manager.generator.gradient_at_global(tile.x, tile.y))
		assert_eq(
			relief.slope_degrees_from_gradient(gradient.x, gradient.y),
			manager.slope_at_global(tile.x, tile.y)
		)
		assert_eq(
			relief.aspect_degrees_from_gradient(gradient.x, gradient.y),
			manager.aspect_at_global(tile.x, tile.y)
		)


## set_wind_strength must also drive SWAY -- trees, blooms/scrub/lichen tufts
## (WindSway), and illustrated grass's own ambient wind term -- not just the
## water shimmer, reusing the SAME live WeatherModel.wind_strength_for value
## world.gd already passes in here, rather than a parallel wind concept.
func test_set_wind_strength_also_drives_tree_bloom_and_grass_sway():
	manager.set_wind_strength(1.8)
	assert_eq(
		manager._wind_sway.tuft_material().get_shader_parameter("wind_strength"), 1.8,
		"blooms/scrub/lichen share this tuft material"
	)
	assert_eq(manager._tree_renderer._wind_sway.shared_material().get_shader_parameter("wind_strength"), 1.8)
	assert_eq(manager._illustrated_grass.material().get_shader_parameter("wind_strength"), 1.8)


## set_snow_depth must also reach TreeRenderer, mirroring set_wind_strength's
## own forward-call shape -- so a newly spawned tree picks up the live snow
## depth (see TreeRenderer._texture_for) with no separate wiring.
func test_set_snow_depth_forwards_to_the_tree_renderer():
	manager.set_snow_depth(0.6)
	assert_almost_eq(manager._tree_renderer._snow_coverage, 0.6, 0.0001)


## record_water_disturbance feeds the SAME shared material set_water_layer
## installed on the tile layer -- a fish/player/animal ripple must actually
## show up on the water the player sees, not on some other material.
func test_record_water_disturbance_updates_the_installed_water_materials_uniforms():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	# Disturbances beyond DISTURBANCE_RADIUS_TILES of the update() center are
	# silently culled (see record_water_disturbance) -- anchor near Berlin's
	# own pixel position, not an arbitrary offset from the world origin, or
	# this disturbance never reaches the shader at all.
	var berlin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var disturbance_pos := berlin_pixel + Vector2(12.0, 34.0)
	manager.record_water_disturbance(disturbance_pos)

	var material := water_layer.material as ShaderMaterial
	assert_eq(material.get_shader_parameter("disturbance_count"), 1)
	var positions: PackedVector2Array = material.get_shader_parameter("disturbance_pos")
	assert_eq(positions[0], disturbance_pos)
	water_layer.free()


## step_water_disturbances must age the SAME installed material's
## disturbances -- world.gd calls this every frame precisely so a recorded
## ripple actually expands/fades instead of sitting frozen at age 0.
func test_step_water_disturbances_ages_the_installed_water_materials_ripple():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	# Same DISTURBANCE_RADIUS_TILES culling as the test above -- anchor near
	# Berlin's own pixel position.
	var berlin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.record_water_disturbance(berlin_pixel + Vector2(1.0, 1.0))
	manager.step_water_disturbances(0.5)

	var material := water_layer.material as ShaderMaterial
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_almost_eq(ages[0], 0.5, 0.001)
	water_layer.free()



## ONE buffer, TWO surfaces. The ocean overlay stopped painting river tiles
## (see _paint_water_overlay: "the flow overlay is now the river's entire
## water surface"), so a fish's wake was being recorded and aged into a
## layer that river tiles no longer have -- reported as "fishes don't
## produce interferencing ripples anymore in the new unified river water".
## The same three uniforms must reach the river surface too.
##
## Anchored at the world origin on purpose: _disturbance_center_tile starts
## at Vector2i.ZERO, so this clears DISTURBANCE_RADIUS_TILES without paying
## for an update() the assertion does not need.
func test_a_recorded_disturbance_reaches_the_river_surface_too():
	var river_layer := TileMapLayer.new()
	manager.set_river_flow_layer(river_layer)

	var disturbance_pos := Vector2(6.0, 9.0)
	manager.record_water_disturbance(disturbance_pos)

	var material := river_layer.material as ShaderMaterial
	assert_eq(material.get_shader_parameter("disturbance_count"), 1)
	var positions: PackedVector2Array = material.get_shader_parameter("disturbance_pos")
	assert_eq(positions[0], disturbance_pos)
	river_layer.free()


## And it must AGE there as well, or the river's ring sits frozen at radius
## zero while the ocean's expands -- the same reason step_water_disturbances
## exists for the water layer at all.
func test_step_water_disturbances_ages_the_river_surfaces_ripple_too():
	var river_layer := TileMapLayer.new()
	manager.set_river_flow_layer(river_layer)

	manager.record_water_disturbance(Vector2(1.0, 1.0))
	manager.step_water_disturbances(0.5)

	var material := river_layer.material as ShaderMaterial
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_almost_eq(ages[0], 0.5, 0.001)
	river_layer.free()


## Both surfaces read the SAME buffer -- one lifetime, one cull, one cap.
## A second buffer is a second thing to keep in step, and the two would
## drift apart the moment either side was re-tuned.
func test_both_surfaces_show_the_very_same_disturbance_buffer():
	var water_layer := TileMapLayer.new()
	var river_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.set_river_flow_layer(river_layer)

	manager.record_water_disturbance(Vector2(3.0, 4.0))
	manager.record_water_disturbance(Vector2(5.0, 6.0))
	manager.step_water_disturbances(0.25)

	var water_material := water_layer.material as ShaderMaterial
	var river_material := river_layer.material as ShaderMaterial
	assert_eq(
		river_material.get_shader_parameter("disturbance_count"),
		water_material.get_shader_parameter("disturbance_count")
	)
	assert_eq(
		river_material.get_shader_parameter("disturbance_pos"),
		water_material.get_shader_parameter("disturbance_pos")
	)
	assert_eq(
		river_material.get_shader_parameter("disturbance_age"),
		water_material.get_shader_parameter("disturbance_age")
	)
	water_layer.free()
	river_layer.free()

# -- fish: visible, catchable entities on ocean cells (see FishRenderer) -----

const FishMarker = preload("res://src/rendering/fish_marker.gd")


func _loaded_fish_markers() -> Array:
	var markers := []
	for child in creatures_parent.get_children():
		if child is FishMarker:
			markers.append(child)
	return markers


func test_update_spawns_fish_markers_near_berlins_water():
	manager.update(_berlin_tile)
	assert_gt(_loaded_fish_markers().size(), 0)


func test_evicting_old_chunks_frees_their_fish_markers():
	manager.update(_berlin_tile)
	var fish_near_berlin := _loaded_fish_markers()
	assert_gt(fish_near_berlin.size(), 0)

	# Moving far away can spawn its own new fish (unrelated ocean cells) --
	# what matters is that BERLIN's own markers specifically got freed, not
	# that the fish count happens to hit zero globally.
	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)
	for fish in fish_near_berlin:
		assert_false(is_instance_valid(fish), "Berlin's fish markers should be freed once out of range")


func test_catch_nearest_fish_removes_it_and_returns_its_species():
	manager.update(_berlin_tile)
	var fish: Array = _loaded_fish_markers()
	assert_gt(fish.size(), 0)
	var target = fish[0]
	var target_position: Vector2 = target.position

	var species := manager.catch_nearest_fish(target_position, 1.0)
	assert_ne(species, "")
	assert_false(is_instance_valid(target), "the caught fish should be freed")


func test_catch_nearest_fish_returns_empty_string_when_none_in_range():
	manager.update(_berlin_tile)
	var far_from_everything := Vector2(-999999.0, -999999.0)
	assert_eq(manager.catch_nearest_fish(far_from_everything, 5.0), "")


# -- ambient flyers: decorative butterflies/songbirds (see AmbientFlyerRenderer) --

const AmbientFlyerMarker = preload("res://src/rendering/ambient_flyer_marker.gd")


func _loaded_ambient_flyer_markers() -> Array:
	var markers := []
	for child in creatures_parent.get_children():
		if child is AmbientFlyerMarker:
			markers.append(child)
	return markers


func test_update_spawns_ambient_flyers_near_berlin():
	manager.update(_berlin_tile)
	assert_gt(_loaded_ambient_flyer_markers().size(), 0)


func test_evicting_old_chunks_frees_their_ambient_flyers():
	manager.update(_berlin_tile)
	var flyers_near_berlin := _loaded_ambient_flyer_markers()
	assert_gt(flyers_near_berlin.size(), 0)

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	for flyer in flyers_near_berlin:
		assert_false(is_instance_valid(flyer), "Berlin's ambient flyers should be freed once out of range")


# -- piscivore birds: kingfishers dive for fish (see PiscivoreBirdRenderer,
# PiscivoreBirdMarker) and actually decrement the aquatic population --------

const PiscivoreBirdMarker = preload("res://src/rendering/piscivore_bird_marker.gd")


func _loaded_piscivore_bird_markers() -> Array:
	var markers := []
	for child in creatures_parent.get_children():
		if child is PiscivoreBirdMarker:
			markers.append(child)
	return markers


func test_fish_population_near_matches_fish_population_at_chunk():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_almost_eq(
		manager.fish_population_near(pixel), manager.fish_population_at_chunk(center_chunk), 0.001
	)


func test_record_fish_catch_near_decrements_the_right_chunk():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	var before := manager.fish_population_near(pixel)
	manager.record_fish_catch_near(pixel, 1.0)
	assert_almost_eq(manager.fish_population_near(pixel), maxf(0.0, before - 1.0), 0.001)


func test_update_may_spawn_a_kingfisher_near_berlins_water():
	manager.update(_berlin_tile)
	assert_gt(_loaded_piscivore_bird_markers().size(), 0)


func test_evicting_old_chunks_frees_their_kingfishers():
	manager.update(_berlin_tile)
	var birds_near_berlin := _loaded_piscivore_bird_markers()
	assert_gt(birds_near_berlin.size(), 0)

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	for bird in birds_near_berlin:
		assert_false(is_instance_valid(bird), "Berlin's kingfishers should be freed once out of range")


## See docs/concept/fishing.md#aquatic-population-model.

func test_update_seeds_fish_population_for_loaded_water_regions_around_berlin():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var found_water_chunk := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		if manager.fish_population_at_chunk(chunk_coord) > 0.0:
			found_water_chunk = true
	assert_true(
		found_water_chunk,
		"expected at least one loaded chunk near Berlin to have a seeded fish population"
	)


## Fishes out EVERY loaded water chunk (not just one) so there's no
## untouched neighbor left to migrate fish back in from -- migration
## restocking a single fished-out chunk from an adjacent healthy one is
## correct, intended behavior (see docs/concept/fishing.md's "gradually
## restocks from adjacent untouched water"), not something this test should
## fight; a region with nothing left anywhere nearby is the real zero case.
func test_step_ecosystem_shows_no_fish_markers_once_the_whole_loaded_region_is_fished_out():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var any_water := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		var population := manager.fish_population_at_chunk(chunk_coord)
		if population > 0.0:
			any_water = true
			manager._ecosystem.record_catch(chunk_coord, population)
	assert_true(any_water, "precondition: some loaded chunk near Berlin has fish")

	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY)

	assert_eq(
		_loaded_fish_markers().size(), 0,
		"an entirely fished-out region should show no fish markers after the next ecosystem refresh"
	)


func test_catch_nearest_fish_decrements_the_chunks_aggregate_fish_population():
	manager.update(_berlin_tile)
	var fish: Array = _loaded_fish_markers()
	assert_gt(fish.size(), 0)
	var target = fish[0]
	var target_position: Vector2 = target.position
	var target_tile := Vector2i(
		floori(target_position.x / TerrainRenderer.TILE_SIZE),
		floori(target_position.y / TerrainRenderer.TILE_SIZE)
	)
	var target_chunk := _chunk_coord_for_tile(target_tile)
	var before := manager.fish_population_at_chunk(target_chunk)

	manager.catch_nearest_fish(target_position, 1.0)

	assert_lt(manager.fish_population_at_chunk(target_chunk), before)


## A real app restart has no in-memory _unloaded_ecology at all -- only disk
## persistence survives it. Rather than actually constructing a second
## EarthChunkManager (which re-triggers a harmless-but-noisy engine resource
## warning mid-test that GUT's error capture misattributes as a failure of
## THIS test, since it fires outside before_each), this drops the in-session
## catch-up record directly -- the exact condition `_load_chunk`'s
## `had_in_session_catchup` check is testing for -- so the same disk-read
## branch is exercised precisely, with the same manager instance.
func test_fish_population_survives_being_forgotten_from_in_session_memory():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var target_chunk := Vector2i.ZERO
	var found := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		if manager.fish_population_at_chunk(chunk_coord) > 0.0:
			target_chunk = chunk_coord
			found = true
			break
	assert_true(found, "precondition: some loaded chunk near Berlin has fish")

	manager._ecosystem.record_catch(target_chunk, manager.fish_population_at_chunk(target_chunk))
	assert_eq(manager.fish_population_at_chunk(target_chunk), 0.0)

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)  # evicts Berlin's chunks, writing fish population to disk
	manager._unloaded_ecology.erase(target_chunk)  # simulate a fresh session's empty memory

	manager.update(_berlin_tile)  # reload

	assert_eq(manager.fish_population_at_chunk(target_chunk), 0.0)

	var path := "user://chunk_fish_population/%d_%d.bin" % [target_chunk.x, target_chunk.y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# -- set_attraction_point / clear_attraction_point (see Player._fishing_step) --

func test_set_attraction_point_attracts_fish_within_radius():
	manager.update(_berlin_tile)
	var fish: Array = _loaded_fish_markers()
	assert_gt(fish.size(), 0)
	var target: FishMarker = fish[0]
	var bobber_position: Vector2 = target.position

	manager.set_attraction_point(bobber_position, 5.0)

	assert_eq(target.attract_target, bobber_position)


func test_set_attraction_point_leaves_fish_outside_radius_unattracted():
	manager.update(_berlin_tile)
	var fish: Array = _loaded_fish_markers()
	assert_gt(fish.size(), 0)
	var target: FishMarker = fish[0]

	manager.set_attraction_point(Vector2(-999999.0, -999999.0), 5.0)

	assert_null(target.attract_target)


func test_clear_attraction_point_releases_every_fish():
	manager.update(_berlin_tile)
	var fish: Array = _loaded_fish_markers()
	assert_gt(fish.size(), 0)
	manager.set_attraction_point(fish[0].position, 100000.0)
	assert_not_null(fish[0].attract_target)

	manager.clear_attraction_point()

	for f in fish:
		assert_null(f.attract_target)


# -- has_merchant_near (see VillageRenderer, Shop) ----------------------------
#
# Real settlements are sparse (~1-in-30 habitable chunks, see
# SettlementGenerator) -- Berlin's loaded chunks aren't guaranteed to have
# one, so this injects a fake merchant marker directly (same technique as the
# fishing-catch tests above) instead of depending on that roll landing.

const NpcMarker = preload("res://src/rendering/npc_marker.gd")
const NpcIdentity = preload("res://src/world/npc_identity.gd")
const OccupationProduction = preload("res://src/emergence/occupation_production.gd")
const SettlementState = preload("res://src/emergence/settlement_state.gd")
const SettlementGranary = preload("res://src/emergence/settlement_granary.gd")
const NpcProduction = preload("res://src/world/npc_production.gd")


func _add_fake_merchant(position: Vector2) -> NpcMarker:
	var merchant := NpcMarker.new()
	merchant.identity = NpcIdentity.new(1)
	merchant.identity.occupation = "merchant"
	merchant.position = position
	creatures_parent.add_child(merchant)
	manager._loaded_villages[Vector2i(0, 0)] = [merchant]
	return merchant


func test_has_merchant_near_true_when_a_merchant_is_within_range():
	manager.update(_berlin_tile)
	var merchant := _add_fake_merchant(Vector2(100, 100))
	assert_true(manager.has_merchant_near(Vector2(105, 100), 10.0))
	merchant.free()


func test_has_merchant_near_false_when_out_of_range():
	manager.update(_berlin_tile)
	var merchant := _add_fake_merchant(Vector2(100, 100))
	assert_false(manager.has_merchant_near(Vector2(500, 500), 10.0))
	merchant.free()


## Before any chunk is even loaded, _loaded_villages is genuinely empty --
## unlike a real loaded region, which has some (small, non-zero) chance of
## containing an actual settlement/merchant, this can't flake.
func test_has_merchant_near_false_when_no_settlement_loaded():
	assert_false(manager.has_merchant_near(Vector2(100, 100), 10000.0))


# -- nearest_npc_near (see Player._talk_step, the "Talk (key)" prompt) -------
#
# Same shape as has_merchant_near, but for ANY villager (not just merchants)
# and returning the marker itself -- the talk prompt/greeting needs the
# NPC's identity, not just a yes/no.

func _add_fake_npc(position: Vector2, seed_value: int = 1) -> NpcMarker:
	var npc := NpcMarker.new()
	npc.identity = NpcIdentity.new(seed_value)
	npc.position = position
	creatures_parent.add_child(npc)
	manager._loaded_villages[Vector2i(0, 0)] = [npc]
	return npc


func test_nearest_npc_near_returns_the_npc_within_range():
	manager.update(_berlin_tile)
	var npc := _add_fake_npc(Vector2(100, 100))
	assert_eq(manager.nearest_npc_near(Vector2(105, 100), 10.0), npc)
	npc.free()


func test_nearest_npc_near_returns_null_when_out_of_range():
	manager.update(_berlin_tile)
	var npc := _add_fake_npc(Vector2(100, 100))
	assert_null(manager.nearest_npc_near(Vector2(500, 500), 10.0))
	npc.free()


func test_nearest_npc_near_returns_null_when_no_settlement_loaded():
	assert_null(manager.nearest_npc_near(Vector2(100, 100), 10000.0))


func test_nearest_npc_near_picks_the_closer_of_two_candidates():
	manager.update(_berlin_tile)
	var near := _add_fake_npc(Vector2(100, 100), 1)
	var far := _add_fake_npc(Vector2(300, 300), 2)
	manager._loaded_villages[Vector2i(0, 0)] = [far, near]
	assert_eq(manager.nearest_npc_near(Vector2(100, 100), 10000.0), near)
	near.free()
	far.free()


# -- nearest_liftable_stone_near / liftable_stones_near (see PebbleDispersion,
# World._update_interaction_prompt's "Pick (key)" prompt) -------------------
#
# Same shape as nearest_npc_near, scanning _loaded_stones instead of
# _loaded_villages. Only something the player could actually press the
# pickup key to collect qualifies -- a boulder (StaticBody2D, no pick_up)
# never does.

func _add_fake_liftable_stone(position: Vector2) -> LiftableStone:
	var stone := LiftableStone.new()
	stone.position = position
	entities_parent.add_child(stone)
	manager._loaded_stones[Vector2i(0, 0)] = [stone]
	return stone


func test_nearest_liftable_stone_near_returns_the_stone_within_range():
	var stone := _add_fake_liftable_stone(Vector2(100, 100))
	assert_eq(manager.nearest_liftable_stone_near(Vector2(105, 100), 10.0), stone)
	stone.free()


func test_nearest_liftable_stone_near_returns_null_when_out_of_range():
	var stone := _add_fake_liftable_stone(Vector2(100, 100))
	assert_null(manager.nearest_liftable_stone_near(Vector2(500, 500), 10.0))
	stone.free()


func test_nearest_liftable_stone_near_returns_null_when_nothing_loaded():
	assert_null(manager.nearest_liftable_stone_near(Vector2(100, 100), 10000.0))


func test_nearest_liftable_stone_near_ignores_boulders():
	var boulder := SmashableStone.new()
	boulder.position = Vector2(100, 100)
	entities_parent.add_child(boulder)
	manager._loaded_stones[Vector2i(0, 0)] = [boulder]
	assert_null(manager.nearest_liftable_stone_near(Vector2(101, 100), 10000.0))
	boulder.free()


func test_nearest_liftable_stone_near_picks_the_closer_of_two_candidates():
	var near := _add_fake_liftable_stone(Vector2(100, 100))
	var far := LiftableStone.new()
	far.position = Vector2(300, 300)
	entities_parent.add_child(far)
	manager._loaded_stones[Vector2i(0, 0)] = [far, near]
	assert_eq(manager.nearest_liftable_stone_near(Vector2(100, 100), 10000.0), near)
	near.free()
	far.free()


## Dispersion (see PebbleDispersion) needs every nearby member checked, not
## just the closest one -- a flock can have several members near a walker at
## once.
func test_liftable_stones_near_returns_every_qualifying_stone_within_range():
	var a := LiftableStone.new()
	a.position = Vector2(100, 100)
	var b := LiftableStone.new()
	b.position = Vector2(103, 100)
	var boulder := SmashableStone.new()
	boulder.position = Vector2(101, 100)
	var far := LiftableStone.new()
	far.position = Vector2(500, 500)
	for node in [a, b, boulder, far]:
		entities_parent.add_child(node)
	manager._loaded_stones[Vector2i(0, 0)] = [a, b, boulder, far]

	var found := manager.liftable_stones_near(Vector2(100, 100), 10.0)
	assert_eq(found.size(), 2)
	assert_true(found.has(a))
	assert_true(found.has(b))
	for node in [a, b, boulder, far]:
		node.free()


func _expected_tree_count_around(center_chunk: Vector2i) -> int:
	var expected := 0
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				var biome_name := manager.biome_at_global(global_x, global_y)
				if tree_placement.has_tree_at(global_x, global_y, biome_name):
					expected += 1
	return expected


func test_chunks_in_radius_returns_the_square_grid_around_the_center():
	var coords := manager.chunks_in_radius(Vector2i(10, 10), 1)
	assert_eq(coords.size(), 9)
	assert_true(coords.has(Vector2i(10, 10)))
	assert_true(coords.has(Vector2i(9, 9)))
	assert_true(coords.has(Vector2i(11, 11)))
	assert_false(coords.has(Vector2i(12, 10)))


func test_update_loads_the_chunk_containing_the_player():
	manager.update(Vector2i(0, 0))
	assert_true(manager.is_chunk_loaded(Vector2i(0, 0)))


func test_update_does_not_load_chunks_far_from_the_player():
	manager.update(Vector2i(0, 0))
	assert_false(manager.is_chunk_loaded(Vector2i(500, 500)))


func test_moving_far_away_evicts_the_original_chunk():
	manager.update(Vector2i(0, 0))
	assert_true(manager.is_chunk_loaded(Vector2i(0, 0)))

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager.is_chunk_loaded(Vector2i(0, 0)))


# -- steady-state streaming budget (see docs/concept/persistence.md's
# "Loading screens" section). update() has always loaded every pending chunk
# in one uninterrupted synchronous call. That is fine for the COLD load,
# which has update_with_progress and a loading screen -- but World calls
# update() every frame during play, and stepping across one chunk boundary
# makes a whole LOAD_RADIUS column pending at once, all of it generated,
# painted and populated inside that single frame. -------------------------

## The guard for the ~210 existing update() call sites: the default is
## unbudgeted, exactly as update() has always behaved.
func test_update_loads_every_pending_chunk_when_no_budget_is_set():
	var center_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	var expected := manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS).size()
	manager.update(Vector2i(0, 0))
	assert_eq(manager.loaded_chunk_count(), expected)
	assert_eq(manager.max_chunk_loads_per_update, 0, "unbudgeted must stay the default")


func test_update_loads_at_most_the_configured_budget_in_one_call():
	manager.max_chunk_loads_per_update = 1
	manager.update(Vector2i(0, 0))
	assert_eq(manager.loaded_chunk_count(), 1)


## With a budget it matters WHICH chunk gets loaded: chunks_in_radius is
## row-major, so an unordered budgeted loader would start at the far
## top-left corner rather than the ground under the player's feet.
func test_a_budgeted_update_loads_the_nearest_pending_chunk_first():
	manager.max_chunk_loads_per_update = 1
	manager.update(_berlin_tile)
	assert_true(
		manager.is_chunk_loaded(_chunk_coord_for_tile(_berlin_tile)),
		"the chunk the player is standing in must be loaded before any other"
	)


func test_repeated_budgeted_updates_eventually_load_the_whole_radius():
	var center_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	var expected := manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS)
	manager.max_chunk_loads_per_update = 1
	for i in expected.size():
		manager.update(Vector2i(0, 0))
	for chunk_coord in expected:
		assert_true(manager.is_chunk_loaded(chunk_coord))


## RULE-9 for the streaming change: budgeting alters WHEN chunks load and in
## what order, and must not alter WHICH ones end up loaded. Compares a
## budgeted manager driven to completion against an unbudgeted one -- the
## same comparison the game itself relies on, since both end in the same
## steady state.
func test_a_budgeted_manager_ends_with_exactly_the_same_chunks_as_an_unbudgeted_one():
	manager.update(_berlin_tile)
	var unbudgeted := manager.chunks_in_radius(
		_chunk_coord_for_tile(_berlin_tile), EarthChunkManager.LOAD_RADIUS
	)

	var other_layer := TileMapLayer.new()
	var other_entities := Node2D.new()
	var other_creatures := Node2D.new()
	var budgeted := EarthChunkManager.new(other_layer, other_entities, other_creatures)
	budgeted.max_chunk_loads_per_update = 1
	for i in unbudgeted.size():
		budgeted.update(_berlin_tile)

	assert_eq(budgeted.loaded_chunk_count(), manager.loaded_chunk_count())
	for chunk_coord in unbudgeted:
		assert_true(
			budgeted.is_chunk_loaded(chunk_coord),
			"%s must be loaded by the budgeted manager too" % chunk_coord
		)
	other_layer.free()
	other_entities.free()
	other_creatures.free()


## Eviction is not part of the budget: a budgeted update still drops chunks
## the player has left behind, or a slow loader would grow the live set.
func test_a_budgeted_update_still_evicts_beyond_unload_radius():
	manager.update(Vector2i(0, 0))
	assert_true(manager.is_chunk_loaded(Vector2i(0, 0)))

	manager.max_chunk_loads_per_update = 1
	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager.is_chunk_loaded(Vector2i(0, 0)))


## The budget VALUE is a derived, tested number rather than an eyeballed
## one. At the player's real base pace -- Player.BASE_SPEED 80 world units a
## second over TerrainRenderer.TILE_SIZE 16, i.e. 5 tiles a second -- one
## chunk per frame is ample: the newly pending ring is LOAD_RADIUS *
## CHUNK_SIZE = 64 tiles ahead, so even halving that for safety leaves 6.4
## seconds of walking, ~192 frames at 30 fps, to load a worst-case 9 chunks.
func test_chunks_per_update_at_the_players_real_walking_pace_is_one():
	assert_eq(EarthChunkManager.chunks_per_update_for(5.0, 30.0), 1)


## ...and it scales rather than pretending: a player crossing the whole lead
## in a handful of frames needs the whole pending set in one call, which is
## exactly the unbudgeted behaviour.
func test_chunks_per_update_for_an_impossibly_fast_player_is_the_whole_pending_set():
	var worst_case := 2 * (2 * EarthChunkManager.LOAD_RADIUS + 1) - 1
	assert_eq(EarthChunkManager.chunks_per_update_for(10000.0, 30.0), worst_case)
	assert_gt(EarthChunkManager.chunks_per_update_for(200.0, 30.0), 1)


# -- update_with_progress: chunked, frame-yielding update() variant used by
# the initial New Game/Load Game/Join loading-screen flow (see
# World._show_loading_overlay, LoadingOverlay, docs/concept/persistence.md's
# "Loading screens" section) so it can show REAL per-chunk progress instead
# of an indeterminate spinner frozen for the whole synchronous update()
# duration. pending_load_chunks is the plain, cheap (no generation) piece
# that makes the total knowable up front. --------------------------------

func test_pending_load_chunks_lists_every_chunk_update_would_load():
	var center_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	var expected := manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS)
	assert_eq(manager.pending_load_chunks(Vector2i(0, 0)).size(), expected.size())


func test_pending_load_chunks_is_empty_once_update_already_loaded_them():
	manager.update(Vector2i(0, 0))
	assert_eq(manager.pending_load_chunks(Vector2i(0, 0)).size(), 0)


func test_update_with_progress_loads_the_same_chunks_update_would():
	var center_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	var expected := manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS)
	await manager.update_with_progress(Vector2i(0, 0))
	for chunk_coord in expected:
		assert_true(manager.is_chunk_loaded(chunk_coord))


func test_update_with_progress_reports_real_progress_from_zero_to_the_true_total():
	var total := manager.pending_load_chunks(Vector2i(0, 0)).size()
	assert_gt(total, 0, "nothing loaded yet -- there should be chunks pending")
	var calls := []
	var record_progress := func(loaded: int, of_total: int) -> void:
		calls.append([loaded, of_total])
	await manager.update_with_progress(Vector2i(0, 0), record_progress)
	assert_eq(calls[0], [0, total], "first call reports zero of the real total")
	assert_eq(calls[calls.size() - 1], [total, total], "last call reports completion")
	assert_eq(calls.size(), total + 1, "one call per chunk loaded, plus the initial zero")


func test_update_with_progress_still_evicts_chunks_beyond_unload_radius():
	await manager.update_with_progress(Vector2i(0, 0))
	assert_true(manager.is_chunk_loaded(Vector2i(0, 0)))

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	await manager.update_with_progress(far_away_tile)

	assert_false(manager.is_chunk_loaded(Vector2i(0, 0)))


# -- re-entrancy: _load_chunk must tolerate being called twice for the same
# coord without leaking nodes. update()/update_with_progress() both funnel
# every chunk through this one mutation point with no "already loaded" guard
# AT the point of mutation (pending_load_chunks/_budgeted_load_order only
# guard what gets SELECTED, one level up) -- so two concurrent loaders that
# each independently decided a coord was still pending can both go on to
# call _load_chunk on it. This is exactly what happens in
# World._on_peer_connected, which has no re-entrancy guard around its
# `await _compute_dry_land_spawn_tile()` / `update_with_progress()` chain
# (contrast `_initial_client_chunk_load_task_running`, which guards the
# solo-client cold-load path but nothing analogous exists for peer-connect):
# two peers joining within the same multi-frame loading window, or a peer
# joining while the host's own per-frame update() is already mid-load, both
# reach the same spawn-adjacent chunk set concurrently. -------------------

func test_load_chunk_called_twice_for_the_same_coord_does_not_leak_entity_nodes():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	var entities_before := entities_parent.get_child_count()

	# Simulates the race: another in-flight loader reaches the same
	# coordinate before either call has finished.
	manager._load_chunk(chunk_coord)

	assert_eq(
		entities_parent.get_child_count(), entities_before,
		"a second _load_chunk for an already-loaded coord must not spawn a duplicate batch of tree/stone/decoration nodes"
	)


func test_load_chunk_called_twice_for_the_same_coord_does_not_leak_creature_nodes():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	var creatures_before := creatures_parent.get_child_count()

	manager._load_chunk(chunk_coord)

	assert_eq(
		creatures_parent.get_child_count(), creatures_before,
		"a second _load_chunk for an already-loaded coord must not spawn a duplicate batch of creature/fish/village nodes"
	)


func test_load_chunk_called_twice_for_the_same_coord_keeps_the_original_tree_and_stone_records():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	var trees_before: Array = manager._loaded_trees[chunk_coord]
	var stones_before: Array = manager._loaded_stones[chunk_coord]

	manager._load_chunk(chunk_coord)

	assert_eq(
		manager._loaded_trees[chunk_coord], trees_before,
		"a second _load_chunk must not overwrite the tree record with a freshly (and redundantly) spawned batch"
	)
	assert_eq(
		manager._loaded_stones[chunk_coord], stones_before,
		"a second _load_chunk must not overwrite the stone record with a freshly (and redundantly) spawned batch"
	)


func test_elevation_at_global_matches_the_generator_for_a_loaded_tile():
	manager.update(Vector2i(5, 5))
	var expected := manager.generator.elevation_at_global(5, 5)
	assert_almost_eq(manager.elevation_at_global(5, 5), expected, 0.0001)


func test_slope_at_global_matches_the_generator():
	var expected := manager.generator.slope_at_global(5, 5)
	assert_almost_eq(manager.slope_at_global(5, 5), expected, 0.0001)


func test_aspect_at_global_matches_the_generator():
	var expected := manager.generator.aspect_at_global(5, 5)
	assert_almost_eq(manager.aspect_at_global(5, 5), expected, 0.0001)


func test_update_paints_tiles_onto_the_shared_tile_map_layer():
	manager.update(Vector2i(0, 0))
	assert_ne(tile_map_layer.get_cell_source_id(Vector2i(0, 0)), -1)


## Entities parent also carries stones and tall-grass tufts now, so tree
## assertions count ChoppableTree children specifically.
func _spawned_tree_count() -> int:
	var count := 0
	for child in entities_parent.get_children():
		if child is ChoppableTree:
			count += 1
	return count


func test_update_spawns_a_tree_node_for_every_forested_tile_in_loaded_chunks():
	manager.update(Vector2i(0, 0))
	assert_eq(_spawned_tree_count(), _expected_tree_count_around(Vector2i(0, 0)))


func test_evicting_old_chunks_leaves_only_the_new_locations_trees():
	manager.update(Vector2i(0, 0))

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_eq(_spawned_tree_count(), _expected_tree_count_around(Vector2i(500, 500)))


# -- ecosystem: creature promotion --------------------------------------------

func test_update_seeds_a_living_population_for_loaded_regions_around_berlin():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_gt(manager.herbivore_population_at_chunk(center_chunk), 0.0)


## docs/concept/npc.md "Needs and the local production economy": a producer
## NPC's gathered yield reads these SAME real regional numbers rather than an
## invented economy stat -- see NpcProduction. Both mirror
## fish_population_near/fish_capacity_near's exact existing "_near" pattern.

func test_vegetation_density_near_matches_the_chunks_average_density():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_gt(manager.vegetation_density_near(pixel), 0.0)


func test_herbivore_population_near_matches_herbivore_population_at_chunk():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_almost_eq(
		manager.herbivore_population_near(pixel), manager.herbivore_population_at_chunk(center_chunk), 0.001
	)


## docs/concept/disease.md's herd (foot-and-mouth-like) archetype: real
## population vs. real carrying capacity is CreatureMarker's own density
## signal for herd disease transmission pressure (see
## DiseaseModel.herd_transmission_chance) -- mirrors herbivore_population_
## at_chunk/near's exact existing pair-of-accessors pattern.
func test_herbivore_capacity_near_matches_herbivore_capacity_at_chunk():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_gt(manager.herbivore_capacity_at_chunk(center_chunk), 0.0)
	assert_almost_eq(
		manager.herbivore_capacity_near(pixel), manager.herbivore_capacity_at_chunk(center_chunk), 0.001
	)


func test_update_spawns_creature_markers_for_loaded_regions_around_berlin():
	manager.update(_berlin_tile)
	assert_gt(creatures_parent.get_child_count(), 0)


func test_evicting_old_chunks_frees_their_creature_markers():
	manager.update(_berlin_tile)
	var markers_near_berlin := creatures_parent.get_child_count()
	assert_gt(markers_near_berlin, 0)

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_false(manager.has_ecosystem_region(center_chunk))


func test_step_ecosystem_does_nothing_before_a_simulated_day_has_elapsed():
	manager.update(_berlin_tile)
	var before_ids := _child_instance_ids(creatures_parent)

	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY * 0.01)

	assert_eq(_child_instance_ids(creatures_parent), before_ids)


func test_step_ecosystem_refreshes_creature_markers_after_a_full_simulated_day():
	manager.update(_berlin_tile)
	var before_ids := _child_instance_ids(creatures_parent)

	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY)

	assert_ne(_child_instance_ids(creatures_parent), before_ids)


## Computes a chunk's dominant biome the same way (sampling biome_at_global
## over every cell) BiomeClassifier.dominant_biome would from the chunk's own
## `biome` array -- used to verify EarthChunkManager actually threads that
## biome into CreatureRenderer.spawn_creatures rather than always falling
## back to the generic pool.
func _dominant_biome_of_chunk(chunk_coord: Vector2i) -> String:
	var biome_array := PackedStringArray()
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
			var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
			biome_array.append(manager.biome_at_global(global_x, global_y))
	return BiomeClassifier.new().dominant_biome(biome_array)


# -- region difficulty (see docs/concept/ecosystem_dynamics.md's Region
# difficulty section) -- dangerous species (bear/lion/venomous_snake) are
# gated behind HARD difficulty, itself a distance-from-spawn gradient.

func test_set_spawn_tile_makes_nearby_regions_use_easy_difficulty():
	manager.set_spawn_tile(_berlin_tile)
	manager.update(_berlin_tile)

	for child in creatures_parent.get_children():
		if child is CreatureMarker and child.info != null:
			assert_false(
				child.info.species in ["bear", "lion", "venomous_snake"],
				"dangerous species should not appear at EASY difficulty near the configured spawn"
			)


## Without set_spawn_tile ever being called (e.g. a manager constructed
## directly, as most of this test file's tests do), difficulty defaults to
## HARD -- fails open to "nothing is gated" rather than silently changing
## every other test in this file's existing species-pool behavior.
func test_without_a_configured_spawn_difficulty_defaults_to_unrestricted():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_eq(manager._difficulty_tier_at(center_chunk), RegionDifficulty.Tier.HARD)


func test_a_configured_spawns_own_chunk_is_easy_difficulty():
	manager.set_spawn_tile(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_eq(manager._difficulty_tier_at(center_chunk), RegionDifficulty.Tier.EASY)


# -- explored-tiles wiring (see docs/concept/wayfinding.md's Map item) ------
# Pure delegation to ExploredTiles -- no chunk loading involved, so these
# stay cheap: construct a manager the same way every other fast test in
# this file already does and call the three coordinator methods directly.

func test_marking_a_chunk_explored_returns_true_the_first_time():
	assert_true(manager.mark_chunk_explored(Vector2i(2, 3)))


func test_marking_an_already_explored_chunk_again_returns_false():
	manager.mark_chunk_explored(Vector2i(2, 3))
	assert_false(manager.mark_chunk_explored(Vector2i(2, 3)))


func test_is_chunk_explored_is_false_before_marking_and_true_after():
	assert_false(manager.is_chunk_explored(Vector2i(4, 5)))
	manager.mark_chunk_explored(Vector2i(4, 5))
	assert_true(manager.is_chunk_explored(Vector2i(4, 5)))


func test_explored_chunks_lists_every_distinct_marked_chunk():
	manager.mark_chunk_explored(Vector2i(1, 1))
	manager.mark_chunk_explored(Vector2i(2, 2))
	assert_eq(manager.explored_chunks().size(), 2)
	assert_true(manager.explored_chunks().has(Vector2i(1, 1)))
	assert_true(manager.explored_chunks().has(Vector2i(2, 2)))


# -- spawn chunk coord getter (Compass's "point me home" default target) ----

func test_spawn_chunk_coord_reflects_the_configured_spawn_tile():
	manager.set_spawn_tile(_berlin_tile)
	var expected_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_eq(manager.spawn_chunk_coord(), expected_chunk)


func test_promoted_creatures_near_berlin_only_use_species_from_their_chunks_biome_pool():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var dominant := _dominant_biome_of_chunk(center_chunk)

	var expected_species := {}
	for species in CreatureRenderer.HERBIVORE_SPECIES_POOL_BY_BIOME.get(
		dominant, CreatureRenderer.HERBIVORE_SPECIES_POOL
	):
		expected_species[species] = true
	for species in CreatureRenderer.PREDATOR_SPECIES_POOL_BY_BIOME.get(
		dominant, CreatureRenderer.PREDATOR_SPECIES_POOL
	):
		expected_species[species] = true

	var chunk_origin := center_chunk * EarthChunkManager.CHUNK_SIZE
	var checked_any := false
	for child in creatures_parent.get_children():
		if not (child is CreatureMarker):
			continue  # fish/NPCs/village houses share this parent but have no CreatureInfo/species pool
		var tile_x := int(child.position.x / TerrainRenderer.TILE_SIZE)
		var tile_y := int(child.position.y / TerrainRenderer.TILE_SIZE)
		var in_center_chunk := (
			tile_x >= chunk_origin.x and tile_x < chunk_origin.x + EarthChunkManager.CHUNK_SIZE
			and tile_y >= chunk_origin.y and tile_y < chunk_origin.y + EarthChunkManager.CHUNK_SIZE
		)
		if in_center_chunk:
			checked_any = true
			assert_true(
				expected_species.has(child.info.species),
				"%s is not in the expected species pool for dominant biome '%s'" % [child.info.species, dominant]
			)
	assert_true(checked_any, "precondition: some creature should be promoted in Berlin's own chunk")


# -- forage (central, throttled tree drops) -----------------------------------

func test_step_forage_drops_ground_items_from_loaded_trees_after_an_interval():
	manager.update(_berlin_tile)
	assert_gt(entities_parent.get_child_count(), 0, "precondition: some trees loaded near Berlin")

	watch_signals(WorldItemBus)
	manager.step_forage(EarthChunkManager.FORAGE_INTERVAL)

	assert_signal_emit_count(WorldItemBus, "item_dropped", EarthChunkManager.FORAGE_DROPS_PER_TICK)


func test_step_forage_does_nothing_before_the_interval_elapses():
	manager.update(_berlin_tile)
	watch_signals(WorldItemBus)
	manager.step_forage(EarthChunkManager.FORAGE_INTERVAL * 0.1)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)


func test_step_forage_drops_nothing_when_no_trees_are_loaded():
	# No update() -> nothing loaded -> no trees to forage from.
	watch_signals(WorldItemBus)
	manager.step_forage(EarthChunkManager.FORAGE_INTERVAL)
	assert_signal_emit_count(WorldItemBus, "item_dropped", 0)


# -- fruiting (near-detail phenology drops a NAMED species, see TreeSpecies) --

## step_fruiting (unlike the ambient step_forage above) runs real per-tree
## phenology for trees close to the player, and now drops the tree's actual
## NAMED species id (cherry/apple/walnut) rather than the generic "fruit"/
## "nut" every tree used to drop regardless of species.
func test_step_fruiting_drops_named_species_items_near_the_player():
	manager.update(_berlin_tile)
	assert_gt(entities_parent.get_child_count(), 0, "precondition: some trees loaded near Berlin")

	# A WHOLE YEAR, because that is now what a bearing cycle is.
	#
	# This said 3000 seconds, which was five years back when a year was ten
	# minutes. A day became four real hours (SeasonCycle.SECONDS_PER_DAY), so
	# the same 3000 seconds is now 0.43% of a year -- long before any species'
	# ripening phase -- and the test failed asserting that nothing had fallen
	# yet, which was true. The span has to be expressed in the calendar it is
	# actually measured against, not in a number of seconds that silently
	# stopped meaning what it meant.
	manager.advance_world_age(SeasonCycle.SECONDS_PER_YEAR)

	var berlin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	watch_signals(WorldItemBus)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, berlin_pixel)

	var drop_count = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_gt(
		drop_count, 0,
		"precondition: a nearby tree should have shed its crop over a full year"
	)
	var saw_named_species := false
	for i in drop_count:
		var stack = get_signal_parameters(WorldItemBus, "item_dropped", i)[0]
		if TreeSpecies.IDS.has(stack.item.id):
			saw_named_species = true
	assert_true(
		saw_named_species,
		"fallen fruit near the player should use a named species id, not the generic fruit/nut"
	)


## The perf fix step_fruiting's per-tree loop now applies: genome lookup,
## species/pollination lookups, FruitingModel.state_at, and above all
## tree.set_ripe_fruit's canopy texture redraw all used to run for EVERY
## loaded tree in the whole streaming radius -- potentially thousands --
## roughly once a second, forever, including trees the player has never
## been anywhere near. A tree beyond FRUITING_DETAIL_RADIUS must now be
## skipped entirely for the tick, and because FruitingModel.state_at is a
## PURE function of elapsed world time rather than a running simulation,
## that skip must not freeze the tree: it has to show the correct catch-up
## ripeness the moment the player is back in range.
##
## Reads the tree's raw _ripe_count field rather than the public
## ripe_fruit_count() getter -- that getter clamps the "never touched" -1
## sentinel to 0, so it cannot distinguish "skipped for being out of range"
## from "processed and genuinely bore no fruit" the way this test needs to.
func test_step_fruiting_skips_a_far_tree_then_shows_its_real_ripeness_once_in_range():
	var species_id := "apple"
	var tree_position := _position_for_species(species_id)

	var scheduler := ForageScheduler.new()
	var genome := scheduler.genome_for(tree_position)
	var model := FruitingModel.new()
	# Land the world clock at genuine mid-plateau peak (same technique as
	# test_harvest_peak_fruit_near_reports_the_real_peak_state above), so the
	# tree actually has real hanging fruit to catch up on. Computed and set
	# BEFORE the tree is even loaded, so establishing the clock itself -- via
	# set_world_age_seconds's own sync_tree_season call -- cannot be what
	# dresses it.
	var warmth_for_window: float = manager._warmth_at_pixel(tree_position)
	var window: Dictionary = model._window_for(genome, warmth_for_window)
	var peak_time: float = (
		(float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	manager.set_world_age_seconds(peak_time)

	var tree := ChoppableTree.new()
	tree.position = tree_position
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	var far_pixel := tree.position + Vector2(EarthChunkManager.FRUITING_DETAIL_RADIUS + 1000.0, 0.0)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, far_pixel)

	assert_eq(
		tree._ripe_count, -1,
		"a tree outside FRUITING_DETAIL_RADIUS must be skipped entirely, not dressed with a stale/default value"
	)

	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, tree.position)

	# Apple is insect-pollinated (TreeSpecies._INSECT_POLLINATED) and this tree
	# was never visited by a bee, so step_fruiting's own yield_multiplier
	# composes FruitingModel.pollination_factor(0) -- the UNPOLLINATED_YIELD_
	# FLOOR, a fifth of the ceiling -- on top of the species multiplier (see
	# step_fruiting's own pollination_factor block). Leaving that out here
	# used to overstate "expected" by 5x (10 instead of the real 2): this is
	# the REAL catch-up ripeness the test's own name promises, not a second,
	# looser opinion about it.
	var pollination_factor := 1.0
	if TreeSpecies.needs_pollinators_for(species_id):
		pollination_factor = FruitingModel.pollination_factor(
			tree.pollination_visits_in_cycle(FruitingModel.BEARING_CYCLE_SECONDS, manager.world_age_seconds())
		)
	var yield_multiplier := TreeSpecies.yield_multiplier_for(species_id) * pollination_factor
	var ripening_multiplier := TreeSpecies.ripening_multiplier_for(species_id)
	var current_warmth: float = manager._warmth_at_pixel(tree.position)
	var expected: Dictionary = manager._fruiting_model.state_at(
		genome, manager.world_age_seconds(), current_warmth, yield_multiplier, ripening_multiplier
	)
	var expected_ripe := int(expected.get("ripe", 0))

	assert_gt(expected_ripe, 0, "precondition: mid-plateau should carry real ripe fruit")
	assert_eq(
		tree._ripe_count, expected_ripe,
		"once back in range the tree must show the REAL catch-up ripeness for the elapsed time, not a frozen/stale value"
	)


## step_fruiting's own per-tree loop calls tree.set_ripe_fruit directly (not
## through sync_tree_season's loop), so it has to pass the live snow depth
## through too -- otherwise every fruiting tick would silently reset a
## nearby tree's snow back to zero between sync_tree_season's own less
## frequent redraws.
func test_step_fruiting_also_dresses_a_nearby_tree_with_the_live_snow_depth():
	var species_id := "apple"
	var tree_position := _position_for_species(species_id)
	manager.set_snow_depth(0.5)

	var tree := ChoppableTree.new()
	tree.position = tree_position
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, tree.position)

	assert_almost_eq(tree._snow_coverage, 0.5, 0.0001)


# -- fallen leaves: the same fruiting step also sheds real ground litter ----
#
# See docs/concept/leaf_litter.md. Reported: "ants should eat fallen fruits
# leaves and other stuff like seeds", then later "it seems that falling
# leaves are still not implemented" once fallen-fruit foraging alone had
# shipped. Gated on the canopy's own TURNING-INTO-WINTER window -- the same
# season/turning_into/turn_progress values already read once per step for
# the windfall block above, not a second schedule computing its own answer.

## A year_fraction inside autumn's own TURN_FRACTION window (the last 34% of
## autumn -- see TreePhenology._settled_then_turn). Autumn is
## SeasonCycle.SEASONS[2], so its own span is [0.5, 0.75); 0.72 sits
## comfortably inside the turning slice of that ([0.665, 0.75)), not its
## settled first two-thirds.
const _TURNING_INTO_WINTER_YEAR_FRACTION := 0.72
## Well inside summer's own settled span -- the trickle window, see
## LEAF_SUMMER_TRICKLE_CHANCE.
const _SETTLED_SUMMER_YEAR_FRACTION := 0.3
## Well inside spring, before blossom even opens -- no leaf falls at all
## here (see step_fruiting's own leaf_fall_chance/leaf_fall_season block):
## neither the autumn turn nor the summer trickle condition is true.
const _SETTLED_SPRING_YEAR_FRACTION := 0.05
## Generous bound for the deterministic per-step roll (see
## EarthChunkManager's own doc comment on it) to land a hit -- not a retry
## against flakiness, since the roll is a pure hash of (tree seed, step),
## not engine randf(): a real bug that stopped leaves falling entirely
## would still exhaust every one of these attempts and fail the same way.
const _LEAF_ROLL_ATTEMPTS := 30
## LEAF_SUMMER_TRICKLE_CHANCE is a real 3% per step, not autumn's own
## progress-scaled (and often much higher) chance -- needs far more
## attempts for the SAME "a real bug would exhaust every one of these
## too" guarantee (at 3%, 300 attempts leaves under a 1 in 10^3 chance of
## a false failure from the roll sequence alone).
const _LEAF_TRICKLE_ROLL_ATTEMPTS := 300


func _set_world_age_at_year_fraction(fraction: float) -> void:
	manager.set_world_age_seconds(fraction * SeasonCycle.SECONDS_PER_YEAR)


## The chunk-local LeafLitterField a tree at `tree_position` would fall
## into, creating it on demand -- these tests build a bare `manager` and
## inject trees directly into `_loaded_trees` (see before_each's own doc
## comment on why this file never calls the real, expensive update()), so
## the normal chunk-load path that would otherwise create this field (see
## EarthChunkManager's own leaf-fall wiring) never runs here either.
func _leaf_litter_field_for(tree_position: Vector2) -> LeafLitterField:
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(
		manager._world_tile_for_pixel(tree_position)
	)
	if not manager._leaf_litter_fields.has(chunk_coord):
		manager._leaf_litter_fields[chunk_coord] = LeafLitterField.new()
	return manager._leaf_litter_fields[chunk_coord]


## Finds the first fallen-leaf record for `species_id` across up to
## `attempts` fruiting steps, or {} if none fell (see LeafLitterField's own
## doc comment for the record shape). Leaves accumulate in the field across
## attempts (nothing here ever consumes one), so this is really "has one
## fallen at all yet", the same thing the old WorldItemBus-signal-count
## version checked.
##
## Advances the world clock by FRUITING_INTERVAL between attempts -- the
## per-step roll is a deterministic hash of (tree seed, step_bucket), see
## EarthChunkManager's own doc comment, so without a real clock advance
## every attempt would re-read the identical step_bucket and re-roll the
## exact same result. The total advance across even _LEAF_TRICKLE_ROLL_
## ATTEMPTS stays a tiny fraction of a season's own span, so this never
## risks drifting into the next season mid-loop.
##
## Forces LEAF_LITTER_ENABLED on for the lookup by default (restoring
## whatever it was after) -- the fall-triggering mechanism itself (angle/
## distance/season roll) is still real, tested logic even while the flag
## ships off by default (see that constant's own doc comment); pass
## force_enabled=false for the one test that specifically wants to see the
## flag's OFF behaviour instead.
## `force_enabled` sets LEAF_LITTER_ENABLED to EXACTLY this value for the
## duration of the lookup, in both directions -- not just "true, or else
## leave it at whatever the ambient default currently is". That distinction
## used to be invisible (this helper's own `if force_enabled: ... = true`,
## with no else, happened to coincide with the real default being false),
## until flipping the real default to true silently broke
## test_step_fruiting_adds_no_leaf_when_leaf_litter_disabled's own
## `force_enabled=false` call, which had never actually been forcing
## anything off at all -- it was only ever coasting on an ambient default
## that happened to already be false. Fixed here rather than left as a
## trap for the next default flip.
func _find_a_fallen_leaf(
	species_id: String, tree_position: Vector2, player_pixel: Vector2,
	attempts: int = _LEAF_ROLL_ATTEMPTS, force_enabled: bool = true
) -> Dictionary:
	var previous_enabled := EarthChunkManager.LEAF_LITTER_ENABLED
	EarthChunkManager.LEAF_LITTER_ENABLED = force_enabled
	var field := _leaf_litter_field_for(tree_position)
	var result := {}
	for attempt in attempts:
		if attempt > 0:
			manager.advance_world_age(EarthChunkManager.FRUITING_INTERVAL)
		manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, player_pixel)
		for leaf in field.leaves():
			if leaf.species == species_id:
				result = leaf
				break
		if not result.is_empty():
			break
	EarthChunkManager.LEAF_LITTER_ENABLED = previous_enabled
	return result


func test_step_fruiting_drops_a_leaf_from_a_turning_tree():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_TURNING_INTO_WINTER_YEAR_FRACTION)

	var found := _find_a_fallen_leaf("cherry", tree.position, tree.position)

	assert_false(found.is_empty(), "a tree well into its autumn turn should shed a real leaf item")


## The record's own `season` field carries which season it fell in (see
## LeafLitterAtlas/LeafLitterRenderer) -- the mechanism that actually gives
## a leaf its correct colour.
func test_a_leaf_records_the_autumn_season_it_fell_in():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_TURNING_INTO_WINTER_YEAR_FRACTION)

	var found := _find_a_fallen_leaf("cherry", tree.position, tree.position)

	assert_false(found.is_empty(), "precondition: a leaf should have fallen")
	assert_eq(found.season, "autumn")


## Reported: "when they fall in summer they should be green" -- a real,
## if much rarer, trickle in settled summer, not only the main autumn
## fall (see LEAF_SUMMER_TRICKLE_CHANCE).
func test_step_fruiting_also_drops_a_light_summer_trickle():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_SETTLED_SUMMER_YEAR_FRACTION)

	var found := _find_a_fallen_leaf(
		"cherry", tree.position, tree.position, _LEAF_TRICKLE_ROLL_ATTEMPTS
	)

	assert_false(found.is_empty(), "a settled summer tree should still shed an occasional leaf")
	assert_eq(found.season, "summer")


## Spring, before blossom even opens, is neither the autumn turn nor the
## summer trickle -- step_fruiting's own leaf_fall_chance stays exactly
## zero here, not merely small.
func test_step_fruiting_drops_no_leaf_in_early_spring():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_SETTLED_SPRING_YEAR_FRACTION)

	var field := _leaf_litter_field_for(tree.position)
	for attempt in _LEAF_ROLL_ATTEMPTS:
		manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, tree.position)
	var saw_leaf := false
	for leaf in field.leaves():
		if leaf.species == "cherry":
			saw_leaf = true
	assert_false(saw_leaf, "nothing has started shedding yet in early spring")


## Oak's own fallen leaf records species "acorn" (TreeSpecies' own id for the
## tree, not a literal "oak") -- LeafLitterAtlas's own art lookup keys off
## this same species id (see that class's own cell_index).
func test_a_leaf_records_its_own_species():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("acorn")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_TURNING_INTO_WINTER_YEAR_FRACTION)

	var found := _find_a_fallen_leaf("acorn", tree.position, tree.position)

	assert_false(found.is_empty(), "precondition: an acorn tree should shed a leaf")
	assert_eq(found.species, "acorn")


func test_a_leaf_lands_near_its_own_tree():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	_set_world_age_at_year_fraction(_TURNING_INTO_WINTER_YEAR_FRACTION)

	var found := _find_a_fallen_leaf("cherry", tree.position, tree.position)

	assert_false(found.is_empty(), "precondition: a leaf should have fallen")
	var leaf_at: Vector2 = found.position
	assert_lt(
		tree.position.distance_to(leaf_at), EarthChunkManager.LEAF_SCATTER_RADIUS + 1.0,
		"a leaf landed nowhere near its own tree"
	)


# -- LEAF_LITTER_ENABLED: on by default again -------------------------------
#
# Was briefly an off-by-default deactivation switch (requested directly:
# "deactivate leaf littering", right after the GPU rewrite shipped). Turned
# back on: reported live that ants/bugs "just walk back and forth" with
# real foraging never actually happening -- with this off, carrion and
# fresh windfall fruit are the only things left for a decomposer to find,
# and neither is reliably nearby early in a game, so an ambient decomposer
# had nothing to forage in practice. Live-verified before flipping this
# back on (see docs/concept/leaf_litter.md's own Status entry for the real
# measurement) that the GPU rewrite actually fixed the original per-node
# performance report, not just assumed to have from the architecture
# change alone. Same idiom as EarthChunkGenerator.HYDROLOGY_RIVERS_ENABLED,
# a mutable static var (not a const) so the fall-triggering mechanism
# itself stays directly tested regardless of which way the default sits
# (see _find_a_fallen_leaf's own doc comment) -- this file's own coverage
# of the OFF behaviour (test_step_fruiting_adds_no_leaf_when_leaf_litter_
# disabled, just below) is unaffected either way, since it forces the flag
# explicitly rather than relying on the default.

func test_leaf_litter_is_on_by_default():
	assert_true(EarthChunkManager.LEAF_LITTER_ENABLED)


func test_step_fruiting_adds_no_leaf_when_leaf_litter_disabled():
	var tree := ChoppableTree.new()
	tree.position = _position_for_species("cherry")
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]
	# Fully turned autumn, well past the turning point -- the exact
	# precondition test_step_fruiting_drops_a_leaf_from_a_turning_tree
	# already relies on to guarantee a shed leaf when the switch is on.
	_set_world_age_at_year_fraction(_TURNING_INTO_WINTER_YEAR_FRACTION)

	# force_enabled=false -- this is the one test that wants the flag
	# actually forced OFF, not _find_a_fallen_leaf's own default of forcing
	# it on to exercise the underlying mechanism regardless of the real
	# shipped default.
	var found := _find_a_fallen_leaf(
		"cherry", tree.position, tree.position, _LEAF_ROLL_ATTEMPTS, false
	)

	assert_true(
		found.is_empty(),
		"no leaf should be added while LEAF_LITTER_ENABLED is off, however far into its turn the tree is"
	)


# -- sync_tree_season: the second path that redraws every loaded tree's ------
# canopy, independent of step_fruiting (see World._client_process and
# set_world_age_seconds/jump_to_season). Must respect the same
# FRUITING_DETAIL_RADIUS gate when it has a player_pixel to check against, or
# a tree step_fruiting skipped for being out of range gets re-dressed right
# back in -- with its own stale cached ripe_fruit_count() -- the moment a
# season changes, including the very first-ever call (its tracked signature,
# _last_tree_season, starts empty and so never matches).

func test_sync_tree_season_leaves_a_far_tree_untouched():
	var tree := ChoppableTree.new()
	tree.position = Vector2(500, 500)
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	var far_pixel := tree.position + Vector2(EarthChunkManager.FRUITING_DETAIL_RADIUS + 1000.0, 0.0)
	manager.sync_tree_season(far_pixel)

	assert_eq(tree._ripe_count, -1, "a season sync must not dress a tree the player is nowhere near")
	assert_eq(tree.current_season(), "", "a season sync must not dress a tree the player is nowhere near")


func test_sync_tree_season_dresses_a_nearby_tree():
	var tree := ChoppableTree.new()
	tree.position = Vector2(500, 500)
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	manager.sync_tree_season(tree.position)

	assert_ne(
		tree.current_season(), "",
		"a tree the player is standing next to should be dressed on a season sync, not skipped"
	)


# -- snow reaching an already-standing tree ----------------------------------
#
# TreeRenderer.set_snow_coverage only reaches a tree at the moment it is
# SPAWNED (see test_tree_renderer.gd) -- it holds no reference to any tree
# once built, so it cannot push a live change to one already standing.
# sync_tree_season is the mechanism that already redraws every loaded tree's
# canopy for season/turn; it has to carry snow the rest of the way too, or an
# already-standing forest would never visibly whiten as it snows.

func test_sync_tree_season_dresses_a_nearby_tree_with_the_live_snow_depth():
	var tree := ChoppableTree.new()
	tree.position = Vector2(500, 500)
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	manager.set_snow_depth(0.6)
	manager.sync_tree_season(tree.position)

	assert_almost_eq(
		tree._snow_coverage, 0.6, 0.0001,
		"a nearby tree should be dressed with the live snow depth, not left at zero"
	)


## step_snow (the real per-frame path -- see World._client_process) sets
## _snow_depth directly rather than through set_snow_depth, so sync_tree_season
## has to read the live field itself rather than relying on set_snow_depth
## having been called at all.
func test_sync_tree_season_reads_snow_depth_set_via_step_snow_not_only_set_snow_depth():
	var tree := ChoppableTree.new()
	tree.position = Vector2(500, 500)
	tree.bind_canopy(Sprite2D.new())
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	# advance_world_age gives step_snow real elapsed time to accumulate
	# against (see test_set_world_age_seconds_does_not_fake_a_catch_up_on_
	# the_first_snow_step's own precedent) -- calling step_snow cold, with
	# no elapsed time yet, would accumulate nothing.
	manager.advance_world_age(1.0)
	manager.step_snow(true, 0.0)  # cold and snowing
	assert_gt(manager.snow_depth(), 0.0, "precondition: step_snow should have laid down real snow")

	manager.sync_tree_season(tree.position)

	assert_almost_eq(tree._snow_coverage, manager.snow_depth(), 0.0001)


# -- building/destruction -----------------------------------------------------

func test_build_at_global_sets_a_modification_when_the_chunk_is_loaded():
	manager.update(_berlin_tile)
	var success := manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")
	assert_true(success)
	assert_eq(manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "earth")


func test_build_at_global_fails_when_the_chunk_is_not_loaded():
	var success := manager.build_at_global(999999, 999999, "earth")
	assert_false(success)


## Asserts the cell actually changed rather than pinning an exact atlas
## coordinate: a real Berlin tile almost always has at least one real,
## unmodified land-biome cardinal neighbor, so the earth cell now blends
## toward it (see TerrainRenderer.earth_dominant_blend_for/paint()'s
## modifications branch) instead of always landing on the flat
## atlas_coords_for_modification("earth") tile -- which TerrainRenderer's
## own test suite (test_terrain_renderer.gd) already covers in detail. This
## test's own job is just proving build_at_global -> paint() wiring fires.
func test_build_at_global_repaints_the_tile_map_cell():
	manager.update(_berlin_tile)
	var before_coords := tile_map_layer.get_cell_atlas_coords(_berlin_tile)

	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")

	assert_ne(
		tile_map_layer.get_cell_atlas_coords(_berlin_tile), before_coords,
		"building earth should repaint the cell away from its original biome tile"
	)


func test_destroy_at_global_removes_a_previously_built_modification():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")

	var success := manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)

	assert_true(success)
	assert_eq(manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "")


func test_destroy_at_global_fails_when_there_is_nothing_to_remove():
	manager.update(_berlin_tile)
	var success := manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)
	assert_false(success)


# -- structure proximity (has_structure_near) ----------------------------------

func test_has_structure_near_is_true_at_the_exact_tile():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "campfire")

	assert_true(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


func test_has_structure_near_is_true_within_radius():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "campfire")

	assert_true(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


func test_has_structure_near_is_false_beyond_radius():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 5, _berlin_tile.y, "campfire")

	assert_false(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


func test_has_structure_near_is_false_for_a_different_structure_id():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "furnace")

	assert_false(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


func test_has_structure_near_is_false_when_nothing_is_built():
	manager.update(_berlin_tile)
	assert_false(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


## Chebyshev (square) radius, not circular -- a structure diagonally offset by
## (2, 2) is within radius 3 (max(2, 2) == 2 <= 3), matching the simple
## chunk-radius style already used elsewhere in this manager (see
## _chebyshev_distance / chunks_in_radius).
func test_has_structure_near_uses_chebyshev_not_euclidean_distance():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y + 2, "campfire")

	assert_true(manager.has_structure_near(_berlin_tile.x, _berlin_tile.y, "campfire", 3))


## A structure built just across a chunk boundary from the query tile must
## still be found -- has_structure_near checks the query tile's own chunk plus
## its immediate neighbors (see its doc comment), not just the single chunk
## the query tile itself falls in.
func test_has_structure_near_detects_a_structure_across_a_chunk_boundary():
	manager.update(Vector2i(0, 0))
	var boundary_x := EarthChunkManager.CHUNK_SIZE - 1  # last column of chunk (0, 0)
	manager.build_at_global(boundary_x + 1, 0, "campfire")  # first column of chunk (1, 0)

	assert_true(manager.has_structure_near(boundary_x, 0, "campfire", 3))


# -- nearest_structure_position (see docs/concept/timber_construction.md's --
# -- "Storage, logistics, and the autonomous dependency chain" section: a ----
# -- Logistics worker needs WHERE the nearest structure is, not just whether -
# -- one exists) -------------------------------------------------------------

func test_nearest_structure_position_finds_a_structure_within_range():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var found = manager.nearest_structure_position(origin_pixel, "storage", 200.0)

	assert_not_null(found)


func test_nearest_structure_position_returns_null_when_out_of_range():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 50, _berlin_tile.y, "storage")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	assert_null(manager.nearest_structure_position(origin_pixel, "storage", 20.0))


func test_nearest_structure_position_returns_null_when_nothing_built():
	manager.update(_berlin_tile)
	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	assert_null(manager.nearest_structure_position(origin_pixel, "storage", 2000.0))


func test_nearest_structure_position_ignores_a_different_structure_id():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 1, _berlin_tile.y, "furnace")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	assert_null(manager.nearest_structure_position(origin_pixel, "storage", 200.0))


func test_nearest_structure_position_picks_the_closer_of_two_candidates():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 10, _berlin_tile.y, "storage")
	manager.build_at_global(_berlin_tile.x + 1, _berlin_tile.y, "storage")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var expected_near := Vector2(_berlin_tile.x + 1, _berlin_tile.y) * TerrainRenderer.TILE_SIZE + Vector2.ONE * (
		TerrainRenderer.TILE_SIZE * 0.5
	)
	var found: Vector2 = manager.nearest_structure_position(origin_pixel, "storage", 2000.0)
	assert_almost_eq(found.x, expected_near.x, 0.5)
	assert_almost_eq(found.y, expected_near.y, 0.5)


# -- nearby_structure_positions (see docs/concept/timber_construction.md's --
# -- own named honest constraint this closes: "a Sägewerk pairs with only --
# -- its single nearest Storage, not every Storage within range" -- the -----
# -- ALL-matches counterpart to nearest_structure_position's single-closest -
# -- answer, reusing the exact same chunk-scan loop) -------------------------

func test_nearby_structure_positions_finds_a_structure_within_range():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var found: Array = manager.nearby_structure_positions(origin_pixel, "storage", 200.0)

	assert_eq(found.size(), 1)


func test_nearby_structure_positions_returns_every_match_within_range_not_just_the_nearest():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 10, _berlin_tile.y, "storage")
	manager.build_at_global(_berlin_tile.x + 1, _berlin_tile.y, "storage")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var found: Array = manager.nearby_structure_positions(origin_pixel, "storage", 2000.0)

	assert_eq(found.size(), 2, "both real Storage tiles are within range -- not just the closer one")


func test_nearby_structure_positions_excludes_matches_beyond_max_distance():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 1, _berlin_tile.y, "storage")
	manager.build_at_global(_berlin_tile.x + 50, _berlin_tile.y, "storage")

	# origin_pixel is the query tile's top-left corner, and distance is
	# measured to the FAR structure's own tile CENTER (same convention
	# nearest_structure_position already uses) -- at TILE_SIZE=16 that is
	# 1*16 + 8 = 24px for the +1-tile storage, so max_distance must clear
	# 24 to count it as in-range while still excluding the +50-tile one.
	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var found: Array = manager.nearby_structure_positions(origin_pixel, "storage", 30.0)

	assert_eq(found.size(), 1, "only the in-range Storage should be returned")


func test_nearby_structure_positions_returns_empty_array_when_nothing_built():
	manager.update(_berlin_tile)
	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE

	var found: Array = manager.nearby_structure_positions(origin_pixel, "storage", 2000.0)

	assert_eq(found.size(), 0)


func test_nearby_structure_positions_ignores_a_different_structure_id():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 1, _berlin_tile.y, "furnace")

	var origin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var found: Array = manager.nearby_structure_positions(origin_pixel, "storage", 200.0)

	assert_eq(found.size(), 0)


# -- structure stock (Storage's real inventory, and any future producer's ----
# -- accumulated-output queue -- see StructureStock/StructureStockStore's ----
# -- own doc comments) --------------------------------------------------------

func test_structure_stock_starts_empty():
	assert_eq(manager.structure_stock_at(10, 20, "plank"), 0)


func test_deposit_to_structure_at_increases_its_stock():
	manager.deposit_to_structure_at(10, 20, "plank", 5)
	assert_eq(manager.structure_stock_at(10, 20, "plank"), 5)


func test_deposit_to_structure_at_keys_by_position_not_shared_globally():
	manager.deposit_to_structure_at(10, 20, "plank", 5)
	assert_eq(manager.structure_stock_at(30, 40, "plank"), 0)


func test_withdraw_from_structure_at_succeeds_and_deducts_when_enough_present():
	manager.deposit_to_structure_at(10, 20, "plank", 5)
	assert_true(manager.withdraw_from_structure_at(10, 20, "plank", 3))
	assert_eq(manager.structure_stock_at(10, 20, "plank"), 2)


func test_withdraw_from_structure_at_fails_when_short():
	manager.deposit_to_structure_at(10, 20, "plank", 2)
	assert_false(manager.withdraw_from_structure_at(10, 20, "plank", 3))
	assert_eq(manager.structure_stock_at(10, 20, "plank"), 2)


# -- persistence across unload/reload ------------------------------------------

func test_a_built_modification_survives_unloading_and_reloading_its_chunk():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)  # evicts Berlin's chunk
	manager.update(_berlin_tile)  # reloads it

	assert_eq(manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "earth")

	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var path := "user://chunk_modifications/%d_%d.bin" % [chunk_coord.x, chunk_coord.y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# -- tree spread (seed saplings grow near mature trees) -----------------------

func test_step_tree_spread_does_nothing_before_the_interval_elapses():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()

	manager.step_tree_spread(EarthChunkManager.SPREAD_INTERVAL * 0.1)

	assert_eq(entities_parent.get_child_count(), before)


func test_step_tree_spread_eventually_plants_a_new_tree_near_berlin():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()
	assert_gt(before, 0, "precondition: some trees loaded near Berlin")

	# Several intervals' worth of attempts -- TreeSpread can decline a given
	# attempt (too close to an existing tree), so one interval isn't a
	# reliable enough signal on its own.
	for i in 10:
		manager.step_tree_spread(EarthChunkManager.SPREAD_INTERVAL)

	assert_gt(entities_parent.get_child_count(), before)


func test_a_spread_tree_survives_unloading_and_reloading_its_chunk():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()

	for i in 10:
		manager.step_tree_spread(EarthChunkManager.SPREAD_INTERVAL)
	var after_spread := entities_parent.get_child_count()
	assert_gt(after_spread, before, "precondition: spread actually planted a tree")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)  # evicts Berlin's chunks
	manager.update(_berlin_tile)  # reloads them

	assert_eq(entities_parent.get_child_count(), after_spread)

	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		var path := "user://chunk_planted_trees/%d_%d.bin" % [chunk_coord.x, chunk_coord.y]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# -- building-piece collision (see docs/concept/building.md#pieces) -----------
#
# A wall/window piece must physically block movement, or "enclosure" is just
# a visual fiction; a door/floor piece must NOT, or the player couldn't walk
# into their own house. This project has no generic tile-solidity check --
# trees/boulders/ore block movement via real StaticBody2D+CollisionShape2D
# bodies (see TreeRenderer) -- so building pieces follow that exact
# convention rather than inventing a second collision mechanism.

func test_building_a_wall_piece_adds_a_collision_body():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall")
	var expected_position := Vector2(
		(_berlin_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (_berlin_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var found := false
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			found = true
	assert_true(found, "a wall piece should physically block movement")


func test_building_a_floor_piece_adds_no_collision_body():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_floor")
	assert_eq(entities_parent.get_child_count(), before, "a floor is walkable ground, nothing should block it")


func test_building_a_door_piece_adds_no_collision_body():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_door")
	assert_eq(entities_parent.get_child_count(), before, "a door must stay walkable so the player can enter")


func test_destroying_a_wall_piece_removes_its_collision_body():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall")
	var with_wall := entities_parent.get_child_count()

	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)

	assert_eq(entities_parent.get_child_count(), with_wall - 1)


## Building a SECOND piece where a wall used to be (e.g. player tears down a
## wall and puts a door there instead) must not leave the old wall's
## collision body behind -- build_at_global doesn't check occupancy the way
## BuildingPlacement.can_place does, so a stale collision body would silently
## outlive the piece that placed it.
func test_overwriting_a_wall_with_a_door_removes_the_stale_collision_body():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall")
	var with_wall := entities_parent.get_child_count()

	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_door")

	assert_eq(entities_parent.get_child_count(), with_wall - 1, "the old wall's collision body must be gone")


func test_unloading_a_chunk_frees_its_wall_collision_bodies():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall")
	var expected_position := Vector2(
		(_berlin_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (_berlin_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var body: Node = null
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			body = child
	assert_not_null(body, "precondition: the wall's collision body exists")

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))

	assert_false(is_instance_valid(body), "unloading the chunk should free its wall collision bodies too")
	var path := "user://chunk_modifications/%d_%d.bin" % [_chunk_coord_for_tile(_berlin_tile).x, _chunk_coord_for_tile(_berlin_tile).y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_reloading_a_chunk_restores_collision_for_a_persisted_wall():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "wood_wall")

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))  # unloads, persists to disk
	manager.update(_berlin_tile)  # reloads it

	var expected_position := Vector2(
		(_berlin_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (_berlin_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var found := false
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			found = true
	assert_true(found, "a restored wall modification should get its collision body back")
	var path := "user://chunk_modifications/%d_%d.bin" % [_chunk_coord_for_tile(_berlin_tile).x, _chunk_coord_for_tile(_berlin_tile).y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# -- real statics: a support graph over the piece grid (see
# docs/concept/timber_construction.md#real-statics-a-support-graph-over-the-
# piece-grid, src/gameplay/building_statics.gd) -- event-driven, not
# per-tick: build_at_global/destroy_at_global/stamp_structure_at_global each
# trigger a recompute scoped to just the touched structure's own connected
# piece grid.
#
# A single wall with all four neighbors occupied by non-load-bearing floor
# pieces never touches bare terrain, so its only possible support is a
# load-bearing chain that doesn't exist here -- it is unsupported the moment
# the last floor closes it in. This is the shared fixture below.

func _build_unsupported_wall_cluster(origin: Vector2i) -> void:
	manager.build_at_global(origin.x, origin.y, "wood_wall")
	manager.build_at_global(origin.x + 1, origin.y, "wood_floor")
	manager.build_at_global(origin.x - 1, origin.y, "wood_floor")
	manager.build_at_global(origin.x, origin.y + 1, "wood_floor")
	manager.build_at_global(origin.x, origin.y - 1, "wood_floor")  # closes it in -- now unsupported


## Re-triggers _sync_statics for the whole connected cluster _build_
## unsupported_wall_cluster made, WITHOUT itself propping any of it back up:
## a bare non-load-bearing floor "bridge" (bare, not itself load-bearing, so
## it can't relay support on its own), THEN a real (independently grounded)
## wall well past BuildingStatics.CANTILEVER_LIMIT tiles from the nearest
## cluster floor (F1, at origin+(1,0)) -- far enough that the new wall
## cannot rescue it. This is just "some further, unrelated edit happens
## nearby," the same way any other real player action naturally would
## re-touch this structure.
func _retrigger_statics_recheck(origin: Vector2i) -> void:
	var bridge_start := 2
	var trigger_x := origin.x + 1 + BuildingStatics.CANTILEVER_LIMIT + 1
	for x in range(origin.x + bridge_start, trigger_x):
		manager.build_at_global(x, origin.y, "wood_floor")
	manager.build_at_global(trigger_x, origin.y, "wood_wall")


## Well inside the chunk, not tied to _berlin_tile's own (possibly
## edge-adjacent) position -- see test_stamp_structure_at_global_writes_
## every_ground_piece_cell's doc comment for why a multi-cell footprint
## anchored on _berlin_tile itself is unsafe (posmod-aliasing across a
## chunk boundary).
func _statics_test_origin() -> Vector2i:
	return _chunk_coord_for_tile(_berlin_tile) * EarthChunkManager.CHUNK_SIZE + Vector2i(10, 10)


func test_a_piece_that_loses_its_support_path_does_not_collapse_immediately():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	watch_signals(WorldItemBus)

	_build_unsupported_wall_cluster(origin)

	assert_eq(
		manager.modification_at_global(origin.x, origin.y), "wood_wall",
		"a piece that just lost support should still be standing -- it needs grace time first"
	)
	assert_signal_emit_count(
		WorldItemBus, "item_dropped", 0, "nothing should have collapsed/dropped yet"
	)


## The full flow: an unsupported piece that stays unsupported past the real
## grace period actually collapses -- dropping its own constituent material
## back to the ground (mirroring how a felled tree/smashed stone already
## drops items via WorldItemBus.item_dropped) -- and the recompute this
## triggers cascades to whatever it was (in this case, non-load-bearingly)
## propping up, all without a second manual trigger: placing ONE more
## nearby piece is what re-triggers the same structure's recompute, the
## same way any further edit naturally would in real play.
func test_a_severed_support_collapses_past_the_grace_period_and_drops_its_material():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	_build_unsupported_wall_cluster(origin)
	watch_signals(WorldItemBus)

	manager.advance_world_age(BuildingStatics.GRACE_SECONDS + 1.0)
	_retrigger_statics_recheck(origin)

	assert_eq(
		manager.modification_at_global(origin.x, origin.y), "",
		"the wall should have actually collapsed and been removed"
	)
	var drops = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_gt(drops, 0, "a real collapse should drop real material")
	var found_wood_drop := false
	for i in range(drops):
		var params = get_signal_parameters(WorldItemBus, "item_dropped", i)
		var stack: ItemStack = params[0]
		if stack.item.id == "wood" and stack.count == 2:
			found_wood_drop = true
	assert_true(found_wood_drop, "the collapsed wall should drop exactly its own cost_of (2 wood)")


## The dependent floors, no longer within cantilever reach of any supported
## load-bearing cell once the wall is gone, come down too -- Worked Example
## D's cascade, at the engine level.
func test_a_collapse_cascades_to_the_pieces_it_was_propping_up():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	_build_unsupported_wall_cluster(origin)

	manager.advance_world_age(BuildingStatics.GRACE_SECONDS + 1.0)
	_retrigger_statics_recheck(origin)

	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		assert_eq(
			manager.modification_at_global(origin.x + offset.x, origin.y + offset.y), "",
			"the floor at %s, which only ever depended on the collapsed wall, should have come down too" % offset
		)


func test_destroying_a_wall_removes_its_collision_body_via_collapse_too():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	_build_unsupported_wall_cluster(origin)
	var expected_position := Vector2(
		(origin.x + 0.5) * TerrainRenderer.TILE_SIZE, (origin.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var before := false
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			before = true
	assert_true(before, "precondition: the still-standing wall has real collision")

	manager.advance_world_age(BuildingStatics.GRACE_SECONDS + 1.0)
	_retrigger_statics_recheck(origin)

	var after := false
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			after = true
	assert_false(after, "a collapsed wall must not leave a stale collision body behind")


# -- withering: decay as a bounded, closed-form catch-up (see
# docs/concept/timber_construction.md#withering-decay-as-a-bounded-closed-
# form-catch-up, src/gameplay/building_decay.gd) -- wired at the SAME
# unload/reload catch-up boundary the ecology precedent (_apply_ecology_
# catchup/_unloaded_ecology) already uses, and feeding the EXACT SAME
# _collapse_piece/_sync_statics path a severed support does once condition
# crosses BuildingDecay.RUINED_CONDITION_THRESHOLD -- decay and a severed
# support are two INPUTS into one collapse mechanism, not two parallel ones.

## Moves the player far enough away that the chunk holding _statics_test_
## origin()'s own structures genuinely unloads (see _unload_chunk), lets
## `elapsed_seconds` of real world-age pass while it sits unloaded, then
## moves back so it reloads and _apply_piece_condition_catchup actually
## runs -- the real streaming path, not a stubbed shortcut.
func _unload_wait_and_reload(elapsed_seconds: float) -> void:
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	if elapsed_seconds > 0.0:
		manager.advance_world_age(elapsed_seconds)
	manager.update(_berlin_tile)


func test_a_freshly_placed_piece_starts_at_full_condition():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	manager.build_at_global(origin.x, origin.y, "wood_wall")
	assert_almost_eq(manager.piece_condition_at_global(origin.x, origin.y), 1.0, 0.0001)


## A piece never touched by anything, on a chunk that was never unloaded,
## must not silently decay either -- the mechanism only runs at the real
## unload/reload catch-up boundary (see the doc's own two-fidelity framing);
## there is no separate per-frame decay for a chunk that stays loaded.
func test_a_piece_on_a_chunk_that_never_unloads_does_not_decay():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	manager.build_at_global(origin.x, origin.y, "wood_wall")
	manager.advance_world_age(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 5.0)
	assert_almost_eq(manager.piece_condition_at_global(origin.x, origin.y), 1.0, 0.0001)


func test_a_piece_condition_is_measurably_lower_after_a_real_simulated_absence():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	manager.build_at_global(origin.x, origin.y, "wood_wall")

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 0.1)

	var condition := manager.piece_condition_at_global(origin.x, origin.y)
	assert_lt(condition, 1.0, "an exposed piece should have measurably decayed over a real unloaded absence")
	assert_gt(condition, 0.0, "0.1 ecological day should not be anywhere near enough to ruin plain wood")


## A wall that bounds a real enclosed, floored room (see EarthChunkManager.
## _is_piece_roofed's own doc comment for why walls need an adjacency check
## rather than a literal RoomDetector.is_indoors on their own cell) should
## retain more condition than a free-standing, fully exposed wall of the
## SAME material over the SAME elapsed absence.
func test_a_sheltered_piece_decays_slower_than_an_exposed_one_over_the_same_absence():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var sheltered_origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(4, 4)
	var exposed_origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(20, 20)

	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			manager.build_at_global(sheltered_origin.x + dx, sheltered_origin.y + dy, "wood_wall")
	manager.build_at_global(sheltered_origin.x, sheltered_origin.y, "wood_floor")
	# The wall directly north of the floor -- an EDGE wall, orthogonally
	# adjacent to the one-cell interior room, unlike a corner wall (which is
	# only diagonally adjacent and would never actually register as roofed).
	var tracked_sheltered_wall := sheltered_origin + Vector2i(0, -1)

	manager.build_at_global(exposed_origin.x, exposed_origin.y, "wood_wall")

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 0.1)

	var sheltered_condition := manager.piece_condition_at_global(tracked_sheltered_wall.x, tracked_sheltered_wall.y)
	var exposed_condition := manager.piece_condition_at_global(exposed_origin.x, exposed_origin.y)
	assert_gt(
		sheltered_condition, exposed_condition,
		"a wall bounding a real roofed room should retain more condition than a free-standing exposed one"
	)


## The full flow: a piece decayed past BuildingDecay.RUINED_CONDITION_
## THRESHOLD during a real unloaded absence collapses via the EXACT SAME
## path a severed support does -- removed from modifications and dropping
## its own constituent material back to the ground (mirrors
## test_a_severed_support_collapses_past_the_grace_period_and_drops_its_
## material above, the model for constructing this scenario).
func test_a_fully_decayed_piece_collapses_via_the_same_collapse_path_and_drops_its_material():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	manager.build_at_global(origin.x, origin.y, "wood_wall")
	watch_signals(WorldItemBus)

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 2.0)

	assert_eq(
		manager.modification_at_global(origin.x, origin.y), "",
		"a piece decayed past the ruined threshold should have actually collapsed and been removed"
	)
	var drops = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_gt(drops, 0, "a real decay collapse should drop real material, same as a severed-support collapse")
	var found_wood_drop := false
	for i in range(drops):
		var params = get_signal_parameters(WorldItemBus, "item_dropped", i)
		var stack: ItemStack = params[0]
		if stack.item.id == "wood" and stack.count == 2:
			found_wood_drop = true
	assert_true(found_wood_drop, "the decayed wall should drop exactly its own cost_of (2 wood)")


func test_a_collapsed_decayed_piece_condition_is_no_longer_tracked():
	manager.update(_berlin_tile)
	var origin := _statics_test_origin()
	manager.build_at_global(origin.x, origin.y, "wood_wall")

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 2.0)

	# The piece is gone entirely -- piece_condition_at_global's own "1.0 for
	# a non-piece cell" default, not a lingering near-zero value.
	assert_almost_eq(manager.piece_condition_at_global(origin.x, origin.y), 1.0, 0.0001)


# -- construction labor catch-up (see docs/concept/timber_construction.md's
# "Unloaded / offscreen fidelity" subsection, construction_catchup.gd,
# ConstructionProjectStore.advance_project_labor) -- the settlement
# construction ledger's own real chunk-load caller. Wired at the EXACT SAME
# unload/reload catch-up boundary the withering section directly above
# already uses (_unload_wait_and_reload is the same helper), the same
# "two fidelities" philosophy applied to a ConstructionProject's own
# labor-hours accumulator instead of a piece's condition value.

const ConstructionProject = preload("res://src/emergence/construction_project.gd")

## A local footprint origin well inside the chunk, distinct from
## _statics_test_origin()'s own (10, 10) -- these tests build no actual
## wall/floor pieces, just a ConstructionProject sited at this cell, so
## there is no real collision risk either way, but keeping it distinct
## avoids any accidental coupling to the statics tests' own fixture cell.
func _construction_test_local_origin() -> Vector2i:
	return Vector2i(15, 15)


func test_an_in_progress_projects_labor_measurably_advances_after_a_real_simulated_chunk_unload_absence():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	# 2 real households -> builder_count 2 (household_count_for_settlement,
	# already real -- see this doc's own "do not reinvent" instruction).
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	manager.update(_berlin_tile)
	var project := manager.construction_project_store().start_project(
		chunk_coord, _construction_test_local_origin(), "sagewerk", "household:construction_labor_test"
	)
	project.status = ConstructionProject.Status.IN_PROGRESS

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 1.0)

	assert_gt(
		project.labor_hours_accumulated, 0.0,
		"a real IN_PROGRESS project's labor should measurably advance after a real simulated unloaded absence"
	)


## A chunk that never unloads must not advance construction labor at all --
## mirrors test_a_piece_on_a_chunk_that_never_unloads_does_not_decay's own
## identical regression shape: the mechanism only runs at the real
## unload/reload catch-up boundary, there is no separate live per-frame
## labor tick for a chunk that stays loaded the whole time.
func test_a_chunk_that_never_unloads_does_not_advance_construction_labor_at_all():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	manager.update(_berlin_tile)
	var project := manager.construction_project_store().start_project(
		chunk_coord, _construction_test_local_origin(), "sagewerk", "household:construction_labor_test"
	)
	project.status = ConstructionProject.Status.IN_PROGRESS

	manager.advance_world_age(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 5.0)

	assert_almost_eq(project.labor_hours_accumulated, 0.0, 0.0001)


## The full flow: a project reaching COMPLETE (2 households' worth of labor
## over 2 real unloaded days comfortably clears sagewerk's real 18-hour
## requirement -- see ConstructionLabor.labor_hours_required) actually
## places its own real tile at the project's own (chunk_coord, origin) --
## closing this doc's own previously-named "completing a project today only
## marks status + grants household property, it never actually builds
## anything" gap for a real placeable output.
func test_a_completed_projects_placeable_output_is_actually_placed_in_the_world():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	manager.update(_berlin_tile)
	var local_origin := _construction_test_local_origin()
	var project := manager.construction_project_store().start_project(
		chunk_coord, local_origin, "sagewerk", "household:construction_labor_test"
	)
	project.status = ConstructionProject.Status.IN_PROGRESS

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 2.0)

	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	var global_cell := chunk_coord * EarthChunkManager.CHUNK_SIZE + local_origin
	assert_eq(
		manager.modification_at_global(global_cell.x, global_cell.y), "sagewerk",
		"a completed project whose recipe output is a real placeable should actually place it in the world"
	)


## A project whose recipe output is NOT a placeable (e.g. "log_to_balken",
## whose real output is "beam" -- a plain material item, ItemCatalog.
## kind_of("beam") == "material") must still reach COMPLETE (the labor
## catch-up itself does not care what the output is), but must not attempt
## to place anything -- no crash, no garbage tile written to the world.
func test_a_completed_project_whose_output_is_not_placeable_places_nothing_and_does_not_crash():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	manager.update(_berlin_tile)
	var local_origin := _construction_test_local_origin()
	var project := manager.construction_project_store().start_project(
		chunk_coord, local_origin, "log_to_balken", "household:construction_labor_test"
	)
	project.status = ConstructionProject.Status.IN_PROGRESS

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 1.0)

	assert_eq(project.status, ConstructionProject.Status.COMPLETE)
	var global_cell := chunk_coord * EarthChunkManager.CHUNK_SIZE + local_origin
	assert_eq(
		manager.modification_at_global(global_cell.x, global_cell.y), "",
		"a completed project whose recipe output is not a real placeable should place nothing"
	)


# -- corrected builder_count: SPARE capacity, not total population -----------
# (docs/concept/timber_construction.md's "Deciding what to build, and who
# builds it" section's own "Spare capacity" paragraph -- a real bug fix:
# construction should only ever consume population BEYOND what farmer/
# hunter/fisher require, never compete with the survival occupations
# SettlementState.carrying_capacity itself depends on.)

## Seed 5 is a real, pinned hunter (see test_step_settlements_attempts_
## production_for_a_producer_occupation above) -- a real survival occupation,
## NpcProduction.PRODUCER_ITEM_BY_OCCUPATION's own subset. A settlement whose
## ENTIRE population works a real survival occupation has ZERO spare
## capacity, and must accrue ZERO construction labor even though
## household_count_for_settlement is genuinely nonzero -- the exact
## regression this fix closes (the old code passed TOTAL population here).
func test_construction_labor_only_advances_using_spare_capacity_not_total_population():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])
	manager.update(_berlin_tile)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(
		manager.household_count_for_settlement(settlement_id), 1,
		"sanity check on the fixture -- household_count_for_settlement is genuinely nonzero"
	)
	var project := manager.construction_project_store().start_project(
		chunk_coord, _construction_test_local_origin(), "sagewerk", "household:spare_capacity_test"
	)
	project.status = ConstructionProject.Status.IN_PROGRESS

	_unload_wait_and_reload(EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY * 5.0)

	assert_almost_eq(
		project.labor_hours_accumulated, 0.0, 0.0001,
		"a settlement whose entire population works a real survival occupation has zero SPARE " +
		"capacity, even though household_count_for_settlement is nonzero"
	)


# -- double-fix cancellation, wired at the real chunk-load boundary ----------
# (docs/concept/timber_construction.md's "Deciding what to build, and who
# builds it" section's own "Two real needs resolving each other" paragraph --
# SettlementBuildDecision, called from _load_chunk via
# _apply_settlement_build_decision.)

## A settlement's own queued "sagewerk" producer project is abandoned once a
## real sagewerk already exists nearby (the player independently brought/
## built the same real fix first) -- proven against the REAL chunk-scanned
## present_structure_ids (_present_structure_ids_for_settlement_chunk), not a
## literal Array a test hands the pure decision function directly.
func test_a_redundant_producer_project_is_abandoned_once_the_real_structure_already_exists_nearby():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	manager.update(_berlin_tile)
	var sagewerk_tile := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(5, 5)
	manager.build_at_global(sagewerk_tile.x, sagewerk_tile.y, "sagewerk")
	var redundant := manager.construction_project_store().start_project(
		chunk_coord, _construction_test_local_origin(), "sagewerk", "household:double_fix_test"
	)
	assert_eq(redundant.status, ConstructionProject.Status.PLANNED, "precondition")

	_unload_wait_and_reload(0.0)

	assert_eq(redundant.status, ConstructionProject.Status.ABANDONED)


# -- bulk structure stamping (see VillageRenderer, HouseBlueprint) ------------
#
# Stamping a whole house one build_at_global call per cell would repaint its
# owning chunk once PER CELL -- ruinous for a multi-house village at chunk
# load time. stamp_structure_at_global writes every cell directly and
# repaints once.

func test_stamp_structure_at_global_writes_every_ground_piece_cell():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	# Well inside the chunk, not tied to _berlin_tile's own (possibly
	# edge-adjacent) position -- see _stamp_test_hut's doc comment for why a
	# multi-cell footprint anchored on _berlin_tile itself is unsafe.
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(10, 10)
	var pieces := {
		Vector2i(0, 0): "wood_wall", Vector2i(1, 0): "wood_wall", Vector2i(0, 1): "wood_floor",
	}

	manager.stamp_structure_at_global(chunk_coord, origin, pieces, {})

	assert_eq(manager.modification_at_global(origin.x, origin.y), "wood_wall")
	assert_eq(manager.modification_at_global(origin.x + 1, origin.y), "wood_wall")
	assert_eq(manager.modification_at_global(origin.x, origin.y + 1), "wood_floor")


func test_stamp_structure_at_global_writes_roof_pieces_on_their_own_layer():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := _berlin_tile
	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "wood_floor"}, {Vector2i(0, 0): "wood_roof"})

	# Roofs aren't part of `modifications` (see Chunk.roof_modifications) --
	# the ground cell should still read as the floor, not the roof.
	assert_eq(manager.modification_at_global(origin.x, origin.y), "wood_floor")


func test_stamp_structure_at_global_gives_wall_cells_real_collision():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := _berlin_tile
	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "wood_wall"}, {})

	var expected_position := Vector2((origin.x + 0.5) * TerrainRenderer.TILE_SIZE, (origin.y + 0.5) * TerrainRenderer.TILE_SIZE)
	var found := false
	for child in entities_parent.get_children():
		if child is StaticBody2D and child.position == expected_position:
			found = true
	assert_true(found, "a stamped wall should block movement just like a hand-placed one")


func test_stamp_structure_at_global_does_nothing_for_an_unloaded_chunk():
	var success_context_before := entities_parent.get_child_count()
	manager.stamp_structure_at_global(Vector2i(9999, 9999), Vector2i(9999 * 32, 9999 * 32), {Vector2i(0, 0): "wood_wall"}, {})
	assert_eq(entities_parent.get_child_count(), success_context_before)


# -- roof layer: hidden while the player is indoors under it -----------------

func test_roof_pieces_paint_onto_the_roof_layer():
	var roof_layer := TileMapLayer.new()
	manager.set_roof_layer(roof_layer)
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	# origin_tile IS _berlin_tile, and the piece dicts are keyed by LOCAL
	# (footprint-relative) cells -- Vector2i.ZERO is the origin cell itself,
	# not `_berlin_tile` again (which would double-offset to 2x the tile).
	manager.stamp_structure_at_global(
		chunk_coord, _berlin_tile, {Vector2i.ZERO: "wood_floor"}, {Vector2i.ZERO: "wood_roof"}
	)

	assert_ne(roof_layer.get_cell_source_id(_berlin_tile), -1, "the roof should be painted onto the roof layer")
	roof_layer.free()


## The whole point of the separate layer: standing inside a room hides ITS
## roof (so the player can see themselves), while a roof the player is not
## under stays visible.
## Built well inside the chunk (not near _berlin_tile itself, which can sit
## close enough to a chunk edge for a 3x3 footprint to spill into the next
## chunk over -- stamp_structure_at_global silently drops cells outside its
## own chunk_coord, see its own doc comment, which then breaks the ring's
## enclosure and was a real false-negative this test caught).
func _stamp_test_hut(chunk_coord: Vector2i) -> Vector2i:
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(10, 10)
	var ground := {}
	for x in range(0, 3):
		for y in range(0, 3):
			var local := Vector2i(x, y)
			var edge := x == 0 or y == 0 or x == 2 or y == 2
			ground[local] = "wood_wall" if edge else "wood_floor"
	ground[Vector2i(1, 0)] = "wood_door"
	manager.stamp_structure_at_global(chunk_coord, origin, ground, {Vector2i(1, 1): "wood_roof"})
	return origin + Vector2i(1, 1)  # the hut's one interior/floor cell, globally


func test_update_hides_the_roof_over_the_room_the_player_is_standing_in():
	var roof_layer := TileMapLayer.new()
	manager.set_roof_layer(roof_layer)
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var interior_tile := _stamp_test_hut(chunk_coord)
	assert_ne(roof_layer.get_cell_source_id(interior_tile), -1, "precondition: the roof is visible before entering")

	manager.update(interior_tile)  # the player's own tile IS the hut's interior cell

	assert_eq(roof_layer.get_cell_source_id(interior_tile), -1, "the roof over the player's own room should be hidden")
	roof_layer.free()


func test_update_shows_the_roof_again_once_the_player_leaves_the_room():
	var roof_layer := TileMapLayer.new()
	manager.set_roof_layer(roof_layer)
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var interior_tile := _stamp_test_hut(chunk_coord)
	manager.update(interior_tile)  # enters the room, hides the roof
	assert_eq(roof_layer.get_cell_source_id(interior_tile), -1, "precondition: hidden while inside")

	manager.update(interior_tile + Vector2i(5, 5))  # steps back outside the room

	assert_ne(roof_layer.get_cell_source_id(interior_tile), -1, "leaving the room should show the roof again")
	roof_layer.free()


# -- geology: a real per-chunk Strata sim exists for every loaded chunk ------
# (see docs/concept/geology.md). Cave-entrance discovery/reveal itself is
# exercised directly against GeologyRenderer (test_geology_renderer.gd) --
# entrances are far too sparse (~1 in 500 mountain tiles) to reliably land
# inside a small, fast real-elevation-generated test chunk, so these smoke
# tests only cover what every loaded chunk (any biome) guarantees: a real
# Strata instance exists, and update()'s new geology-reveal step never
# crashes even when nothing is nearby.

func test_loading_a_chunk_creates_a_real_topsoil_strata_instance():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var strata := manager.strata_at(chunk_coord)
	assert_not_null(strata, "a loaded chunk should have a real Strata instance")
	assert_eq(strata.layer, Strata.LAYER_TOPSOIL_REGOLITH)


func test_unloading_a_chunk_clears_its_strata():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_not_null(manager.strata_at(chunk_coord), "precondition: chunk is loaded")

	# Walk far enough away that the original chunk falls outside UNLOAD_RADIUS.
	var far_tile := _berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0)
	manager.update(far_tile)

	assert_null(manager.strata_at(chunk_coord), "an unloaded chunk's strata should be cleared")


func test_update_does_not_crash_the_geology_reveal_step_away_from_any_entrance():
	# Berlin is inland, non-mountain -- exercises the "nothing nearby" path
	# through _update_geology_reveal/_nearby_cave_entrance every frame the
	# rest of update() already runs, the same smoke-test shape the roof
	# visibility tests above give _update_roof_visibility.
	manager.update(_berlin_tile)
	manager.update(_berlin_tile + Vector2i(1, 0))
	manager.update(_berlin_tile)
	assert_true(true, "update() should run the geology reveal step without error")


func _chunk_coord_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


## Deletes a modifications file a test's own unload just persisted to real
## user:// disk (mirrors this file's existing cleanup convention, e.g.
## test_reloading_a_chunk_restores_collision_for_a_persisted_wall) -- so a
## sagewerk built on the shared _berlin_tile spawn point for one test does
## not leak into unrelated tests that load the same tile later.
func _remove_persisted_modifications(chunk_coord: Vector2i) -> void:
	var path := "user://chunk_modifications/%d_%d.bin" % [chunk_coord.x, chunk_coord.y]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _child_instance_ids(parent: Node2D) -> Array[int]:
	var ids: Array[int] = []
	for child in parent.get_children():
		ids.append(child.get_instance_id())
	return ids


# -- a bird's catch must take a real fish -----------------------------------
#
# record_fish_catch_near only decremented a float, so a successful dive
# removed nothing visible: no fish disappeared, nothing to see. The player's
# own catch has always removed the actual FishMarker; a bird's now does too.

func test_a_bird_catch_removes_an_actual_fish_from_the_water():
	var fish_scene := preload("res://src/rendering/fish_marker.gd")
	var fish = fish_scene.new()
	fish.position = Vector2(40, 40)
	fish.species = "trout"
	creatures_parent.add_child(fish)
	manager._loaded_fish[Vector2i(0, 0)] = [fish]

	var taken: bool = manager.record_fish_catch_near(Vector2(42, 42), 1.0)

	assert_true(taken, "a catch within reach should take a fish")
	assert_eq(manager._loaded_fish[Vector2i(0, 0)].size(), 0, "the fish should leave the water")


func test_a_bird_catch_with_no_fish_in_reach_takes_nothing():
	manager._loaded_fish[Vector2i(0, 0)] = []
	assert_false(manager.record_fish_catch_near(Vector2(40, 40), 1.0))


# -- fish flee from a wading player/animal -----------------------------------
#
# "make them swim away from player and animals who wade near them" --
# startle_fish_near_waders reuses the existing FishMarker.bolt_from (already
# built for the kingfisher-miss case above) and takes an already
# water-filtered wader list (see river_wader_positions, tested elsewhere in
# this file) -- it does no water-checking of its own, only distance +
# bolt_from, the same single-threat shape startle_fish_near already has,
# generalized to several candidate threats at once. See docs/concept/
# ecosystem_dynamics.md#a-shoal-finds-its-shape.

func test_startle_fish_near_waders_bolts_a_fish_within_radius():
	var fish_scene := preload("res://src/rendering/fish_marker.gd")
	var fish = fish_scene.new()
	fish.position = Vector2(100, 100)
	creatures_parent.add_child(fish)
	manager._loaded_fish[Vector2i(0, 0)] = [fish]

	manager.startle_fish_near_waders(PackedVector2Array([Vector2(105, 100)]))

	assert_true(fish.is_bolting(), "a fish near a wading threat should bolt")


func test_startle_fish_near_waders_ignores_a_fish_out_of_radius():
	var fish_scene := preload("res://src/rendering/fish_marker.gd")
	var fish = fish_scene.new()
	fish.position = Vector2(100, 100)
	creatures_parent.add_child(fish)
	manager._loaded_fish[Vector2i(0, 0)] = [fish]

	manager.startle_fish_near_waders(PackedVector2Array([Vector2(1000, 1000)]))

	assert_false(fish.is_bolting(), "a fish far from every wader should not bolt")


func test_startle_fish_near_waders_with_no_waders_does_nothing():
	var fish_scene := preload("res://src/rendering/fish_marker.gd")
	var fish = fish_scene.new()
	fish.position = Vector2(100, 100)
	creatures_parent.add_child(fish)
	manager._loaded_fish[Vector2i(0, 0)] = [fish]

	manager.startle_fish_near_waders(PackedVector2Array())

	assert_false(fish.is_bolting())


func test_startle_fish_near_waders_treats_each_fish_independently():
	var fish_scene := preload("res://src/rendering/fish_marker.gd")
	var near_fish = fish_scene.new()
	near_fish.position = Vector2(100, 100)
	creatures_parent.add_child(near_fish)
	var far_fish = fish_scene.new()
	far_fish.position = Vector2(5000, 5000)
	creatures_parent.add_child(far_fish)
	manager._loaded_fish[Vector2i(0, 0)] = [near_fish, far_fish]

	manager.startle_fish_near_waders(PackedVector2Array([Vector2(105, 100)]))

	assert_true(near_fish.is_bolting(), "the fish near the wader should bolt")
	assert_false(far_fish.is_bolting(), "an unrelated fish elsewhere should not")


# -- tuft sprites must stay at their intended world size ---------------------
#
# _sync_grass_sprites set a tuft's scale once at creation (SPRITE_SCALE *
# TUFT_WORLD_SCALE -- a clump reading roughly one tile wide), but every
# refresh afterward OVERWROTE that scale with just the growth fraction. A
# mature patch (growth 1.0, which map-seeded grass starts at) rendered at
# scale 1.0 -- the full oversized art canvas -- instead of the intended
# quarter size: a giant flat rectangle instead of a small tuft (reported:
# "square planty entities which look bad").

func _grass_tuft_seed(chunk_coord: Vector2i, cell: Vector2i) -> int:
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	return hash("%d_%d_grass_tuft" % [origin.x + cell.x, origin.y + cell.y])


## Grass renders through one MultiMeshInstance2D per Y-band (GPU-instanced,
## not one Sprite2D per card - see IllustratedGrassPatch.BAND_COUNT and
## docs/concept/long_grass.md for why: individual per-card nodes hit
## thousands of alpha-blended draw calls at real chunk density and were
## reported live as "super laggy"). Per-instance transform/color content
## (world scale, root position) is exercised at the unit level in
## test_illustrated_grass_patch.gd's instances_for_cells tests instead of
## here: MultiMesh per-instance data needs a real renderer to read back
## (Godot's headless dummy renderer doesn't back it), so this file - run
## headless - checks the wiring this integration is actually responsible
## for: which cells land in which band's draw call.
func test_grass_renders_through_banded_multimesh_instances_not_per_cell_nodes():
	manager.update(_berlin_tile)
	var found_any_band := false
	for chunk_coord in manager._grass_sprites.keys():
		for band in manager._grass_sprites[chunk_coord]:
			assert_true(band is int, "keys are band indices now, not cell Vector2i")
			var mmi = manager._grass_sprites[chunk_coord][band]
			assert_true(mmi is MultiMeshInstance2D)
			assert_eq(mmi.get_parent(), manager._entities_parent, "each band's draw call is a real child of the shared y-sorted entities parent")
			assert_gt(mmi.multimesh.instance_count, 0)
			# SUPERSEDED (2026-08-27): used to assert every band's instance
			# count was a clean multiple of CARD_COUNT, back when a whole
			# cell's cards always stayed together in one band. Now that
			# banding is per-CARD (see IllustratedGrassPatch.cards_for_cell),
			# a cell straddling a band boundary can genuinely split its
			# CARD_COUNT cards across two adjacent bands -- a real,
			# intended consequence of the fix, not something to assert away.
			found_any_band = true
	assert_true(found_any_band, "precondition: Berlin's grassland seeded at least one patch")


## Every card grouped into one band's draw call must actually belong there
## by IllustratedGrassPatch's own band math - the whole point of banding is
## that a band's Y-sort position is representative of the cards inside it.
## SUPERSEDED (2026-08-27): used to bucket by a whole CELL's own raw row
## (band_index_for_local_y(cell.y, ...), a flat CARD_COUNT per cell) --
## now mirrors _sync_grass_sprites' own real per-CARD bucketing (see its
## own doc comment), since a cell's cards can genuinely split across two
## bands once their own real offset-adjusted position crosses a boundary.
func test_every_bands_instance_count_matches_its_own_cells_card_total():
	manager.update(_berlin_tile)
	var half_span: Vector2 = manager._visible_half_span_tiles()
	var player_tile: Vector2i = manager._disturbance_center_tile
	var checked_any := false
	for chunk_coord: Vector2i in manager._grass_sprites.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		var origin: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE
		var expected_by_band: Dictionary = {}
		for cell in sim.get_patch_cells():
			# Matches _sync_grass_sprites' own tile-precise view+buffer
			# cutoff: a chunk passing the coarser chunk-level _decorates
			# gate does not mean every one of its cells is drawn.
			var tile: Vector2i = origin + cell
			if not DecorationLod.keeps_decoration_tile(tile, player_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
				continue
			var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
			var cell_spec := {
				"seed": seed_value,
				"ground_position": Vector2(
					(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
				),
				"growth": sim.get_growth(cell),
			}
			for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
				var local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
				var band := IllustratedGrassPatch.band_index_for_local_y(local_row, EarthChunkManager.CHUNK_SIZE)
				expected_by_band[band] = int(expected_by_band.get(band, 0)) + 1
		for band in manager._grass_sprites[chunk_coord]:
			var mmi: MultiMeshInstance2D = manager._grass_sprites[chunk_coord][band]
			assert_eq(mmi.multimesh.instance_count, expected_by_band.get(band, 0))
			checked_any = true
	assert_true(checked_any, "precondition: Berlin's grassland seeded at least one patch")


## The actual point of the tile-precise cutoff: a decorating chunk (one that
## already passed the coarser chunk-level _decorates gate) must still be
## able to have cells that AREN'T drawn, once they're further from the
## player than half_span+buffer -- otherwise this change did nothing.
func test_cells_beyond_the_view_buffer_are_not_drawn_even_in_a_decorating_chunk():
	manager.update(_berlin_tile)
	var half_span: Vector2 = manager._visible_half_span_tiles()
	var player_tile: Vector2i = manager._disturbance_center_tile
	var found_a_filtered_cell := false
	for chunk_coord: Vector2i in manager._grass_sprites.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		var origin: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE
		for cell in sim.get_patch_cells():
			if not DecorationLod.keeps_decoration_tile(origin + cell, player_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
				found_a_filtered_cell = true
				break
		if found_a_filtered_cell:
			break
	assert_true(found_a_filtered_cell, "precondition: at least one loaded/decorating chunk has a cell outside the tile-precise view window (otherwise this test cannot exercise the cutoff at all)")


## Walking far enough that a specific cell falls outside the view+buffer
## window must actually drop its cards -- "loaded/unloaded as the player
## walks", not just "smaller once, forever after".
func test_a_cell_drops_out_when_the_player_walks_far_enough_away():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._grass_sprites.keys()[0]
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var a_cell: Vector2i = sim.get_patch_cells()[0]
	var a_tile := origin + a_cell

	# Stand right on the cell: it must be drawn (precondition). a_cell's own
	# CARD_COUNT cards can land in more than one real band (per-card
	# banding, not per-cell -- see this file's other SUPERSEDED notes), so
	# find every real band they occupy rather than assuming a single naive
	# one derived from the cell's own raw row.
	#
	# update() alone only marks a grass resync as DUE (see
	# _sync_decoration_and_grass_tracking's own doc comment) -- chunk_coord
	# was already loaded by the very first update(_berlin_tile) above, so
	# this second update() does not re-enter _load_chunk's synchronous
	# _sync_grass_sprites call. Without an explicit step_tall_grass() here,
	# _grass_sprites[chunk_coord] would still reflect that FIRST,
	# _berlin_tile-centered sync -- which a_cell (an arbitrary patch cell,
	# not necessarily near Berlin at all) may never have been part of in the
	# first place, making "precondition: standing on the cell, its real
	# bands have cards" false regardless of banding. Mirrors
	# test_walking_within_the_same_chunk_resyncs_the_grass_view_without_
	# waiting_for_the_refresh_timer's own real per-frame cadence.
	manager.update(a_tile)
	manager.step_tall_grass(0.0)
	var a_seed_value := hash("%d_%d_grass_tuft" % [a_tile.x, a_tile.y])
	var a_cell_spec := {
		"seed": a_seed_value,
		"ground_position": Vector2(
			(a_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (a_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
		),
		"growth": sim.get_growth(a_cell),
	}
	var real_bands: Array[int] = []
	for card in IllustratedGrassPatch.cards_for_cell(a_cell_spec):
		var local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
		var card_band := IllustratedGrassPatch.band_index_for_local_y(local_row, EarthChunkManager.CHUNK_SIZE)
		if not real_bands.has(card_band):
			real_bands.append(card_band)

	var near_count := 0
	for band in real_bands:
		if manager._grass_sprites[chunk_coord].has(band):
			near_count += manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	assert_gt(near_count, 0, "precondition: standing on the cell, its real bands have cards")

	# Walk far enough away (well beyond any reasonable half_span+buffer)
	# that the chunk itself still decorates (a village-sized hop, not a
	# world away) but this one cell no longer falls in the view window. Same
	# reasoning as above: update() alone only marks the resync due.
	manager.update(a_tile + Vector2i(0, 200))
	manager.step_tall_grass(0.0)
	if not manager._grass_sprites.has(chunk_coord):
		assert_true(true, "the whole chunk dropped entirely once nothing in it was in view -- also correct")
		return
	var far_count := 0
	for band in real_bands:
		if manager._grass_sprites[chunk_coord].has(band):
			far_count += manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	assert_lt(far_count, near_count, "walking away from the cell must reduce (or zero) its real bands' card count")


## The tile-precise view+buffer window is far tighter than the chunk-level
## _decorates gate (CHUNK_SIZE=32 tiles square vs. a camera view a fraction
## of that) -- a player can walk many tiles, bringing new ground into view,
## without ever crossing into a new CHUNK and tripping the existing
## chunk-boundary immediate-resync trigger. Reported live: "the blades load
## way too late and the player walks into a new area without any blades
## which then suddenly appear". update() marks the resync due immediately
## (mirroring the chunk-boundary trigger just above it in the source) on
## tile-level movement alone, so the very next step_tall_grass call -- real
## gameplay's own per-frame cadence (see world.gd's _step_ecology_batch),
## driven here with a 0.0 delta since update() already primed the
## accumulator past its threshold -- picks it up without waiting out a full
## GRASS_REFRESH_INTERVAL.
func test_walking_within_the_same_chunk_resyncs_the_grass_view_without_waiting_for_the_refresh_timer():
	manager.update(_berlin_tile)
	manager.step_tall_grass(0.0)
	var half_span: Vector2 = manager._visible_half_span_tiles()

	# Berlin's OWN chunk (not just any decorating chunk) -- keeps the whole
	# walk inside one chunk so the existing chunk-boundary trigger can never
	# be what makes this test pass.
	var chunk_coord: Vector2i = Vector2i.ZERO
	var found_chunk := false
	for candidate: Vector2i in manager._grass_sims.keys():
		var candidate_origin: Vector2i = candidate * EarthChunkManager.CHUNK_SIZE
		if _berlin_tile.x >= candidate_origin.x and _berlin_tile.x < candidate_origin.x + EarthChunkManager.CHUNK_SIZE \
				and _berlin_tile.y >= candidate_origin.y and _berlin_tile.y < candidate_origin.y + EarthChunkManager.CHUNK_SIZE:
			chunk_coord = candidate
			found_chunk = true
			break
	assert_true(found_chunk, "precondition: Berlin's own chunk has a loaded grass sim")

	var sim: TallGrass = manager._grass_sims[chunk_coord]
	var origin: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE
	var far_cell = null
	for cell in sim.get_patch_cells():
		var tile: Vector2i = origin + cell
		if not DecorationLod.keeps_decoration_tile(tile, _berlin_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
			far_cell = cell
			break
	if far_cell == null:
		assert_true(true, "precondition: every patch in Berlin's own chunk already sits inside the view window -- nothing to walk into")
		return
	var far_tile: Vector2i = origin + far_cell

	# Walk right onto the far cell -- still inside chunk_coord the whole
	# time (far_tile was built from THIS chunk's own origin), so this never
	# trips the old chunk-boundary trigger. The 0.0-delta step mirrors real
	# gameplay's own per-frame step_tall_grass call (world.gd's
	# _step_ecology_batch runs it unconditionally every frame right after
	# update()) -- it only actually does anything because update() just
	# primed the accumulator past its threshold.
	manager.update(far_tile)
	manager.step_tall_grass(0.0)

	# The view window is PLAYER-relative and just re-centred on far_tile, so
	# the whole set of drawn cells reshuffles rather than far_cell's own band
	# simply growing by one -- recompute what SHOULD be drawn now, the same
	# way _sync_grass_sprites itself does (mirrors this file's own
	# test_every_bands_instance_count_matches_its_own_cells_card_total), and
	# require the real multimesh to already match it. A stale sync would
	# still reflect the OLD, _berlin_tile-relative window instead.
	# Mirrors _sync_grass_sprites' own REAL per-CARD bucketing (see its own
	# doc comment) -- SUPERSEDED (2026-08-27) from a cell-level shortcut
	# (band_index_for_local_y(cell.y, ...), one flat CARD_COUNT per cell)
	# now that a cell's own cards can genuinely split across two bands.
	var expected_by_band: Dictionary = {}
	for cell in sim.get_patch_cells():
		var tile: Vector2i = origin + cell
		if not DecorationLod.keeps_decoration_tile(tile, far_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
			continue
		var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
		var cell_spec := {
			"seed": seed_value,
			"ground_position": Vector2(
				(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
			),
			"growth": sim.get_growth(cell),
		}
		for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
			var local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
			var card_band := IllustratedGrassPatch.band_index_for_local_y(local_row, EarthChunkManager.CHUNK_SIZE)
			expected_by_band[card_band] = int(expected_by_band.get(card_band, 0)) + 1

	# far_cell's own real cards (not the naive raw-row shortcut, which can
	# land a band off from where a card's real offset-adjusted position
	# actually falls -- see this file's other SUPERSEDED notes above) must
	# have contributed a nonzero count to at least one of the bands
	# expected_by_band just computed.
	var far_seed_value := hash("%d_%d_grass_tuft" % [far_tile.x, far_tile.y])
	var far_cell_spec := {
		"seed": far_seed_value,
		"ground_position": Vector2(
			(far_tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (far_tile.y + 0.5) * TerrainRenderer.TILE_SIZE
		),
		"growth": sim.get_growth(far_cell),
	}
	var far_bands_total := 0
	for card in IllustratedGrassPatch.cards_for_cell(far_cell_spec):
		var far_local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
		var far_card_band := IllustratedGrassPatch.band_index_for_local_y(far_local_row, EarthChunkManager.CHUNK_SIZE)
		far_bands_total += int(expected_by_band.get(far_card_band, 0))
	assert_gt(far_bands_total, 0, "precondition: far_cell's own real cards' bands should now expect a nonzero count, standing right on it")

	var after: Dictionary = manager._grass_sprites.get(chunk_coord, {})
	for band in expected_by_band:
		assert_true(after.has(band), "band %d must exist once it has cells in the new view window" % band)
		if after.has(band):
			assert_eq(after[band].multimesh.instance_count, expected_by_band[band], "band %d must already match the NEW player-relative view, not a stale one" % band)


## The whole reason bands exist instead of one draw call per chunk: distinct
## bands must carry distinct Y-sort positions, or grass would sort as one
## rigid block against the player instead of tracking depth through a field.
func test_different_bands_carry_distinct_y_sort_positions():
	manager.update(_berlin_tile)
	var checked_any_chunk_with_multiple_bands := false
	for chunk_coord in manager._grass_sprites.keys():
		var bands: Dictionary = manager._grass_sprites[chunk_coord]
		if bands.size() < 2:
			continue
		checked_any_chunk_with_multiple_bands = true
		var ys := {}
		for band in bands:
			var mmi: MultiMeshInstance2D = bands[band]
			ys[snappedf(mmi.position.y, 0.01)] = true
		assert_eq(ys.size(), bands.size(), "each band must carry its own distinct Y-sort position")


## /village dev-console command's discovery half (see World._handle_village_
## command, VillageFinder) -- finds a real settlement's real teleport target
## against real terrain generation, not a stub.
func test_find_nearest_village_returns_a_real_landmark_position():
	var found: Variant = manager.find_nearest_village(_berlin_tile)
	assert_not_null(found, "Berlin's surroundings should contain a settlement within the search radius")
	assert_true(found is Vector2)


## Calling it twice from the same tile must find the SAME settlement --
## deterministic discovery, not a fresh random pick each time.
func test_find_nearest_village_is_deterministic():
	var first: Variant = manager.find_nearest_village(_berlin_tile)
	var second: Variant = manager.find_nearest_village(_berlin_tile)
	assert_eq(first, second)


# -- earthworms (see docs/concept/soil_fauna.md) ----------------------------
#
# The soil-fauna tier a robin feeds on, wired the whole way: per-chunk sims
# created on load, stepped centrally, rendered as sprites, queried and
# consumed by birds, and dropped on unload. DesertScrub/TundraLichen shipped
# as fully-tested sims that nothing in live gameplay ever calls -- these tests
# exist so this one cannot.

const EarthwormPatch = preload("res://src/world/earthworm_patch.gd")
const ProceduralWormSprite = preload("res://src/rendering/procedural_worm_sprite.gd")


## Brings every worm in every loaded chunk to the surface, so the queries
## below have something deterministic to find regardless of the live weather
## rolled for this region on this simulated day.
func _surface_all_worms() -> void:
	for patch in manager._worm_patches.values():
		patch.set_conditions(1.0, 1.0)
	for i in 40:
		for patch in manager._worm_patches.values():
			patch.advance(0.5)


## Sends every worm back down, the way a frost or a dry spell would.
func _burrow_all_worms() -> void:
	for patch in manager._worm_patches.values():
		patch.set_conditions(0.0, 0.0)
	for i in 40:
		for patch in manager._worm_patches.values():
			patch.advance(0.5)


## Any (chunk_coord, cell) that currently has a worm at the surface.
## A surfaced worm in a chunk that is actually DRAWN. Decoration is only built
## for chunks near the player (see DecorationLod), so a worm picked from an
## arbitrary loaded chunk may correctly have no sprite -- which is the
## behaviour, not a bug, but makes for a confusing precondition failure.
func _a_surfaced_worm() -> Array:
	for chunk_coord in manager._worm_patches:
		if not manager._decorates(chunk_coord):
			continue
		var patch: EarthwormPatch = manager._worm_patches[chunk_coord]
		for cell in patch.worm_cells():
			if patch.is_surfaced(cell):
				return [chunk_coord, cell]
	return []


func _pixel_for(chunk_coord: Vector2i, cell: Vector2i) -> Vector2:
	var tile: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
	return Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5) * float(TerrainRenderer.TILE_SIZE)


func _rendered_worm_count() -> int:
	var total := 0
	for sprites in manager._worm_sprites.values():
		total += sprites.size()
	return total


func test_loading_chunks_creates_worm_patches():
	manager.update(_berlin_tile)
	assert_gt(manager._worm_patches.size(), 0, "loaded chunks should have worm sims")


func test_berlins_soil_actually_holds_worms():
	manager.update(_berlin_tile)
	var burrows := 0
	for patch in manager._worm_patches.values():
		burrows += patch.worm_cells().size()
	assert_gt(burrows, 0, "a temperate grassland/forest region should have earthworms")


func test_worms_near_finds_a_surfaced_worm():
	manager.update(_berlin_tile)
	_surface_all_worms()
	var found := _a_surfaced_worm()
	assert_gt(found.size(), 0, "precondition: at least one worm at the surface")
	var pixel := _pixel_for(found[0], found[1])
	var worms := manager.worms_near(pixel, 2)
	assert_gt(worms.size(), 0, "a worm underfoot should be findable")
	var positions := []
	for worm in worms:
		positions.append(worm["position"])
	assert_true(positions.has(pixel), "and reported at its own tile centre")


## Only what is actually up: a burrowed worm is not food.
func test_worms_near_ignores_worms_that_are_still_underground():
	manager.update(_berlin_tile)
	_burrow_all_worms()
	var origin := _pixel_for(_chunk_coord_for_tile(_berlin_tile), Vector2i(0, 0))
	assert_eq(manager.worms_near(origin, 30).size(), 0, "frozen ground offers a bird nothing")


func test_worms_near_respects_its_radius():
	manager.update(_berlin_tile)
	_surface_all_worms()
	var found := _a_surfaced_worm()
	var pixel := _pixel_for(found[0], found[1])
	for worm in manager.worms_near(pixel, 3):
		var offset: Vector2 = worm["position"] - pixel
		assert_lte(
			maxf(absf(offset.x), absf(offset.y)) / float(TerrainRenderer.TILE_SIZE), 3.5,
			"nothing outside the radius should be reported"
		)


func test_taking_a_worm_removes_it_from_the_world():
	manager.update(_berlin_tile)
	_surface_all_worms()
	var found := _a_surfaced_worm()
	var patch: EarthwormPatch = manager._worm_patches[found[0]]
	var pixel := _pixel_for(found[0], found[1])
	assert_true(manager.take_worm_at(pixel), "a bird standing on a worm gets it")
	assert_false(patch.is_surfaced(found[1]), "and the worm is gone")
	assert_false(manager.take_worm_at(pixel), "it cannot be eaten twice")


func test_taking_a_worm_where_there_is_none_fails_rather_than_erroring():
	manager.update(_berlin_tile)
	assert_false(manager.take_worm_at(Vector2(-9000000, -9000000)))


# -- fruit_near / take_fruit_at / try_plant_seed_at (bird endozoochory) -------
#
# The bird-fruit-eating half of docs/concept/flora.md#bird-endozoochory: a
# fruit-eating bird (see AmbientFlyerMarker.fruit_world) looks for fallen
# named-species fruit lying on the ground -- REAL DroppedItem nodes in
# World's own GroundItems container (set_ground_items), the same nodes
# WorldItemBus.item_dropped ultimately spawns -- eats one, and can later
# plant a sapling elsewhere. Mirrors worms_near/take_worm_at's shape exactly.

func _make_ground_fruit(position: Vector2, id: String) -> DroppedItem:
	var item := DroppedItem.new()
	item.item_stack = ItemStack.new(Item.new(id, id.capitalize(), "food", 20))
	item.position = position
	return item


func test_fruit_near_is_empty_when_ground_items_were_never_wired_up():
	assert_eq(manager.fruit_near(Vector2.ZERO, 5).size(), 0)


func test_fruit_near_finds_a_named_species_ground_item():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "cherry"))

	var found := manager.fruit_near(pixel, 5)
	assert_eq(found.size(), 1)
	assert_eq(found[0]["species"], "cherry")
	assert_eq(found[0]["position"], pixel)
	ground_items.free()


## Only named tree-fruit species count -- a dropped sword or raw meat is not
## something a bird can swallow and disperse.
func test_fruit_near_ignores_non_fruit_ground_items():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "meat"))

	assert_eq(manager.fruit_near(pixel, 5).size(), 0)
	ground_items.free()


func test_fruit_near_respects_its_radius():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var far := pixel + Vector2(999999.0, 0.0)
	ground_items.add_child(_make_ground_fruit(far, "apple"))

	assert_eq(manager.fruit_near(pixel, 5).size(), 0)
	ground_items.free()


func test_take_fruit_at_removes_the_item_and_returns_its_species():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var fruit := _make_ground_fruit(pixel, "walnut")
	ground_items.add_child(fruit)

	var species := manager.take_fruit_at(pixel)
	assert_eq(species, "walnut")
	assert_true(fruit.is_queued_for_deletion())
	assert_eq(manager.take_fruit_at(pixel), "", "it cannot be eaten twice")
	ground_items.free()


func test_take_fruit_at_where_there_is_none_fails_rather_than_erroring():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	assert_eq(manager.take_fruit_at(Vector2(-9000000, -9000000)), "")
	ground_items.free()


# -- harvest_peak_fruit_near: direct-from-the-tree harvest (docs/concept/
# progression.md "Ecological literacy") --------------------------------------
#
# Distinct from fruit_near/take_fruit_at above: those cover WINDFALL already
# on the ground. This is picking straight off a tree that still carries real
# hanging fruit (FruitingModel.hanging_at > 0) -- the only harvest event that
# can ever land inside FruitingModel's real "peak" plateau, since windfall by
# definition has already left it (see fruiting_model.gd's is_peak_ripe).

const ForageScheduler = preload("res://src/gameplay/forage_scheduler.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")

## An integer pixel position whose deterministic genome (ForageScheduler.
## genome_for, position-keyed -- no stored per-tree genome anywhere in this
## codebase) resolves to `species_id` with a real nonzero crop. Same
## brute-force-a-real-instance idiom test_fruiting_model.gd's own
## _genome_for uses, just keyed by POSITION instead of a seed, since that is
## what the real per-tree lookup is keyed by.
func _position_for_species(species_id: String) -> Vector2:
	var scheduler := ForageScheduler.new()
	for step in 4000:
		var position := Vector2(step * 37, step * 53)
		var genome := scheduler.genome_for(position)
		if TreeSpecies.species_for_bias(genome.species_bias) != species_id:
			continue
		if FruitingModel.new().crop_potential(genome) <= 0:
			continue
		return position
	return Vector2.ZERO


func test_harvest_peak_fruit_near_finds_nothing_with_no_trees_loaded():
	assert_true(manager.harvest_peak_fruit_near(Vector2.ZERO, 10000.0).is_empty())


func test_harvest_peak_fruit_near_finds_nothing_out_of_range():
	var tree := Node2D.new()
	tree.position = _position_for_species("apple")
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	assert_true(manager.harvest_peak_fruit_near(tree.position + Vector2(99999, 0), 10.0).is_empty())


func test_harvest_peak_fruit_near_finds_nothing_before_anything_has_ripened():
	var tree := Node2D.new()
	tree.position = _position_for_species("apple")
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	manager.set_world_age_seconds(0.0)  # start of the bearing cycle: still growing
	assert_true(manager.harvest_peak_fruit_near(tree.position, 10.0).is_empty())


## The real, tested claim item 3 of the task asks for: a PEAK-timed harvest of
## a tree reports is_peak true, an off-peak-but-still-hanging harvest of the
## SAME tree reports is_peak false -- both read against the real FruitingModel
## window for this tree's own real (position-derived) genome, not a
## hardcoded assumption about when peak falls.
func test_harvest_peak_fruit_near_reports_the_real_peak_state():
	var species_id := "apple"
	var tree := Node2D.new()
	tree.position = _position_for_species(species_id)
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	var scheduler := ForageScheduler.new()
	var genome := scheduler.genome_for(tree.position)
	var model := FruitingModel.new()
	var warmth: float = manager._warmth_at_pixel(tree.position)
	# Window boundaries (grow_end/fall_start/fall_end, as YEAR FRACTIONS) don't
	# depend on yield_multiplier/ripening_multiplier -- see fruiting_model.gd's
	# own doc comments on _cycle_length/_window_for -- so computing them here
	# without TreeSpecies' multipliers still matches what
	# harvest_peak_fruit_near computes internally with them.
	var window: Dictionary = model._window_for(genome, warmth)

	# -- at genuine peak (mid-plateau) --
	manager.set_world_age_seconds(
		(float(window.grow_end) + float(window.fall_start)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	var at_peak: Dictionary = manager.harvest_peak_fruit_near(tree.position, 10.0)
	assert_eq(at_peak.get("species_id", ""), species_id)
	assert_true(at_peak.get("is_peak", false), "expected mid-plateau to read as genuine peak ripeness")

	# -- off-peak, but still hanging (mid-abscission) --
	manager.set_world_age_seconds(
		(float(window.fall_start) + float(window.fall_end)) / 2.0 * FruitingModel.BEARING_CYCLE_SECONDS
	)
	var off_peak: Dictionary = manager.harvest_peak_fruit_near(tree.position, 10.0)
	assert_eq(off_peak.get("species_id", ""), species_id)
	assert_false(off_peak.get("is_peak", true), "expected mid-abscission to no longer read as peak")


func test_try_plant_seed_at_fails_when_the_chunk_is_not_loaded():
	var far_away_pixel := Vector2(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE) * TerrainRenderer.TILE_SIZE
	assert_false(manager.try_plant_seed_at(far_away_pixel, "cherry"))


## Trees establish in forest/rainforest, not every biome (see
## SeedEndozoochory.can_root_in) -- a seed dropped on grassland/ocean/etc. is
## simply lost, same "not every drop succeeds" honesty flower dispersal
## already models.
func test_try_plant_seed_at_fails_outside_forest_or_rainforest():
	manager.update(_berlin_tile)
	var found := false
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var tile := _berlin_tile + Vector2i(dx, dy)
			var biome := manager.biome_at_global(tile.x, tile.y)
			if biome != "" and not ["forest", "rainforest"].has(biome):
				found = true
				assert_false(manager.try_plant_seed_at(Vector2(tile) * TerrainRenderer.TILE_SIZE, "cherry"))
				break
		if found:
			break
	assert_true(found, "precondition: some non-forest biome should be loaded near Berlin")


func test_try_plant_seed_at_plants_a_sapling_somewhere_forested_near_berlin():
	manager.update(_berlin_tile)
	var before := entities_parent.get_child_count()
	var planted := false
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var tile := _berlin_tile + Vector2i(dx, dy)
			if ["forest", "rainforest"].has(manager.biome_at_global(tile.x, tile.y)):
				var pixel := Vector2(tile) * TerrainRenderer.TILE_SIZE
				if manager.try_plant_seed_at(pixel, "cherry"):
					planted = true
					break
		if planted:
			break
	assert_true(planted, "should be able to plant a tree seed somewhere forested near Berlin")
	assert_gt(entities_parent.get_child_count(), before)


## The sprite layer diffs against the sim, so what the player sees is exactly
## what a bird can eat.
##
## Scoped to chunks that are actually DRAWN: decoration is only built near the
## player (see DecorationLod), so a distant chunk legitimately carries no worm
## sprites. The invariant this is protecting is about what the player can see,
## and it still holds everywhere they can see anything.
func test_a_sprite_is_rendered_for_every_surfaced_worm_and_only_those():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var checked := 0
	for chunk_coord in manager._worm_patches:
		if not manager._decorates(chunk_coord):
			continue
		checked += 1
		var patch: EarthwormPatch = manager._worm_patches[chunk_coord]
		var sprites: Dictionary = manager._worm_sprites[chunk_coord]
		for cell in patch.worm_cells():
			assert_eq(
				sprites.has(cell), patch.is_surfaced(cell),
				"sprite presence must match what is actually at the surface"
			)
	assert_gt(checked, 0, "precondition: at least one drawn chunk has worms")


func test_worm_sprites_are_removed_when_the_worms_go_back_down():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	assert_gt(_rendered_worm_count(), 0, "precondition: some worms were rendered")
	_burrow_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	assert_eq(_rendered_worm_count(), 0, "a frost should clear the lawn")


## The art-resolution trap this project has hit twice: a sprite world size
## must come from a world constant, never from its canvas dimensions.
func test_worm_sprites_render_at_their_intended_world_length():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var checked := 0
	for sprites in manager._worm_sprites.values():
		for cell in sprites:
			var sprite: Sprite2D = sprites[cell]
			assert_almost_eq(
				sprite.scale.x * float(ProceduralWormSprite.SIZE.x),
				ProceduralWormSprite.WORLD_LENGTH_TILES * float(TerrainRenderer.TILE_SIZE),
				0.01
			)
			checked += 1
	assert_gt(checked, 0, "precondition: some worms were rendered")


## Foot-anchored like the flowers, so a worm Y-sorts against the player
## instead of sorting from its middle.
func test_worm_sprites_are_foot_anchored():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	for sprites in manager._worm_sprites.values():
		for cell in sprites:
			assert_almost_eq(
				sprites[cell].offset.y, -float(ProceduralWormSprite.SIZE.y) * 0.5, 0.001
			)


func test_unloading_a_chunk_drops_its_worms_and_their_sprites():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var loaded_chunk: Vector2i = manager._worm_patches.keys()[0]
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	assert_false(manager._worm_patches.has(loaded_chunk), "the sim goes with the chunk")
	assert_false(manager._worm_sprites.has(loaded_chunk), "and so do its sprites")


## The live drivers: step_worms must actually push the real weather and the
## real season into every loaded sim, not leave them frozen at construction.
func test_stepping_worms_drives_them_from_the_live_weather_and_season():
	manager.update(_berlin_tile)
	for patch in manager._worm_patches.values():
		patch.set_conditions(0.0, 0.0)
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var centre := _pixel_for(chunk_coord, Vector2i(0, 0))
	var expected := EarthwormPatch.surface_drive(
		manager._weather_model.soil_moisture(manager.current_weather(centre)),
		EarthwormPatch.soil_warmth(
			manager.generator.temperature_at_global(_berlin_tile.x, _berlin_tile.y),
			manager._season_cycle.warmth_modifier(0.0)
		)
	)
	assert_gt(expected, 0.0, "a fresh temperate spring must not be dead ground")
	assert_almost_eq(manager._worm_patches[chunk_coord]._drive, expected, 0.06)


## End to end against real terrain: left to run on its own, a loaded Berlin
## actually puts worms on the ground. This is the one that would have caught
## a soil-warmth formula that reads as frozen at world start.
func test_worms_surface_on_their_own_under_the_live_world():
	manager.update(_berlin_tile)
	for i in 60:
		manager.step_worms(1.0)
	var surfaced := 0
	for patch in manager._worm_patches.values():
		for cell in patch.worm_cells():
			if patch.is_surfaced(cell):
				surfaced += 1
	assert_gt(surfaced, 0, "a real spring day at Berlin should bring worms up")


# -- flowers_near: a landing point that tracks the real plant ----------------
#
# blossom_height_world used to scale purely by the species' own nominal size,
# while the sprite itself is drawn at a smaller, per-PLANT size for a runt
# (see ProceduralFlowerSprite.PLANT_SIZE_VARIANCE) or a plant still growing
# in (see FlowerPatch.growth_at) -- so the landing point did not shrink with
# it. Worst on a species whose scale is large to begin with, where even a
# modest mismatch is a lot of world pixels (reported on the sunflower:
# "butterflies drink from their stem").

func test_a_freshly_planted_seedlings_landing_point_is_not_the_mature_blossom_height():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")

	# Scan a small patch of cells for one this species can actually root in
	# (plant_flower_at refuses ocean/forest/etc. and any cell already
	# occupied), rather than betting on one hand-picked cell.
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var planted_tile := Vector2i.ZERO
	var planted := false
	for y in 8:
		for x in 8:
			var local := Vector2i(x, y)
			if manager.plant_flower_at(_pixel_for(chunk_coord, local), species):
				planted_tile = origin + local
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")

	var at := _pixel_for(chunk_coord, planted_tile - origin)
	var found := {}
	for flower in manager.flowers_near(at, 2):
		if flower["position"].distance_to(at) < 1.0:
			found = flower
			break
	assert_false(found.is_empty(), "precondition: the newly-planted flower should be forageable")

	# A fresh planting starts at growth 0.0 (see FlowerPatch.plant) -- far
	# smaller than the mature sprite the old species-only formula assumed.
	var actual_offset: float = found["position"].y - found["landing"].y
	var seed_value := hash("%d_%d_flower" % [planted_tile.x, planted_tile.y])
	var mature_offset := ProceduralFlowerSprite.blossom_height_world(
		seed_value, ProceduralFlowerSprite.world_scale_for(species)
	)
	assert_gt(mature_offset, 0.0, "precondition: a mature blossom should sit above the foot at all")
	assert_lt(
		actual_offset, mature_offset * 0.9,
		"a freshly-planted seedling should land well below its mature blossom height"
	)


# -- forage claims (see ForageClaims / PollinatorForaging.choose_target) -----
#
# The shared table of "which bloom is each live pollinator heading for",
# reached by the markers through the same duck-typed `scent_world` they
# already hold. Held on the chunk manager because it must be SHARED between
# flyers, and because the chunk lifecycle is the only place that can reliably
# clean it up when they despawn.

func test_claiming_and_reading_back_a_flower():
	manager.claim_flower(Vector2(100, 200), 4242)
	assert_eq(manager.claims_near(Vector2(100, 200), 8.0, 0), [Vector2(100, 200)])


func test_a_flyer_is_never_warned_off_its_own_target():
	manager.claim_flower(Vector2(100, 200), 4242)
	assert_eq(manager.claims_near(Vector2(100, 200), 8.0, 4242).size(), 0)


func test_claims_outside_the_radius_are_not_reported():
	manager.claim_flower(Vector2(1000, 1000), 4242)
	assert_eq(manager.claims_near(Vector2(0, 0), 8.0, 0).size(), 0)


func test_releasing_a_claim_clears_it():
	manager.claim_flower(Vector2(100, 200), 4242)
	manager.release_flower_claim(4242)
	assert_eq(manager.claims_near(Vector2(100, 200), 8.0, 0).size(), 0)


func test_releasing_a_claim_nobody_holds_is_harmless():
	manager.release_flower_claim(123456)
	assert_eq(manager._forage_claims.claim_count(), 0)


## The leak this wiring exists to avoid: claims are keyed by instance id, and
## chunk unload is the ONLY despawn path that releases them
## (NOTIFICATION_PREDELETE is not reliable here). Without it the table fills
## with blooms that nothing is heading for any more, and every surviving
## pollinator routes around empty grass forever.
func test_unloading_a_chunk_releases_every_departing_flyers_claim():
	manager.update(_berlin_tile)
	var claimed := 0
	for chunk_coord in manager._loaded_ambient_flyers:
		for flyer in manager._loaded_ambient_flyers[chunk_coord]:
			manager.claim_flower(flyer.position, flyer.get_instance_id())
			claimed += 1
	assert_gt(claimed, 0, "precondition: Berlin spawned some ambient flyers")
	assert_eq(manager._forage_claims.claim_count(), claimed)

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))
	assert_eq(
		manager._forage_claims.claim_count(), 0,
		"every unloaded flyer should have given up its claim"
	)


# -- ground decor gets its own non-y-sorted layer ----------------------------
#
# Flowers, worms, desert scrub, and tundra lichen are ground-level decoration:
# always flush with the floor, never needing to Y-sort against a tree or a
# creature. scenes/world.tscn already gives ground-effects layers exactly
# this "always draws behind Entities" treatment (WaterFx/SnowFx/HillshadeFx:
# z_index=-1, no y_sort_enabled) -- world.gd wires an equivalent "GroundDecor"
# node through to EarthChunkManager as an optional 4th constructor argument,
# and these four kinds parent their sprites there instead of under the
# y_sort_enabled Entities node, so they stop forcing per-sprite Y-order
# interleaving with everything else Entities draws (which is what breaks
# draw-call batching under the gl_compatibility renderer).
#
# The argument is optional, defaulting to null, so the many other
# EarthChunkManager.new(...) call sites across this suite (and the real one
# in scenes/world.gd before this change) keep working unchanged; omitting it
# falls back to the same Entities parent ground decor always used.

const DesertScrub = preload("res://src/world/desert_scrub.gd")
const TundraLichen = preload("res://src/world/tundra_lichen.gd")


func _all_biome(cell_value: String, size: int) -> PackedStringArray:
	var biome := PackedStringArray()
	biome.resize(size * size)
	for i in biome.size():
		biome[i] = cell_value
	return biome


func test_flower_worm_scrub_and_lichen_sprites_parent_under_the_supplied_ground_decor_layer():
	var ground_decor := Node2D.new()
	ground_decor.z_index = -1
	var decor_tile_map := TileMapLayer.new()
	var decor_entities := Node2D.new()
	var decor_creatures := Node2D.new()
	var decor_manager := EarthChunkManager.new(
		decor_tile_map, decor_entities, decor_creatures, ground_decor
	)
	decor_manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)

	# Flower: plant one directly, the same way
	# test_a_freshly_planted_seedlings_landing_point_is_not_the_mature_blossom_height does.
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, decor_manager.current_season()):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var planted := false
	for y in 8:
		for x in 8:
			if decor_manager.plant_flower_at(_pixel_for(chunk_coord, Vector2i(x, y)), species):
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var flower_sprites: Dictionary = decor_manager._flower_sprites[chunk_coord]
	assert_gt(flower_sprites.size(), 0, "precondition: the planted flower should have a sprite")
	for sprite in flower_sprites.values():
		assert_eq(sprite.get_parent(), ground_decor, "flower sprite should parent under GroundDecor")

	# Worm: force one to the surface, the same way _surface_all_worms does
	# (that helper reaches the file-level `manager`, not this local instance).
	for patch in decor_manager._worm_patches.values():
		patch.set_conditions(1.0, 1.0)
	for i in 40:
		for patch in decor_manager._worm_patches.values():
			patch.advance(0.5)
	decor_manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var checked_worm := 0
	for sprites in decor_manager._worm_sprites.values():
		for sprite in sprites.values():
			assert_eq(sprite.get_parent(), ground_decor, "worm sprite should parent under GroundDecor")
			checked_worm += 1
	assert_gt(checked_worm, 0, "precondition: some worms were rendered")

	# Desert scrub / tundra lichen: Berlin's real biome is not desert or
	# tundra, so force an all-desert/all-tundra sim directly (this suite
	# already reaches into manager internals the same way elsewhere) rather
	# than hunting for a real-world tile of that biome.
	decor_manager._scrub_sims[chunk_coord] = DesertScrub.new(
		1, EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE,
		_all_biome("desert", EarthChunkManager.CHUNK_SIZE)
	)
	decor_manager._sync_scrub_sprites(chunk_coord)
	var scrub_sprites: Dictionary = decor_manager._scrub_sprites[chunk_coord]
	assert_gt(scrub_sprites.size(), 0, "precondition: a forced desert biome should seed scrub")
	for sprite in scrub_sprites.values():
		assert_eq(sprite.get_parent(), ground_decor, "scrub sprite should parent under GroundDecor")

	decor_manager._lichen_sims[chunk_coord] = TundraLichen.new(
		1, EarthChunkManager.CHUNK_SIZE, EarthChunkManager.CHUNK_SIZE,
		_all_biome("tundra", EarthChunkManager.CHUNK_SIZE)
	)
	decor_manager._sync_lichen_sprites(chunk_coord)
	var lichen_sprites: Dictionary = decor_manager._lichen_sprites[chunk_coord]
	assert_gt(lichen_sprites.size(), 0, "precondition: a forced tundra biome should seed lichen")
	for sprite in lichen_sprites.values():
		assert_eq(sprite.get_parent(), ground_decor, "lichen sprite should parent under GroundDecor")

	decor_tile_map.free()
	decor_entities.free()
	decor_creatures.free()
	ground_decor.free()


## Backward compatibility: every other EarthChunkManager.new(...) call site
## passes only 3 arguments, and must keep parenting ground decor under
## Entities exactly as before this change.
func test_ground_decor_falls_back_to_entities_when_not_supplied():
	manager.update(_berlin_tile)
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, manager.current_season()):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var planted := false
	for y in 8:
		for x in 8:
			if manager.plant_flower_at(_pixel_for(chunk_coord, Vector2i(x, y)), species):
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var flower_sprites: Dictionary = manager._flower_sprites[chunk_coord]
	assert_gt(flower_sprites.size(), 0, "precondition: the planted flower should have a sprite")
	for sprite in flower_sprites.values():
		assert_eq(
			sprite.get_parent(), entities_parent,
			"with no ground_decor_parent supplied, ground decor should keep parenting under Entities"
		)


## A live pollinator reaches this surface through `scent_world`, which is the
## manager itself -- so the duck-typed contract the markers probe for with
## has_method must actually be present here.
func test_the_manager_exposes_the_claim_surface_the_markers_probe_for():
	assert_true(manager.has_method("claim_flower"))
	assert_true(manager.has_method("release_flower_claim"))
	assert_true(manager.has_method("claims_near"))


## An eaten worm has to vanish the INSTANT the bird takes it.
##
## Found by the live runtime probe, which reported 59 rendered worms against
## 56 actually at the surface: the sprite layer only re-syncs every
## WORM_REFRESH_INTERVAL (5s), so a worm a robin had just eaten went on lying
## in the grass for up to five more seconds. That undermines the entire point
## of the mechanic -- the player watches the bird peck and the worm stay put.
## take_worm_at therefore re-syncs its own chunk immediately, exactly the way
## plant_flower_at does after planting.
func test_an_eaten_worm_disappears_immediately_rather_than_at_the_next_refresh():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var found := _a_surfaced_worm()
	assert_gt(found.size(), 0, "precondition: a worm is up")
	var chunk_coord: Vector2i = found[0]
	var cell: Vector2i = found[1]
	assert_true(manager._worm_sprites[chunk_coord].has(cell), "precondition: it is rendered")

	assert_true(manager.take_worm_at(_pixel_for(chunk_coord, cell)))
	assert_false(
		manager._worm_sprites[chunk_coord].has(cell),
		"the worm must leave the screen on the same frame the bird takes it"
	)


## ...and the rest of the lawn must not flicker out with it.
func test_eating_one_worm_leaves_the_other_worm_sprites_alone():
	manager.update(_berlin_tile)
	_surface_all_worms()
	manager.step_worms(EarthChunkManager.WORM_REFRESH_INTERVAL + 1.0)
	var before := _rendered_worm_count()
	assert_gt(before, 1, "precondition: more than one worm is rendered")
	var found := _a_surfaced_worm()
	manager.take_worm_at(_pixel_for(found[0], found[1]))
	assert_eq(_rendered_worm_count(), before - 1)


# -- solid_obstacles_near: spatially-bounded obstacle lookup for creatures ----
#
# CreatureMarker used to find trees/stones by scanning the ENTIRE "tree" and
# "stone" node groups -- every node in every loaded chunk, per creature, on
# every sensing tick (reported: "since the last change the game is laggy").
# The chunk manager already keeps per-chunk lists of exactly these nodes, so
# a lookup bounded to the chunks overlapping the query circle is O(nearby),
# not O(world).

func test_solid_obstacles_near_returns_only_obstacles_within_the_radius():
	var near := Node2D.new()
	near.position = Vector2(100, 100)
	var far := Node2D.new()
	far.position = Vector2(400, 100)
	entities_parent.add_child(near)
	entities_parent.add_child(far)
	manager._loaded_trees[Vector2i(0, 0)] = [near, far]

	var found: Array = manager.solid_obstacles_near(Vector2(110, 100), 64.0)

	assert_eq(found.size(), 1)
	assert_eq(found[0]["position"], Vector2(100, 100))


## An obstacle can sit just across a chunk border from the asking creature --
## the chunk-range math must cover every chunk the query circle overlaps,
## not only the creature's own.
func test_solid_obstacles_near_finds_an_obstacle_in_a_neighboring_chunk():
	var chunk_px := float(EarthChunkManager.CHUNK_SIZE * TerrainRenderer.TILE_SIZE)
	var just_across := Node2D.new()
	just_across.position = Vector2(chunk_px + 10.0, 100)  # inside chunk (1,0)
	entities_parent.add_child(just_across)
	manager._loaded_stones[Vector2i(1, 0)] = [just_across]

	# Creature stands near the border, inside chunk (0,0).
	var found: Array = manager.solid_obstacles_near(Vector2(chunk_px - 10.0, 100), 64.0)

	assert_eq(found.size(), 1)


func test_solid_obstacles_near_reads_the_radius_from_the_obstacles_own_collision_shape():
	var tree := StaticBody2D.new()
	tree.position = Vector2(100, 100)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12.0, 6.0)
	collision.shape = shape
	tree.add_child(collision)
	entities_parent.add_child(tree)
	manager._loaded_trees[Vector2i(0, 0)] = [tree]

	var found: Array = manager.solid_obstacles_near(Vector2(100, 100), 64.0)

	assert_eq(found.size(), 1)
	assert_almost_eq(found[0]["radius"], 6.0, 0.001, "half the shape's larger extent")


# -- seeds: the granivore half of a meadow ----------------------------------

## Flowers whose bloom is over have gone to seed (see FlowerPatch.seed_cells
## / concept/flora.md). This is the seeds_near/take_seed_at pair FlyerDiet
## has been waiting on since the diet table was written -- sparrows carried a
## FOOD_SEEDS entry with nothing in the world to eat.
func test_seeds_near_reports_seed_lying_on_the_ground():
	manager.update(_berlin_tile)
	# Seed is shed over time now, not present from the moment a chunk loads.
	for i in 400:
		manager.step_flowers(1.0)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE

	var seeds: Array = manager.seeds_near(centre, 40)

	assert_gt(seeds.size(), 0, "a standing meadow should have shed seed around itself")
	for seed in seeds:
		assert_true(seed.has("position"), "shaped like worms_near/fruit_near")
		assert_ne(String(seed["species"]), "", "a seed knows which flower it came from")


## Taking a seed returns the species (so the bird can plant it again) and
## actually removes it, so two birds can't eat the same seed.
func test_take_seed_at_returns_the_species_and_removes_it():
	manager.update(_berlin_tile)
	for i in 400:
		manager.step_flowers(1.0)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something to eat")
	var at: Vector2 = seeds[0]["position"]

	var species := manager.take_seed_at(at)

	assert_ne(species, "", "eating a seed tells the bird what it swallowed")
	assert_eq(manager.take_seed_at(at), "", "and there is nothing left to eat twice")


## The complement that makes the whole cycle work: what a bird swallows must
## be a species the world can actually plant again (bird endozoochory). An
## eaten seed that named nothing plantable would break the cycle silently.
func test_an_eaten_seed_names_a_real_plantable_species():
	const FlowerSpecies = preload("res://src/world/flower_species.gd")
	manager.update(_berlin_tile)
	for i in 400:
		manager.step_flowers(1.0)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something to eat")

	var species := manager.take_seed_at(seeds[0]["position"])

	assert_true(
		FlowerSpecies.IDS.has(species),
		"a swallowed seed must name a real flower species, or nothing can grow from it"
	)


## Every seed a bird can eat must be VISIBLE. Seeds sit on plants whose bloom
## is over -- and bloom-aware rendering (correctly) stopped drawing
## out-of-bloom plants, which between them created an invisible resource: a
## sparrow landed and pecked at bare grass (reported: "the sparrow is landing
## and pecking at something but neither worms nor seeds are visible at where
## he's pecking"). A plant gone to seed is drawn as a dried seedhead instead
## of not at all -- see concept/flora.md "What is visible must be what is
## real", the invariant this broke.
func test_every_edible_seed_is_rendered():
	manager.update(_berlin_tile)
	for i in 400:
		manager.step_flowers(1.0)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: some seed has been shed")

	var rendered: Array = []
	for chunk_coord in manager._seed_sprites:
		for cell in manager._seed_sprites[chunk_coord]:
			rendered.append(manager._seed_sprites[chunk_coord][cell].position)

	for seed in seeds:
		var found := false
		for at in rendered:
			if at.distance_to(seed["position"]) < TerrainRenderer.TILE_SIZE:
				found = true
				break
		assert_true(found, "a seed a bird will fly down and eat must be visible on the ground")


## Shed seed must be a visible object on the ground, not an invisible
## property of a plant -- a sparrow flew down and pecked at bare grass
## because the seed it was eating had no sprite at all (reported: "neither
## worms nor seeds are visible at where he's pecking"). Seeds now fall from
## flowers as their own entities and are rendered where they lie.
func test_shed_seed_appears_on_the_ground_and_is_rendered():
	manager.update(_berlin_tile)
	for i in 400:
		manager.step_flowers(1.0)

	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.seeds_near(centre, 60)
	assert_gt(seeds.size(), 0, "a standing meadow should shed seed around itself")

	var rendered := 0
	for chunk_coord in manager._seed_sprites:
		rendered += manager._seed_sprites[chunk_coord].size()
	assert_gt(rendered, 0, "and every shed seed must be visible on the ground")


func test_a_bird_eating_a_seed_removes_its_sprite():
	manager.update(_berlin_tile)
	for i in 400:
		manager.step_flowers(1.0)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.seeds_near(centre, 60)
	assert_gt(seeds.size(), 0, "precondition: something to eat")

	var before := 0
	for chunk_coord in manager._seed_sprites:
		before += manager._seed_sprites[chunk_coord].size()
	var species := manager.take_seed_at(seeds[0]["position"])
	var after := 0
	for chunk_coord in manager._seed_sprites:
		after += manager._seed_sprites[chunk_coord].size()

	assert_ne(species, "", "eating tells the bird what it swallowed")
	assert_eq(after, before - 1, "the eaten seed must disappear on the frame it is taken")


## Individual reproduction must obey the same carrying capacity the unseen
## aggregate simulation does ("two fidelities, one truth" --
## concept/ecosystem_dynamics.md). Without this the only limit on breeding
## was a global 60-creature node cap, so once the ecology actually started
## running, well-fed deer bred straight to that cap and piled up in one
## clearing (reported with a screenshot: "the fruit caused dozens of deer to
## spawn???").
func test_a_chunk_refuses_more_herbivores_once_at_carrying_capacity():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE

	assert_true(
		manager.can_support_another_herbivore(centre, 0),
		"empty habitable ground should support a herbivore"
	)
	assert_false(
		manager.can_support_another_herbivore(centre, 100000),
		"a crowd far beyond what the land can feed must not breed further"
	)


# -- grass a grazer can walk to (see GrazerForaging) -------------------------
#
# Herbivores used to absorb food from the BIOME under their feet and eat
# whatever tuft their wander happened to cross (_graze_by_herbivores). For a
# horse to actually walk to a tuft it needs to be able to see one first --
# the grass counterpart of worms_near/seeds_near/fruit_near, in the same
# {position} shape so GrazerForaging can treat all four alike.

func test_grass_near_reports_a_mature_tuft_in_the_same_shape_as_the_other_food():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "Berlin's grassland should offer a horse something to eat")
	for tuft in tufts:
		assert_true(tuft.has("position"), "shaped like worms_near/fruit_near")


## What is visible must be what is real: a grazer must not walk to a shoot it
## cannot actually crop, since TallGrass.graze only yields on a mature patch.
func test_grass_near_only_offers_tufts_that_are_actually_ready():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	for tuft in manager.grass_near(centre, 40):
		var tile := manager._world_tile_for_pixel(tuft.position)
		var chunk_coord := manager._chunk_coord_for_tile(tile)
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		assert_gte(
			sim.get_growth(tile - chunk_coord * EarthChunkManager.CHUNK_SIZE), 1.0,
			"a young shoot is not a meal"
		)


func test_grass_near_respects_its_radius():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var centre_tile: Vector2i = manager._world_tile_for_pixel(centre)
	for tuft in manager.grass_near(centre, 3):
		var tile: Vector2i = manager._world_tile_for_pixel(tuft.position)
		assert_lte(maxi(absi(tile.x - centre_tile.x), absi(tile.y - centre_tile.y)), 3)


func test_a_grazed_tuft_is_gone_from_the_world():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "precondition: something to graze")
	var eaten: Vector2 = tufts[0].position
	assert_true(manager.graze_grass_at(eaten), "the mouthful lands")
	for tuft in manager.grass_near(centre, 40):
		assert_ne(tuft.position, eaten, "the tuft the horse just ate is gone")


func test_grazing_bare_ground_takes_nothing():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "precondition: a loaded grass sim")
	manager.graze_grass_at(tufts[0].position)
	assert_false(manager.graze_grass_at(tufts[0].position), "nothing left to take twice")


## The tuft has to disappear on the frame the player watched the horse eat
## it, not whenever the next throttled sprite refresh happens to come round --
## the same immediate-resync take_worm_at and take_seed_at do.
func test_a_grazed_tuft_stops_being_drawn_immediately():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "precondition: something to graze")

	# grass_near's 40-tile reach is simulation-wide (a grazer may walk to an
	# off-screen tuft -- see grass_near's own doc comment), scanned in
	# dictionary order across a 3x3-chunk neighbourhood, NOT sorted by
	# distance. Drawing is intentionally scoped far tighter, to the camera's
	# own tile-precise view window (GRASS_VIEW_BUFFER_TILES/_sync_grass_
	# sprites), so tufts[0] is not reliably one of the handful that are
	# actually drawn. This test's own subject is the draw-immediacy of an
	# on-screen tuft, so pick the first one the manager itself already drew
	# rather than assuming grass_near's first result is on-screen.
	# SUPERSEDED (2026-08-27): used to predict a SINGLE band via the old
	# cell-level shortcut (band_index_for_local_y(cell.y, ...)) and assert
	# just that one band's count dropped by a flat CARD_COUNT. Now that
	# banding is per-CARD (see IllustratedGrassPatch.cards_for_cell), one
	# tuft's own CARD_COUNT cards can genuinely land in two DIFFERENT real
	# bands -- so this finds every real band the eaten tuft's own cards
	# occupy and checks the TOTAL across all of them, mirroring
	# _sync_grass_sprites' own real per-card bucketing exactly.
	var eaten: Vector2
	var chunk_coord: Vector2i
	var real_bands: Array[int] = []
	for tuft in tufts:
		var tile: Vector2i = manager._world_tile_for_pixel(tuft.position)
		var candidate_chunk: Vector2i = manager._chunk_coord_for_tile(tile)
		var origin: Vector2i = candidate_chunk * EarthChunkManager.CHUNK_SIZE
		var cell: Vector2i = tile - origin
		var sim: TallGrass = manager._grass_sims.get(candidate_chunk)
		if sim == null:
			continue
		var seed_value := hash("%d_%d_grass_tuft" % [tile.x, tile.y])
		var cell_spec := {
			"seed": seed_value,
			"ground_position": Vector2(
				(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
			),
			"growth": sim.get_growth(cell),
		}
		var candidate_bands: Array[int] = []
		for card in IllustratedGrassPatch.cards_for_cell(cell_spec):
			var local_row := IllustratedGrassPatch.local_row_for_world_y(card.position.y, origin.y, TerrainRenderer.TILE_SIZE)
			var card_band := IllustratedGrassPatch.band_index_for_local_y(local_row, EarthChunkManager.CHUNK_SIZE)
			if not candidate_bands.has(card_band):
				candidate_bands.append(card_band)
		var all_drawn := true
		for candidate_band in candidate_bands:
			if not manager._grass_sprites.get(candidate_chunk, {}).has(candidate_band):
				all_drawn = false
				break
		if all_drawn and not candidate_bands.is_empty():
			eaten = tuft.position
			chunk_coord = candidate_chunk
			real_bands = candidate_bands
			break
	assert_false(real_bands.is_empty(), "precondition: at least one grazeable tuft is actually drawn")
	var before := 0
	for band in real_bands:
		before += manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	manager.graze_grass_at(eaten)
	var bands: Dictionary = manager._grass_sprites[chunk_coord]
	var after := 0
	for band in real_bands:
		if bands.has(band):
			after += bands[band].multimesh.instance_count
	assert_eq(after, before - IllustratedGrassPatch.CARD_COUNT, "the eaten tuft's cards stop being drawn at once, across every real band they occupied")


# -- grass seed: the granivore/rodent half of a field (see
# docs/concept/long_grass.md's "Reproduction" section) ----------------------
#
# grass_seeds_near/take_grass_seed_at mirror seeds_near/take_seed_at exactly
# in shape, backed by TallGrass's own ground seed rather than FlowerPatch's --
# grass sheds its own seed, independent of flowers.

func test_grass_seeds_near_reports_seed_lying_on_the_ground():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE

	var seeds: Array = manager.grass_seeds_near(centre, 40)

	assert_gt(seeds.size(), 0, "a standing field should have shed seed around itself")
	for seed in seeds:
		assert_true(seed.has("position"), "shaped like worms_near/seeds_near/fruit_near")


func test_take_grass_seed_at_removes_it_and_returns_true():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.grass_seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something to eat")
	var at: Vector2 = seeds[0]["position"]

	assert_true(manager.take_grass_seed_at(at), "eating a seed that is there succeeds")
	assert_false(manager.take_grass_seed_at(at), "and there is nothing left to eat twice")


func test_plant_grass_at_establishes_a_new_patch():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(centre))
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	# An empty grassland cell somewhere in this chunk to plant into.
	var target_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not sim.has_grass(cell) and manager.biome_at_global(
				(chunk_coord.x * EarthChunkManager.CHUNK_SIZE) + x,
				(chunk_coord.y * EarthChunkManager.CHUNK_SIZE) + y
			) == "grassland":
				target_cell = cell
				break
		if target_cell != Vector2i(-1, -1):
			break
	assert_ne(target_cell, Vector2i(-1, -1), "precondition: an empty grassland cell exists in this chunk")
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var at := Vector2(
		float(origin.x + target_cell.x) + 0.5, float(origin.y + target_cell.y) + 0.5
	) * TerrainRenderer.TILE_SIZE

	assert_true(manager.plant_grass_at(at))

	assert_true(sim.has_grass(target_cell))


func test_plant_grass_at_fails_when_the_chunk_is_not_loaded():
	var far_away := Vector2(1_000_000, 1_000_000)
	assert_false(manager.plant_grass_at(far_away))


# -- rodent scatter-hoarding: a mouse picks up a fallen grass seed and caches
# it nearby (see SeedCaching / docs/concept/long_grass.md's "Reproduction"
# section) -- distinct from the bird pathway above, and from every other
# non-predator creature's flower epizoochory below.

func test_a_mouse_standing_on_a_grass_seed_picks_it_up():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.grass_seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something for the mouse to find")
	var at: Vector2 = seeds[0]["position"]
	var mouse := manager._creature_renderer.spawn_single(
		creatures_parent, "mouse", at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_grass_seed_caching(mouse)

	assert_true(mouse.carried_grass_seed, "the mouse should have picked the seed up")
	var still_there := false
	for seed in manager.grass_seeds_near(centre, 40):
		if seed["position"].distance_to(at) < 1.0:
			still_there = true
	assert_false(still_there, "eaten off the ground, not merely noticed")


## Only mice do this -- a non-mouse creature standing on the exact same seed
## must leave it alone, since this is a real rodent behaviour, not something
## every "Forager"-diet or non-predator creature does.
func test_a_non_mouse_creature_does_not_cache_grass_seed():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.grass_seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something on the ground")
	var at: Vector2 = seeds[0]["position"]
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_grass_seed_caching(horse)

	assert_false(horse.carried_grass_seed)
	var still_there := false
	for seed in manager.grass_seeds_near(centre, 40):
		if seed["position"].distance_to(at) < 1.0:
			still_there = true
	assert_true(still_there, "a horse must not eat grass seed off the ground")


## Once a mouse has carried its cached seed its own (short) distance, it
## caches (plants) a brand-new patch right where it is standing -- the
## genuinely-new-field mechanism _step_spread's contiguous growth cannot
## produce on its own.
func test_a_mouse_caches_its_carried_seed_as_a_new_patch_once_it_has_travelled_far_enough():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	# An empty grassland cell somewhere in this chunk to cache into.
	var target_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not sim.has_grass(cell) and manager.biome_at_global(
				(chunk_coord.x * EarthChunkManager.CHUNK_SIZE) + x,
				(chunk_coord.y * EarthChunkManager.CHUNK_SIZE) + y
			) == "grassland":
				target_cell = cell
				break
		if target_cell != Vector2i(-1, -1):
			break
	assert_ne(target_cell, Vector2i(-1, -1), "precondition: an empty grassland cell exists in this chunk")
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var at := Vector2(
		float(origin.x + target_cell.x) + 0.5, float(origin.y + target_cell.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	var mouse := manager._creature_renderer.spawn_single(
		creatures_parent, "mouse", at, manager, TerrainRenderer.TILE_SIZE
	)
	mouse.carried_grass_seed = true
	# Already travelled well past even the longest possible carry distance.
	mouse.carried_grass_seed_origin = at - Vector2(
		(SeedCaching.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
	)

	manager._step_grass_seed_caching(mouse)

	assert_true(sim.has_grass(target_cell), "a new patch should have been cached here")
	assert_false(mouse.carried_grass_seed, "caching empties the pouch")


## Symmetric to the pickup-too-early case above: a mouse that has not yet
## gone its own carry distance keeps carrying rather than caching on the spot.
func test_a_mouse_does_not_cache_before_travelling_its_carry_distance():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	var target_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not sim.has_grass(cell) and manager.biome_at_global(
				(chunk_coord.x * EarthChunkManager.CHUNK_SIZE) + x,
				(chunk_coord.y * EarthChunkManager.CHUNK_SIZE) + y
			) == "grassland":
				target_cell = cell
				break
		if target_cell != Vector2i(-1, -1):
			break
	assert_ne(target_cell, Vector2i(-1, -1), "precondition: an empty grassland cell exists in this chunk")
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var at := Vector2(
		float(origin.x + target_cell.x) + 0.5, float(origin.y + target_cell.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	var mouse := manager._creature_renderer.spawn_single(
		creatures_parent, "mouse", at, manager, TerrainRenderer.TILE_SIZE
	)
	mouse.carried_grass_seed = true
	mouse.carried_grass_seed_origin = at  # has not moved at all yet

	manager._step_grass_seed_caching(mouse)

	assert_false(sim.has_grass(target_cell), "too soon to cache -- it hasn't gone anywhere yet")
	assert_true(mouse.carried_grass_seed, "still carrying")


# -- ground carriers actually reach their own real carry range --------------
#
# CreatureWander (ordinary wander, shared by every ground creature) is the
# SAME home-tethered containment shape AmbientFlyerMovement uses for birds --
# measured at a hard ~2.6-tile ceiling on distance from home regardless of
# wander_seed, well short of any of these three carriers' own real ranges
# (see docs/progress.md for the full measurement: 0/30 sampled seeds ever
# reached SeedDispersal's range under pure wander, and only 11/30 reached
# SeedCaching's shorter one). Fixed the same shape AmbientFlyerMarker's own
# bird carry was: pickup now also picks a real heading
# (SeedDispersal/SeedCaching/SquirrelNutCaching.carry_direction), leaned
# into by CreatureMarker._wander_step.

## Pickup must set the new direction, not just the existing flag/origin --
## otherwise it stays at its Vector2.ZERO default and the mouse is right
## back to pure, capped wander.
func test_a_mouse_picking_up_a_grass_seed_also_picks_a_real_carry_direction():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.grass_seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: something for the mouse to find")
	var at: Vector2 = seeds[0]["position"]
	var mouse := manager._creature_renderer.spawn_single(
		creatures_parent, "mouse", at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_grass_seed_caching(mouse)

	assert_almost_eq(
		mouse.carried_grass_seed_direction.length(), 1.0, 0.001,
		"pickup should set a real unit-length carry direction, not leave it at its zero default"
	)


## Mirrors AmbientFlyerMarker's own bird range test
## (test_a_sparrows_seed_carry_reaches_the_real_dispersal_range_across_many_
## birds) -- must hold for many different mice, not just a convenient one.
## World left null (a bare marker, not spawn_single's real EarthChunkManager
## world) so this proves the STEERING alone is enough -- not reliant on
## hunger/foraging luck, which real measurement found rescues only some
## individuals and only slowly (see docs/progress.md).
func test_a_mouses_grass_seed_carry_reaches_the_real_range_across_many_mice():
	# creatures_parent (unlike every OTHER test in this file) needs to be in
	# the LIVE tree here: _process is driven for real below, which calls
	# _sync_grounded_children -- that needs _ready to have actually run
	# (health-bar/shadow child nodes are built there), which needs the
	# marker inside a live tree at all.
	add_child(creatures_parent)
	for wander_seed in range(1, 21):
		var mouse: CreatureMarker = manager._creature_renderer.spawn_single(
			creatures_parent, "mouse", Vector2.ZERO, null, TerrainRenderer.TILE_SIZE, wander_seed
		)
		mouse.carried_grass_seed = true
		mouse.carried_grass_seed_origin = mouse.position
		mouse.carried_grass_seed_direction = SeedCaching.carry_direction(wander_seed)

		for step in range(3000):  # 900 simulated seconds -- generous
			mouse._process(0.3)
			manager._step_grass_seed_caching(mouse)
			if not mouse.carried_grass_seed:
				break
		var net_tiles := mouse.position.length() / float(TerrainRenderer.TILE_SIZE)
		var still_carrying := mouse.carried_grass_seed
		creatures_parent.remove_child(mouse)
		mouse.free()

		assert_false(
			still_carrying,
			"wander_seed %d: mouse never cached its grass seed within the step budget" % wander_seed
		)
		assert_gte(
			net_tiles, SeedCaching.CARRY_MIN_TILES,
			"wander_seed %d: mouse only carried %.2f tiles, short of the %.1f-tile minimum" % [
				wander_seed, net_tiles, SeedCaching.CARRY_MIN_TILES
			]
		)
	remove_child(creatures_parent)


## Same pickup-sets-a-real-direction proof, for the OTHER ground carrier that
## needed it: flower epizoochory, gated to no particular species (any
## non-predator grazer -- see _step_seed_dispersal's own doc comment).
func test_a_grazer_picking_up_a_flower_seed_also_picks_a_real_carry_direction():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var at := Vector2.ZERO
	var planted := false
	for y in 8:
		for x in 8:
			var candidate_at := _pixel_for(chunk_coord, Vector2i(x, y))
			if manager.plant_flower_at(candidate_at, species):
				at = candidate_at
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_seed_dispersal(horse)

	assert_almost_eq(
		horse.carried_seed_direction.length(), 1.0, 0.001,
		"pickup should set a real unit-length carry direction, not leave it at its zero default"
	)


## Flower epizoochory's own range (3-14 tiles) is the LARGEST of the three
## ground carriers -- measured as the worst-affected under pure wander (0/30
## sampled seeds ever reached it, see docs/progress.md). World left null for
## the same steering-alone isolation as the mouse test above.
func test_a_grazers_flower_seed_carry_reaches_the_real_range_across_many_grazers():
	add_child(creatures_parent)  # see the mouse test above's own doc comment
	for wander_seed in range(1, 21):
		var horse: CreatureMarker = manager._creature_renderer.spawn_single(
			creatures_parent, "horse", Vector2.ZERO, null, TerrainRenderer.TILE_SIZE, wander_seed
		)
		horse.carried_seed_species = "rose"
		horse.carried_seed_origin = horse.position
		horse.carried_seed_direction = SeedDispersal.carry_direction(wander_seed)

		for step in range(3000):  # 900 simulated seconds -- generous
			horse._process(0.3)
			manager._step_seed_dispersal(horse)
			if horse.carried_seed_species == "":
				break
		var net_tiles := horse.position.length() / float(TerrainRenderer.TILE_SIZE)
		var remaining_species := horse.carried_seed_species
		creatures_parent.remove_child(horse)
		horse.free()

		assert_eq(
			remaining_species, "",
			"wander_seed %d: grazer never dropped its flower seed within the step budget" % wander_seed
		)
		assert_gte(
			net_tiles, SeedDispersal.CARRY_MIN_TILES,
			"wander_seed %d: grazer only carried %.2f tiles, short of the %.1f-tile minimum" % [
				wander_seed, net_tiles, SeedDispersal.CARRY_MIN_TILES
			]
		)
	remove_child(creatures_parent)


## Third and last ground carrier -- fixed by analogy rather than separately
## measured broken (see SquirrelNutCaching.carry_direction's own doc
## comment), but genuinely verified here rather than assumed fixed.
func test_a_squirrel_picking_up_a_nut_also_picks_a_real_carry_direction():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "walnut"))
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(squirrel)

	assert_almost_eq(
		squirrel.carried_nut_direction.length(), 1.0, 0.001,
		"pickup should set a real unit-length carry direction, not leave it at its zero default"
	)
	ground_items.free()


func test_a_squirrels_nut_carry_reaches_the_real_range_across_many_squirrels():
	add_child(creatures_parent)  # see the mouse test above's own doc comment
	for wander_seed in range(1, 21):
		var squirrel: CreatureMarker = manager._creature_renderer.spawn_single(
			creatures_parent, "squirrel", Vector2.ZERO, null, TerrainRenderer.TILE_SIZE, wander_seed
		)
		squirrel.carried_nut_species = "walnut"
		squirrel.carried_nut_origin = squirrel.position
		squirrel.carried_nut_direction = SquirrelNutCaching.carry_direction(wander_seed)

		for step in range(3000):  # 900 simulated seconds -- generous
			squirrel._process(0.3)
			manager._step_squirrel_nut_caching(squirrel)
			if squirrel.carried_nut_species == "":
				break
		var net_tiles := squirrel.position.length() / float(TerrainRenderer.TILE_SIZE)
		var remaining_species := squirrel.carried_nut_species
		creatures_parent.remove_child(squirrel)
		squirrel.free()

		assert_eq(
			remaining_species, "",
			"wander_seed %d: squirrel never resolved its nut within the step budget" % wander_seed
		)
		assert_gte(
			net_tiles, SquirrelNutCaching.CARRY_MIN_TILES,
			"wander_seed %d: squirrel only carried %.2f tiles, short of the %.1f-tile minimum" % [
				wander_seed, net_tiles, SquirrelNutCaching.CARRY_MIN_TILES
			]
		)
	remove_child(creatures_parent)


# -- flower epizoochory / squirrel nut caching: the edge-case battery mouse
# grass-seed caching already has (pickup radius, species/predator gating,
# resolve timing, eaten-vs-cached branches, species fidelity), backfilled
# for its two ground-carrier siblings, which had none of it (see
# docs/progress.md's ground-carrier entry). Pure coverage backfill: these
# pin EXISTING behaviour, not new behaviour.

## Mirrors SeedDispersal's own test_an_animal_far_from_any_flower_picks_up_
## nothing, but through the real EarthChunkManager wiring: planted exactly
## 2 tiles away, straight-line -- inside flowers_near's own wider 2-tile
## candidate net (so this is not merely "too far to be found at all"), but
## beyond SeedDispersal.PICKUP_RADIUS_TILES (1.5). Pins the real pickup
## gate, not just the wider candidate-search radius around it.
func test_a_grazer_two_tiles_from_a_flower_does_not_pick_up_its_seed():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var flower_cell := Vector2i(-1, -1)
	var planted := false
	for y in 8:
		for x in 8:
			var candidate_cell := Vector2i(x, y)
			if manager.plant_flower_at(_pixel_for(chunk_coord, candidate_cell), species):
				flower_cell = candidate_cell
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", _pixel_for(chunk_coord, flower_cell + Vector2i(2, 0)),
		manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_seed_dispersal(horse)

	assert_eq(
		horse.carried_seed_species, "",
		"2 tiles away is beyond PICKUP_RADIUS_TILES (1.5) -- too far to have brushed against it"
	)


## The EarthChunkManager wiring's own version of SeedDispersal's
## test_nothing_is_picked_up_from_a_species_out_of_season -- that test
## covers SeedDispersal.pickup_species in isolation; this confirms
## _step_seed_dispersal's real flowers_near/current_season plumbing
## actually reaches and respects it.
func test_a_grazer_standing_on_an_out_of_season_flower_does_not_pick_up_its_seed():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if not FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be out of bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var at := Vector2.ZERO
	var planted := false
	for y in 8:
		for x in 8:
			var candidate_at := _pixel_for(chunk_coord, Vector2i(x, y))
			if manager.plant_flower_at(candidate_at, species):
				at = candidate_at
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_seed_dispersal(horse)

	assert_eq(
		horse.carried_seed_species, "",
		"a plant not currently in bloom offers no seed to brush against"
	)


## _step_seed_dispersal itself has no predator gate at all -- the gate is
## enforced only by the caller, _graze_by_herbivores' own
## "creature.info.is_predator: continue" (see that function's own doc
## comment). Driving _step_seed_dispersal directly, as every test above
## does, would never reproduce that gate -- this drives the real caller.
func test_a_predator_does_not_disperse_flower_seed_while_grazing():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var at := Vector2.ZERO
	var planted := false
	for y in 8:
		for x in 8:
			var candidate_at := _pixel_for(chunk_coord, Vector2i(x, y))
			if manager.plant_flower_at(candidate_at, species):
				at = candidate_at
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var wolf := manager._creature_renderer.spawn_single(
		creatures_parent, "wolf", at, manager, TerrainRenderer.TILE_SIZE
	)
	assert_true(wolf.info.is_predator, "precondition: a wolf is a predator")
	manager._loaded_creatures[chunk_coord].append(wolf)

	manager._graze_by_herbivores()

	assert_eq(
		wolf.carried_seed_species, "",
		"a predator standing right on a bloom must not disperse its seed"
	)


## Symmetric to the mouse's own test_a_mouse_does_not_cache_before_
## travelling_its_carry_distance: a grazer that has not yet gone its own
## carry distance keeps carrying rather than dropping on the spot.
func test_a_grazer_does_not_drop_its_flower_seed_before_travelling_its_carry_distance():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var patch: FlowerPatch = manager._flower_patches[chunk_coord]
	var target_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not patch.has_flower(cell) and manager.biome_at_global(
				(chunk_coord.x * EarthChunkManager.CHUNK_SIZE) + x,
				(chunk_coord.y * EarthChunkManager.CHUNK_SIZE) + y
			) == "grassland":
				target_cell = cell
				break
		if target_cell != Vector2i(-1, -1):
			break
	assert_ne(target_cell, Vector2i(-1, -1), "precondition: an empty grassland cell exists in this chunk")
	var at := _pixel_for(chunk_coord, target_cell)
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", at, manager, TerrainRenderer.TILE_SIZE
	)
	horse.carried_seed_species = species
	horse.carried_seed_origin = at  # has not moved at all yet

	manager._step_seed_dispersal(horse)

	assert_false(patch.has_flower(target_cell), "too soon to drop -- it hasn't gone anywhere yet")
	assert_eq(horse.carried_seed_species, species, "still carrying")


## Mirrors AmbientFlyerMarker's own test_eating_fruit_eventually_plants_a_
## seed_of_the_same_species_elsewhere: what actually gets planted once the
## carry resolves must be the species that was picked up, not merely "some
## roll of FlowerSpecies.IDS".
func test_a_grazers_dispersed_flower_seed_plants_the_same_species_it_picked_up():
	manager.update(_berlin_tile)
	var season := manager.current_season()
	var species := ""
	for candidate in FlowerSpecies.IDS:
		if FlowerSpecies.is_in_bloom(candidate, season):
			species = candidate
			break
	assert_ne(species, "", "precondition: some species should be in bloom this season")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var pickup_at := Vector2.ZERO
	var planted := false
	for y in 8:
		for x in 8:
			var candidate_at := _pixel_for(chunk_coord, Vector2i(x, y))
			if manager.plant_flower_at(candidate_at, species):
				pickup_at = candidate_at
				planted = true
				break
		if planted:
			break
	assert_true(planted, "precondition: should find a plantable grassland cell near Berlin")
	var patch: FlowerPatch = manager._flower_patches[chunk_coord]
	# A grassland cell distinct from the pickup spot where a seed can actually
	# take, so a match below proves the RESOLVED planting actually names the
	# picked-up species, rather than trivially re-reading the original bloom,
	# which was never disturbed.
	#
	# "Empty" is not enough any more: a seed dropped in an established plant's
	# shade is outcompeted before it is a plant (FlowerEstablishment), so a
	# cell that merely has no flower ON it can still refuse one. This is the
	# same clearance FlowerPatch.plant itself applies -- the test has to pick a
	# spot the rule allows, not assert the rule away.
	var drop_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not FlowerEstablishment.is_clear(cell, patch.get_flower_cells()):
				continue
			if manager.biome_at_global(
				(chunk_coord.x * EarthChunkManager.CHUNK_SIZE) + x,
				(chunk_coord.y * EarthChunkManager.CHUNK_SIZE) + y
			) == "grassland":
				drop_cell = cell
				break
		if drop_cell != Vector2i(-1, -1):
			break
	assert_ne(
		drop_cell, Vector2i(-1, -1),
		"precondition: a second grassland cell clear of the meadow exists to drop into"
	)
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", pickup_at, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_seed_dispersal(horse)
	assert_eq(horse.carried_seed_species, species, "precondition: picked up the planted species")

	horse.position = _pixel_for(chunk_coord, drop_cell)
	horse.carried_seed_origin = horse.position - Vector2(
		(SeedDispersal.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
	)
	manager._step_seed_dispersal(horse)

	assert_eq(horse.carried_seed_species, "", "dropping empties the carried species")
	assert_eq(patch.species_at(drop_cell), species, "the planted species must match what was picked up")


## Same "too far to notice" gate SeedDispersal/SeedCaching's own siblings
## get, driven through the real EarthChunkManager wiring rather than just
## SquirrelNutCaching's own already-tested PICKUP_RADIUS_TILES constant.
func test_a_squirrel_too_far_from_a_fallen_nut_does_not_pick_it_up():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var nut_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(nut_pixel, "walnut"))
	var far_pixel := nut_pixel + Vector2(
		(SquirrelNutCaching.PICKUP_RADIUS_TILES + 2.0) * TerrainRenderer.TILE_SIZE, 0.0
	)
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", far_pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(squirrel.carried_nut_species, "", "too far away to notice the fallen nut")
	var still_there := false
	for fruit in manager.fruit_near(nut_pixel, 10):
		if fruit["position"].distance_to(nut_pixel) < 1.0:
			still_there = true
	assert_true(still_there, "a nut out of pickup range must be left on the ground")
	ground_items.free()


## Mirrors test_a_non_mouse_creature_does_not_cache_grass_seed -- only
## squirrels do this, not the whole "Forager" diet label (mice share that
## label but scatter-hoard grass seed, not nuts).
func test_a_non_squirrel_creature_does_not_cache_a_fallen_nut():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "walnut"))
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(horse)

	assert_eq(horse.carried_nut_species, "", "only squirrels cache nuts")
	var still_there := false
	for fruit in manager.fruit_near(pixel, 5):
		if fruit["position"].distance_to(pixel) < 1.0:
			still_there = true
	assert_true(still_there, "a horse must not take a fallen nut off the ground")
	ground_items.free()


## Symmetric to the mouse's own test_a_mouse_does_not_cache_before_
## travelling_its_carry_distance -- needs no loaded chunk at all: the
## too-early branch returns before touching any chunk state.
func test_a_squirrel_does_not_resolve_its_nut_before_travelling_its_carry_distance():
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)
	squirrel.carried_nut_species = "walnut"
	squirrel.carried_nut_origin = pixel  # has not moved at all yet

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(squirrel.carried_nut_species, "walnut", "too soon to resolve -- it hasn't gone anywhere yet")


## The majority branch (SquirrelNutCaching.NUT_CONSUMED_CHANCE, 0.7): a
## consumed nut must resolve WITHOUT also planting a sapling -- confirms
## try_plant_seed_at is genuinely skipped on this branch, not just that the
## pouch empties either way. Tried across several real forested tiles (see
## test_a_surviving_nut_plants_a_sapling_somewhere_forested_near_berlin,
## which confirms at least one of them accepts a planting) rather than a
## single position -- a lone untested tile might simply have had no room
## (try_plant_seed_at's own spacing/per-tile cap), which would make "nothing
## got planted" prove nothing about the consumed branch at all.
func test_a_consumed_nut_resolves_without_planting_a_sapling():
	manager.update(_berlin_tile)
	var consumed_seed := -1
	for candidate in range(60):
		if SquirrelNutCaching.nut_is_consumed(candidate, candidate):
			consumed_seed = candidate
			break
	assert_ne(consumed_seed, -1, "precondition: some seed should roll consumed")
	var before := entities_parent.get_child_count()
	var forested_tiles_tried := 0
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			if forested_tiles_tried >= 10:
				break
			var tile := _berlin_tile + Vector2i(dx, dy)
			if not ["forest", "rainforest"].has(manager.biome_at_global(tile.x, tile.y)):
				continue
			forested_tiles_tried += 1
			var pixel := Vector2(tile) * TerrainRenderer.TILE_SIZE
			var squirrel := manager._creature_renderer.spawn_single(
				creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE, consumed_seed
			)
			squirrel.carried_nut_species = "walnut"
			squirrel.carried_nut_origin = pixel - Vector2(
				(SquirrelNutCaching.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
			)
			manager._step_squirrel_nut_caching(squirrel)
			assert_eq(squirrel.carried_nut_species, "", "resolving empties the pouch either way")
		if forested_tiles_tried >= 10:
			break
	assert_gt(forested_tiles_tried, 0, "precondition: some forest/rainforest biome should be loaded near Berlin")
	assert_eq(
		entities_parent.get_child_count(), before,
		"a consumed nut must never plant a sapling, even across several real forested tiles"
	)


## The minority branch: a nut that survives handling must actually sprout a
## sapling via try_plant_seed_at -- confirms it is genuinely called, not
## just that the pouch empties either way. Tries several forested tiles near
## Berlin (mirrors test_try_plant_seed_at_plants_a_sapling_somewhere_
## forested_near_berlin) since not every forested tile has room -- a real
## forest is already dense with trees close to each other.
func test_a_surviving_nut_plants_a_sapling_somewhere_forested_near_berlin():
	manager.update(_berlin_tile)
	var surviving_seed := -1
	for candidate in range(60):
		if not SquirrelNutCaching.nut_is_consumed(candidate, candidate):
			surviving_seed = candidate
			break
	assert_ne(surviving_seed, -1, "precondition: some seed should roll surviving")
	var before := entities_parent.get_child_count()
	var planted := false
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var tile := _berlin_tile + Vector2i(dx, dy)
			if not ["forest", "rainforest"].has(manager.biome_at_global(tile.x, tile.y)):
				continue
			var pixel := Vector2(tile) * TerrainRenderer.TILE_SIZE
			var squirrel := manager._creature_renderer.spawn_single(
				creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE, surviving_seed
			)
			squirrel.carried_nut_species = "walnut"
			squirrel.carried_nut_origin = pixel - Vector2(
				(SquirrelNutCaching.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
			)
			manager._step_squirrel_nut_caching(squirrel)
			assert_eq(squirrel.carried_nut_species, "", "resolving empties the pouch either way")
			if entities_parent.get_child_count() > before:
				planted = true
				break
		if planted:
			break
	assert_true(planted, "a surviving nut should sprout a sapling somewhere forested near Berlin")


# -- hover tooltip: is there a grass patch under the cursor, and how grown --
#
# Grass has no per-tuft Node2D (see _sync_grass_sprites), so it cannot join
# HoverTargetFinder's group like every other hoverable entity. World special-
# cases it instead, reading this tile-based accessor directly.

func test_tall_grass_growth_at_reports_the_patchs_growth():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	var cell: Vector2i = sim.get_patch_cells()[0]
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var at := Vector2(
		float(origin.x + cell.x) + 0.5, float(origin.y + cell.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	assert_almost_eq(manager.tall_grass_growth_at(at), sim.get_growth(cell), 0.001)


func test_tall_grass_growth_at_is_negative_where_there_is_no_patch():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	var target_cell := Vector2i(-1, -1)
	for y in EarthChunkManager.CHUNK_SIZE:
		for x in EarthChunkManager.CHUNK_SIZE:
			var cell := Vector2i(x, y)
			if not sim.has_grass(cell):
				target_cell = cell
				break
		if target_cell != Vector2i(-1, -1):
			break
	assert_ne(target_cell, Vector2i(-1, -1), "precondition: an empty cell exists in this chunk")
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var at := Vector2(
		float(origin.x + target_cell.x) + 0.5, float(origin.y + target_cell.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	assert_lt(manager.tall_grass_growth_at(at), 0.0)


# -- wild crops: carrot, potato (see docs/concept/wild_crops.md) ------------
#
# Supersedes the old has_wild_carrot grass-harvest freebie -- a real wild
## carrot/potato patch grows, spreads, and is pulled directly now, so a
## second, disconnected way to get the same item would just be confusing.

func test_update_seeds_wild_crop_patches_for_loaded_regions_around_berlin():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_true(manager._wild_crop_sims.has(center_chunk))
	var sims: Dictionary = manager._wild_crop_sims[center_chunk]
	assert_true(sims.has("carrot"))
	assert_true(sims.has("potato"))


func test_update_spawns_wild_crop_markers_matching_the_sims_patch_cells():
	manager.update(_berlin_tile)
	var expected := 0
	for chunk_coord in manager._wild_crop_sims.keys():
		var sims: Dictionary = manager._wild_crop_sims[chunk_coord]
		for crop_id in sims:
			expected += sims[crop_id].get_patch_cells().size()
			expected += 0  # keeps the loop shape symmetric with the markers count below
	var spawned := 0
	for chunk_coord in manager._wild_crop_markers.keys():
		var markers_by_crop: Dictionary = manager._wild_crop_markers[chunk_coord]
		for crop_id in markers_by_crop:
			spawned += markers_by_crop[crop_id].size()
	assert_gt(spawned, 0, "precondition: at least one wild crop patch turned up around Berlin")
	assert_eq(spawned, expected)


func test_evicting_old_chunks_frees_wild_crop_state():
	manager.update(Vector2i(0, 0))
	var old_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	assert_true(manager._wild_crop_sims.has(old_chunk), "precondition: the old chunk had crop state")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager._wild_crop_sims.has(old_chunk))
	assert_false(manager._wild_crop_markers.has(old_chunk))


## step_wild_crops mirrors step_tall_grass's own throttled-accumulator shape
## -- growth actually advances once the refresh interval elapses.
## The `accelerate_growth` spell atom's real hook (see docs/concept/
## spell_runtime.md) -- same WildCropPatch.advance() step_wild_crops already
## calls on its own throttled clock, triggered instantly instead.
func test_accelerate_wild_crop_growth_advances_every_patch_in_the_chunk():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var sim: WildCropPatch = manager._wild_crop_sims[chunk_coord]["carrot"]
	var immature_cell := Vector2i(-1, -1)
	for cell in sim.get_patch_cells():
		if sim.get_growth(cell) < 1.0:
			immature_cell = cell
	if immature_cell == Vector2i(-1, -1):
		pass_test("precondition unmet (no immature carrot patch nearby this run) -- nothing to regress")
		return
	var before: float = sim.get_growth(immature_cell)

	var applied := manager.accelerate_wild_crop_growth(_berlin_tile, 500.0)

	assert_true(applied)
	assert_gt(sim.get_growth(immature_cell), before)


func test_accelerate_wild_crop_growth_returns_false_for_an_unloaded_chunk():
	var far_away_tile := Vector2i(5000, 5000)
	assert_false(manager.accelerate_wild_crop_growth(far_away_tile, 500.0))


func test_step_wild_crops_advances_growth_toward_maturity():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var sim: WildCropPatch = manager._wild_crop_sims[chunk_coord]["carrot"]
	var immature_cell := Vector2i(-1, -1)
	for cell in sim.get_patch_cells():
		if sim.get_growth(cell) < 1.0:
			immature_cell = cell
	if immature_cell == Vector2i(-1, -1):
		pass_test("precondition unmet (no immature carrot patch nearby this run) -- nothing to regress")
		return
	var before: float = sim.get_growth(immature_cell)
	manager.step_wild_crops(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	assert_gt(sim.get_growth(immature_cell), before)


## The marker actually reflects the sim's growth after a refresh, not just
## the sim itself -- otherwise a grown plant would sit there still drawn as
## a seedling until the player forced a reload.
func test_step_wild_crops_updates_marker_growth_too():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var sim: WildCropPatch = manager._wild_crop_sims[chunk_coord]["carrot"]
	var markers: Dictionary = manager._wild_crop_markers[chunk_coord]["carrot"]
	var immature_cell := Vector2i(-1, -1)
	for cell in sim.get_patch_cells():
		if sim.get_growth(cell) < 1.0:
			immature_cell = cell
	if immature_cell == Vector2i(-1, -1):
		pass_test("precondition unmet (no immature carrot patch nearby this run) -- nothing to check")
		return
	manager.step_wild_crops(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var marker: WildCropMarker = markers[immature_cell]
	assert_eq(marker.growth, sim.get_growth(immature_cell))


# -- wild crops and the season (see docs/concept/wild_crops.md "The season")
#
# WildCropPatch.advance grew a `season_growth` parameter and WildCropRenderer
# grew a `season_tint` one, both defaulted so an untaught caller sees exactly
# today's picture -- and step_wild_crops was that untaught caller, so both
# halves were inert in the running game. These pin the manager actually
# passing the season through, not the phenology itself (WildCropPatch's own
# tests have that). Share the `wild_crops_in_season` token so one narrowed
# -gunit_test_name run covers the set.

## A tint no season could produce by accident, so a pass cannot be the
## default Color.WHITE sitting there untouched.
const SEASON_PROBE_TINT := Color(0.25, 0.5, 0.75)


## Forces `cell` back to bare ground so a growth step is measurable.
## _seed_initial_patches hands every map-generated patch 1.0 (mature, like
## map-generated grass and trees), and clamped-at-maturity growth measures
## nothing -- immature cells otherwise only appear once spread has fired,
## which is a geographic accident of the run.
func _reset_crop_growth(sim: WildCropPatch, cell: Vector2i) -> void:
	sim._patches[cell] = 0.0


func test_wild_crops_in_season_grow_slower_in_winter_than_in_high_summer():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var sim: WildCropPatch = manager._wild_crop_sims[chunk_coord]["carrot"]
	var cells: Array = sim.get_patch_cells()
	assert_gt(cells.size(), 0, "precondition: a carrot patch turned up around Berlin")
	var cell: Vector2i = cells[0]
	var cycle := SeasonCycle.new()

	_reset_crop_growth(sim, cell)
	manager.set_world_age_seconds(cycle.seconds_until_season(0.0, "winter"))
	manager.step_wild_crops(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var winter_gain: float = sim.get_growth(cell)

	_reset_crop_growth(sim, cell)
	manager.set_world_age_seconds(cycle.seconds_until_season(0.0, "summer"))
	manager.step_wild_crops(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var summer_gain: float = sim.get_growth(cell)

	assert_lt(winter_gain, summer_gain, "the same tick ripened a carrot as fast in January as in July")
	# Dormancy, not death: growth_modifier's floor is 0.2, not 0 (see
	# docs/concept/seasons.md's "modulates, doesn't gate" rule). A winter tick
	# that moved nothing would pass the comparison above for the wrong reason.
	assert_gt(winter_gain, 0.0, "a root crop goes dormant in winter, it does not stop")


func test_wild_crops_in_season_tint_their_tops_on_a_step():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var markers: Dictionary = manager._wild_crop_markers[chunk_coord]["carrot"]
	assert_gt(markers.size(), 0, "precondition: a carrot patch turned up around Berlin")

	manager.set_season_tint(SEASON_PROBE_TINT)
	manager.step_wild_crops(EarthChunkManager.GRASS_REFRESH_INTERVAL)

	for cell in markers:
		assert_eq(
			markers[cell].season_tint,
			SEASON_PROBE_TINT,
			"a crop top already on screen never learns the season turned"
		)


## A chunk streamed in during winter has to arrive ALREADY dead-topped.
## Tinting it only on the next step_wild_crops tick means it pops in summer
## green and corrects itself up to GRASS_REFRESH_INTERVAL later, in plain
## sight, every time the player walks over a chunk boundary.
func test_wild_crops_in_season_spawn_already_tinted_at_chunk_load():
	manager.set_season_tint(SEASON_PROBE_TINT)
	manager.update(_berlin_tile)

	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var markers: Dictionary = manager._wild_crop_markers[chunk_coord]["carrot"]
	assert_gt(markers.size(), 0, "precondition: a carrot patch turned up around Berlin")
	for cell in markers:
		assert_eq(
			markers[cell].season_tint,
			SEASON_PROBE_TINT,
			"a newly streamed chunk popped in summer-green in the middle of winter"
		)


# -- decomposers: ants, carrion bugs (see docs/concept/carrion.md) ----------

func test_update_spawns_decomposers_for_loaded_regions_around_berlin():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	assert_true(manager._decomposer_markers.has(center_chunk))
	assert_gt(manager._decomposer_markers[center_chunk].size(), 0)


func test_evicting_old_chunks_frees_decomposer_markers():
	manager.update(Vector2i(0, 0))
	var old_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	assert_true(manager._decomposer_markers.has(old_chunk), "precondition: the old chunk had decomposers")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager._decomposer_markers.has(old_chunk))


# -- ant colonies: visible mounds + traveling foragers (see docs/concept/
# soil_fauna.md "Ants: myrmecochory", AntColony) -- previously a pure
# background population effect with zero rendered presence at all (reported
# live: "ants should be a real gear in the ecosystem"). -----------------

## Unlike decomposers (a GUARANTEED min count per land-biome chunk), mound
## placement is genuinely probabilistic per cell (AntColony.MOUND_CHANCE) --
## Berlin's own chunk is not guaranteed a nonzero count. The real invariant
## worth pinning is that the rendered marker count always exactly matches
## the real mound_cells() count, whatever that happens to be.
func test_update_spawns_a_visible_marker_for_every_real_ant_mound_around_berlin():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var colony: AntColony = manager._ant_colonies[center_chunk]
	assert_true(manager._ant_mound_markers.has(center_chunk))
	assert_eq(manager._ant_mound_markers[center_chunk].size(), colony.mound_cells().size())


## A standalone colony guaranteed at least one mound -- for tests of the
## dispatch/cap logic below, which never touches grass/fruit/chunk data at
## all, so there is no need to pay for a real (and, per this file's own
## documented cost, very slow) manager.update() just to get one.
func _ant_colony_with_one_mound() -> AntColony:
	var biome := PackedStringArray()
	for i in 64:
		biome.append("grassland")
	for seed_value in range(50):
		var colony := AntColony.new(seed_value, 8, 8, biome)
		if not colony.mound_cells().is_empty():
			return colony
	fail_test("expected at least one of 50 seeds to place a mound in an all-grassland 8x8 grid")
	return null


func test_evicting_old_chunks_frees_ant_mound_markers():
	manager.update(Vector2i(0, 0))
	var old_chunk := _chunk_coord_for_tile(Vector2i(0, 0))
	assert_true(manager._ant_mound_markers.has(old_chunk), "precondition: the old chunk had a mound-marker entry")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager._ant_mound_markers.has(old_chunk))


# -- leaf litter rendering: one MultiMeshInstance2D per chunk (see
# LeafLitterRenderer, docs/concept/leaf_litter.md) -- mirrors the ant-mound-
# marker lifecycle tests just above, but _load_chunk/_unload_chunk directly
# rather than the slow real update() -- this file's own CONTRIBUTING.md notes
# on why a real update() call is expensive; nothing about THIS wiring needs
# a real streaming pass, only a single chunk's own load/unload.

func test_load_chunk_creates_a_leaf_litter_multimesh_parented_under_ground_decor():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	assert_true(manager._leaf_litter_mmis.has(chunk_coord))
	var mmi: MultiMeshInstance2D = manager._leaf_litter_mmis[chunk_coord]
	assert_eq(mmi.get_parent(), entities_parent, "ground decor falls back to entities_parent with no dedicated layer (see _ground_decor_parent's own doc comment)")


func test_unload_chunk_frees_its_leaf_litter_multimesh():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	var mmi: MultiMeshInstance2D = manager._leaf_litter_mmis[chunk_coord]

	manager._unload_chunk(chunk_coord)

	assert_false(manager._leaf_litter_mmis.has(chunk_coord))
	assert_true(not is_instance_valid(mmi) or mmi.is_queued_for_deletion())


## nearest_leaf_litter_near/consume_leaf_litter_at/disperse_leaf_litter_near
## mirror worms_near/take_seed_at's own single-chunk-injection test style --
## fast (no real chunk load needed), since these are mechanical 3x3-chunk-
## neighbourhood passthroughs to LeafLitterField's own already-tested
## methods (see test_leaf_litter_field.gd for the actual placement/roll
## math).

func _field_at(chunk_coord: Vector2i) -> LeafLitterField:
	if not manager._leaf_litter_fields.has(chunk_coord):
		manager._leaf_litter_fields[chunk_coord] = LeafLitterField.new()
	return manager._leaf_litter_fields[chunk_coord]


func test_nearest_leaf_litter_near_finds_a_leaf_in_the_center_chunk():
	var field := _field_at(Vector2i(0, 0))
	field.add_leaf(Vector2(10, 10), "cherry", "autumn", 0.0)
	var found := manager.nearest_leaf_litter_near(Vector2(12, 10), 20.0)
	assert_eq(found.get("species"), "cherry")


func test_nearest_leaf_litter_near_reaches_into_a_neighbouring_chunk():
	var chunk_size_px := EarthChunkManager.CHUNK_SIZE * TerrainRenderer.TILE_SIZE
	# Just across the boundary into chunk (1, 0), close to the query point in
	# chunk (0, 0) -- only the 3x3-neighbourhood scan can find this.
	var neighbour_position := Vector2(chunk_size_px + 5.0, 10.0)
	var field := _field_at(Vector2i(1, 0))
	field.add_leaf(neighbour_position, "acorn", "autumn", 0.0)
	var found := manager.nearest_leaf_litter_near(Vector2(chunk_size_px - 5.0, 10.0), 20.0)
	assert_eq(found.get("species"), "acorn")


func test_consume_leaf_litter_at_removes_a_real_leaf_and_reports_success():
	var field := _field_at(Vector2i(0, 0))
	field.add_leaf(Vector2(10, 10), "cherry", "autumn", 0.0)
	assert_true(manager.consume_leaf_litter_at(Vector2(10, 10)))
	assert_eq(field.leaves().size(), 0)


func test_consume_leaf_litter_at_misses_an_empty_position():
	assert_false(manager.consume_leaf_litter_at(Vector2(10, 10)))


func test_disperse_leaf_litter_near_can_relocate_a_settled_leaf():
	var field := _field_at(Vector2i(0, 0))
	field.add_leaf(Vector2(100, 100), "cherry", "autumn", 0.0)
	field.advance(1.0, LeafLitterField.TRANSITION_DURATION + 0.1)  # settle first
	var moved := false
	for attempt in 50:
		manager.set_world_age_seconds(10.0 + attempt)
		if manager.disperse_leaf_litter_near(Vector2(102, 100)):
			moved = true
			break
	assert_true(moved, "a leaf this light should disperse within 50 contact rolls")


func test_disperse_leaf_litter_near_misses_with_nothing_nearby():
	assert_false(manager.disperse_leaf_litter_near(Vector2(900, 900)))


## step_leaf_litter is what actually fills the MultiMesh from the field's own
## current leaves -- proven here by a leaf the test injects directly into the
## chunk's field (mirroring this file's own "poke internal state directly"
## convention), then checking the MultiMesh picked it up. This can only prove
## the ENGINE-VISIBLE instance_count/transform_format wiring, not that the
## GPU actually draws the right pixels -- see test_leaf_litter_renderer_
## smoke.gd for that.
func test_step_leaf_litter_fills_the_multimesh_from_the_fields_current_leaves():
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	manager._load_chunk(chunk_coord)
	# _decorates gates the fill on decoration range (see step_leaf_litter's
	# own doc comment) -- a bare _load_chunk (unlike a real update()) never
	# centres decoration on the chunk it just loaded, so this pokes that
	# internal directly, the same "reach into manager state" convention this
	# whole file already relies on.
	manager._decoration_center = chunk_coord
	var field: LeafLitterField = manager._leaf_litter_fields[chunk_coord]
	field.add_leaf(Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE, "cherry", "autumn", 0.0)

	manager.step_leaf_litter(0.016)

	var mmi: MultiMeshInstance2D = manager._leaf_litter_mmis[chunk_coord]
	assert_not_null(mmi.multimesh, "step_leaf_litter must build the MultiMesh once there is a leaf to show")
	assert_eq(mmi.multimesh.instance_count, 1)


## Real foraging now (see docs/concept/soil_fauna.md "Real foraging: a
## round trip, not an instant resolve"): dispatching a forager no longer
## takes the seed on the spot -- that only happens once the forager itself
## has genuinely walked to it (see AntForagerMarker). This proves the
## dispatch half: a real candidate is found and a real forager is sent
## after it, carrying the real colony/cell/target it needs to resolve the
## rest for itself. A synthetic mound cell placed directly on top of a
## real shed seed (rather than hoping a real AntColony mound happened to
## roll next to one) keeps this deterministic regardless of mound
## placement.
func test_a_successful_grass_seed_forage_dispatches_a_real_forager_at_the_seed():
	manager.update(_berlin_tile)
	for i in 40:
		manager.step_tall_grass(EarthChunkManager.GRASS_REFRESH_INTERVAL)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var seeds: Array = manager.grass_seeds_near(centre, 40)
	assert_gt(seeds.size(), 0, "precondition: a real shed seed exists to forage")
	var seed_position: Vector2 = seeds[0]["position"]

	var seed_tile := manager._world_tile_for_pixel(seed_position)
	var chunk_coord := manager._chunk_coord_for_tile(seed_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var cell: Vector2i = seed_tile - origin
	var colony: AntColony = manager._ant_colonies[chunk_coord]
	var global_tile := origin + cell

	var before_children := manager._entities_parent.get_child_count()
	manager._forage_seed_near_mound(colony, origin, cell)

	assert_gt(
		manager._entities_parent.get_child_count(), before_children,
		"a real, successful forage should dispatch a visible forager sprite"
	)
	assert_true(manager._active_ant_foragers.has(global_tile))
	var forager: AntForagerMarker = manager._active_ant_foragers[global_tile][0]
	assert_eq(forager.target_position, seed_position, "the forager should be sent at the REAL seed position")
	assert_true(seeds.any(func(s): return s["position"] == seed_position))
	# The take has NOT happened yet -- only the forager's own real arrival
	# resolves it now (see test_ant_forager_marker.gd's own coverage of
	# that). Confirmed here by the seed still being reachable, not taken.
	assert_gt(manager.grass_seeds_near(centre, 40).size(), 0, "the seed must still be there until the ant arrives")


## AntColony.FORAGE_CHANCE can succeed several times a second per mound at
## normal frame rate -- a new visible ant for every single one would be a
## flicker of overlapping sprites, not a colony reading as alive. Uses a
## standalone AntColony (not manager.update()'s real, slow chunk load,
## which this dispatch-only logic never actually touches) at its own
## founding population, whose active_forager_cap_at is exactly 1.
func test_does_not_spawn_a_second_forager_for_a_mound_already_at_its_own_cap():
	var colony := _ant_colony_with_one_mound()
	var cell: Vector2i = colony.mound_cells()[0]
	assert_eq(colony.active_forager_cap_at(cell), 1, "precondition: a founding colony's cap is exactly one")
	var global_tile := Vector2i(123_456, 123_456)  # arbitrary -- does not need to be a real mound
	var mound_pixel := Vector2(global_tile) * TerrainRenderer.TILE_SIZE
	var before := manager._entities_parent.get_child_count()

	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(10, 0), "seed")
	assert_eq(manager._entities_parent.get_child_count(), before + 1, "precondition: the first spawn landed")

	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(-10, 0), "seed")
	assert_eq(
		manager._entities_parent.get_child_count(), before + 1,
		"a second forager for a mound already at its own cap should not spawn while the first is still out"
	)


## Once a mound's population has genuinely grown, its cap allows MORE than
## one concurrent forager -- replacing the old hardcoded single-forager
## limit (see docs/concept/soil_fauna.md "A queen, and where a colony's
## size comes from").
func test_dispatches_a_second_forager_once_the_mounds_own_cap_allows_it():
	var colony := _ant_colony_with_one_mound()
	var cell: Vector2i = colony.mound_cells()[0]
	for i in 20:
		colony.record_forage_result(cell, true)  # saturate the recent-success EMA first
	# advance() integrates the logistic curve with real (Euler) steps, not a
	# closed-form solution -- one giant delta_seconds jump under-integrates
	# it badly (a single step extrapolates from the STARTING slope only),
	# so this simulates many moderate simulated-days instead, matching how
	# advance() is actually called many times over real elapsed play.
	for i in 200:
		colony.advance(AntColony.SECONDS_PER_SIMULATED_DAY)  # one simulated day per call
	assert_gt(colony.active_forager_cap_at(cell), 1, "precondition: a long-thriving colony should allow more than one")
	var global_tile := Vector2i(654_321, 654_321)
	var mound_pixel := Vector2(global_tile) * TerrainRenderer.TILE_SIZE
	var before := manager._entities_parent.get_child_count()

	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(10, 0), "seed")
	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(-10, 0), "seed")

	assert_eq(
		manager._entities_parent.get_child_count(), before + 2,
		"a thriving colony's second forager should be allowed out alongside the first"
	)


## Once an out forager finishes its trip (frees itself), a new one may be
## dispatched again even at a cap of 1 -- the slot is per ACTIVE forager,
## not a one-time-ever limit.
func test_a_finished_forager_frees_its_slot_for_a_new_one():
	var colony := _ant_colony_with_one_mound()
	var cell: Vector2i = colony.mound_cells()[0]
	var global_tile := Vector2i(111_111, 111_111)
	var mound_pixel := Vector2(global_tile) * TerrainRenderer.TILE_SIZE

	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(10, 0), "seed")
	var first: AntForagerMarker = manager._active_ant_foragers[global_tile][0]
	first.free()

	var before := manager._entities_parent.get_child_count()
	manager._dispatch_ant_forager(global_tile, colony, cell, mound_pixel, mound_pixel + Vector2(-10, 0), "seed")
	assert_eq(manager._entities_parent.get_child_count(), before + 1, "a freed slot should accept a new forager")


# -- Sägewerk: "an NPC moves in" the moment the worksite exists (see
# docs/concept/timber_construction.md) -- exactly one LumberjackMarker per
# placed Sägewerk instance, mirroring the decomposer/wild-crop per-chunk
# spawn/despawn lifecycle above.

func test_building_a_sagewerk_spawns_a_lumberjack():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_true(manager._sagewerk_lumberjacks.has(chunk_coord))
	assert_gt(manager._sagewerk_lumberjacks[chunk_coord].size(), 0)


func test_building_a_sagewerk_twice_on_the_same_tile_spawns_only_one_lumberjack():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_eq(manager._sagewerk_lumberjacks[chunk_coord].size(), 1)


func test_destroying_a_sagewerk_despawns_its_lumberjack():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_gt(manager._sagewerk_lumberjacks[chunk_coord].size(), 0, "precondition: a lumberjack moved in")

	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)

	assert_eq(manager._sagewerk_lumberjacks[chunk_coord].size(), 0)


func test_overwriting_a_sagewerk_with_a_different_structure_despawns_its_lumberjack():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)

	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "campfire")

	assert_eq(manager._sagewerk_lumberjacks[chunk_coord].size(), 0)


func test_evicting_a_chunk_frees_its_sagewerk_lumberjacks():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_true(manager._sagewerk_lumberjacks.has(chunk_coord), "precondition")

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)

	assert_false(manager._sagewerk_lumberjacks.has(chunk_coord))
	_remove_persisted_modifications(chunk_coord)


## A previously-built Sägewerk persists as an ordinary chunk modification
## (see build_at_global's own doc comment) -- reloading that chunk must
## re-staff it with a fresh Lumberjack, not leave it abandoned, the same
## "an NPC moves in" guarantee a freshly-placed one gets.
func test_reloading_a_chunk_with_a_persisted_sagewerk_respawns_its_lumberjack():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)

	var far_away_tile := Vector2i(500 * EarthChunkManager.CHUNK_SIZE, 500 * EarthChunkManager.CHUNK_SIZE)
	manager.update(far_away_tile)
	assert_false(manager._sagewerk_lumberjacks.has(chunk_coord), "precondition: chunk was evicted")

	manager.update(_berlin_tile)

	assert_true(manager._sagewerk_lumberjacks.has(chunk_coord))
	assert_gt(manager._sagewerk_lumberjacks[chunk_coord].size(), 0)
	_remove_persisted_modifications(chunk_coord)


# -- Storage/Logistics: "if both production buildings and storage exist, new
# NPCs may move in which handle logistics" (docs/concept/timber_
# construction.md's "Storage, logistics, and the autonomous dependency
# chain" section) -- one worker-pair (one LogisticsMarker per real output
# item id, _SAGEWERK_LOGISTICS_ITEM_IDS: beam, plank) per real Storage
# within SAGEWERK_STORAGE_PAIR_RADIUS_TILES of a real Sägewerk -- EVERY
# real Storage in range, not just the single nearest one (this closes this
# doc's own previously-named honest constraint). Keyed off the Sägewerk's
# own cell, then by each paired Storage's own identity, mirroring
# _sagewerk_lumberjacks' per-chunk dict-of-cells shape one level deeper.

## Total LogisticsMarker count across every Storage paired to the Sägewerk
## at (chunk_coord, local_cell) -- sums each storage-keyed pair's own
## item-keyed worker count, so a test doesn't need to know the internal
## storage-key format to assert "N workers total."
func _logistics_worker_count(chunk_coord: Vector2i, local_cell: Vector2i) -> int:
	var total := 0
	for by_item in manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {}).values():
		total += by_item.size()
	return total


func test_a_sagewerk_with_no_nearby_storage_spawns_no_logistics_workers():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)

	assert_true(
		manager._logistics_workers.get(chunk_coord, {}).is_empty(),
		"no Storage nearby -- nothing real for a Logistics worker to carry to"
	)


func test_a_sagewerk_with_a_nearby_storage_spawns_exactly_two_logistics_workers():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)

	var by_storage: Dictionary = manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {})
	assert_eq(by_storage.size(), 1, "exactly one real Storage in range -- one worker-pair")
	var by_item: Dictionary = by_storage.values()[0]
	assert_eq(by_item.size(), 2, "one worker per real Sägewerk output item (beam, plank)")
	assert_true(by_item.has("beam"))
	assert_true(by_item.has("plank"))


## Building the Storage first (before the Sägewerk exists) still ends up
## staffed once the Sägewerk itself is placed -- the pairing doesn't depend
## on build order.
func test_a_storage_built_before_its_sagewerk_still_gets_paired():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)

	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 2)


func test_re_syncing_a_staffed_sagewerk_does_not_double_spawn_logistics_workers():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)

	# A second, redundant build on an UNRELATED nearby tile re-triggers the
	# storage-changed resync path (see _sync_logistics_workers) without
	# touching the Sägewerk or Storage tiles themselves.
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")

	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 2)


func test_destroying_the_sagewerk_despawns_its_logistics_workers():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 2, "precondition")

	manager.destroy_at_global(_berlin_tile.x, _berlin_tile.y)

	assert_true(manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {}).is_empty())


func test_destroying_the_paired_storage_despawns_its_logistics_workers():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 2, "precondition")

	manager.destroy_at_global(_berlin_tile.x + 2, _berlin_tile.y)

	assert_true(manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {}).is_empty())


## The actual fix: TWO real Storages within range of one Sägewerk each get
## their own real worker-pair -- four workers total, not two. This is the
## direct test of this doc's previously-named honest constraint ("a Sägewerk
## pairs with only its single nearest Storage, not every Storage within
## range") now being closed.
func test_two_storages_within_range_each_get_their_own_worker_pair():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	manager.build_at_global(_berlin_tile.x + 2, _berlin_tile.y, "storage")
	manager.build_at_global(_berlin_tile.x - 2, _berlin_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)

	var by_storage: Dictionary = manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {})
	assert_eq(by_storage.size(), 2, "both real Storages in range get their own pair")
	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 4, "two workers per pair, two pairs")
	for by_item in by_storage.values():
		assert_true(by_item.has("beam"))
		assert_true(by_item.has("plank"))


## Each pair's own real deliveries land in ITS OWN paired Storage's stock --
## not funneled to whichever Storage nearest_structure_position would pick
## from the worker's own position, which (before this fix) would have been
## the SAME single storage for every worker regardless of which one it was
## nominally paired with. The far storage is placed further from the
## Sägewerk than the near one but still within SAGEWERK_STORAGE_PAIR_RADIUS_
## TILES -- under the old bug, its own paired worker would have delivered to
## the NEAR storage instead (whichever nearest_structure_position picked),
## so a delivery actually landing at the far storage is the real proof.
func test_each_paired_storage_receives_its_own_deliveries_not_the_nearest_ones():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var near_storage_tile := _berlin_tile + Vector2i(2, 0)
	var far_storage_tile := _berlin_tile + Vector2i(18, 0)
	manager.build_at_global(near_storage_tile.x, near_storage_tile.y, "storage")
	manager.build_at_global(far_storage_tile.x, far_storage_tile.y, "storage")
	manager.deposit_to_structure_at(_berlin_tile.x, _berlin_tile.y, "beam", 8)

	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	var by_storage: Dictionary = manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {})
	assert_eq(by_storage.size(), 2, "precondition: both Storages paired")

	var beam_markers: Array = []
	for by_item in by_storage.values():
		beam_markers.append(by_item["beam"])

	for i in 800:
		for beam_marker in beam_markers:
			beam_marker._process(0.25)
		if (
			manager.structure_stock_at(near_storage_tile.x, near_storage_tile.y, "beam") > 0
			and manager.structure_stock_at(far_storage_tile.x, far_storage_tile.y, "beam") > 0
		):
			break

	assert_gt(
		manager.structure_stock_at(near_storage_tile.x, near_storage_tile.y, "beam"), 0,
		"the near storage's own paired worker delivers to it"
	)
	assert_gt(
		manager.structure_stock_at(far_storage_tile.x, far_storage_tile.y, "beam"), 0,
		"the far storage's own paired worker delivers to it too -- not funneled to the nearer one"
	)


## Removing one of two paired Storages despawns only that Storage's own
## worker-pair -- the other Storage's own workers keep running undisturbed.
func test_destroying_one_of_two_paired_storages_despawns_only_its_own_pair():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "sagewerk")
	var storage_a_tile := _berlin_tile + Vector2i(2, 0)
	var storage_b_tile := _berlin_tile + Vector2i(-2, 0)
	manager.build_at_global(storage_a_tile.x, storage_a_tile.y, "storage")
	manager.build_at_global(storage_b_tile.x, storage_b_tile.y, "storage")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var local_cell := manager._local_coord(_berlin_tile.x, _berlin_tile.y)
	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 4, "precondition: two pairs")

	manager.destroy_at_global(storage_a_tile.x, storage_a_tile.y)

	var by_storage: Dictionary = manager._logistics_workers.get(chunk_coord, {}).get(local_cell, {})
	assert_eq(by_storage.size(), 1, "only storage_a's own pair despawns")
	assert_eq(_logistics_worker_count(chunk_coord, local_cell), 2, "storage_b's own pair keeps running")


# -- the periodic ecosystem refresh must not rebuild the world ---------------
#
# step_ecosystem freed EVERY creature marker in EVERY loaded chunk once a
# minute and respawned them from their deterministic spawn points (reported:
# "every N seconds horses and deer disappear and respawn at original spawn
# point"). Beyond the teleport, it wiped every scrap of per-animal state --
# hunger, energy, and, once taming existed, trust and tamed status -- so a
# horse the player had spent five carrots taming was deleted and replaced by a
# wild one a minute later.
#
# Like the 30-second reproduction cooldown and the twice-a-minute fruiting
# cycle, it only ever looked survivable because the ecology simulation was
# never actually running (see World.owns_ecosystem_simulation_for).

func _loaded_creature_list() -> Array:
	var all: Array = []
	for chunk_coord in manager._loaded_creatures.keys():
		for creature in manager._loaded_creatures[chunk_coord]:
			if is_instance_valid(creature):
				all.append(creature)
	return all


func test_the_ecosystem_refresh_keeps_the_animals_that_are_already_there():
	manager.update(_berlin_tile)
	var before := _loaded_creature_list()
	assert_gt(before.size(), 0, "precondition: Berlin has animals")
	var kept_id: int = before[0].get_instance_id()
	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY + 0.1)
	var survivors := 0
	for creature in _loaded_creature_list():
		if creature.get_instance_id() == kept_id:
			survivors += 1
	assert_eq(survivors, 1, "the same animal must still be the same animal after a refresh")


## The teleport itself: an animal that has walked somewhere must still be
## where it walked to, not back at the point it spawned.
func test_an_animal_is_not_teleported_back_to_its_spawn_point():
	manager.update(_berlin_tile)
	var animals := _loaded_creature_list()
	assert_gt(animals.size(), 0, "precondition: Berlin has animals")
	var walker = animals[0]
	var walked_to: Vector2 = walker.position + Vector2(97, -63)
	walker.position = walked_to
	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY + 0.1)
	assert_true(is_instance_valid(walker), "it should not have been freed")
	assert_eq(walker.position, walked_to, "it should still be where it walked to")


## What the churn actually destroyed: everything the player had invested in
## the animal.
func test_a_tamed_animal_survives_the_refresh_with_its_trust_intact():
	manager.update(_berlin_tile)
	var animals := _loaded_creature_list()
	assert_gt(animals.size(), 0, "precondition: Berlin has animals")
	var pet = animals[0]
	pet.trust = 1.0
	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY + 0.1)
	assert_true(is_instance_valid(pet), "a tamed animal must not be freed by a refresh")
	assert_eq(pet.trust, 1.0)


## The refresh still has a job: tracking the aggregate population. It just
## does it by adding and removing rather than by rebuilding.
func test_the_refresh_still_tracks_the_population_downward():
	manager.update(_berlin_tile)
	var before := _loaded_creature_list().size()
	assert_gt(before, 0, "precondition: Berlin has animals")
	for chunk_coord in manager._loaded_chunks.keys():
		manager._ecosystem.seed_populations(chunk_coord, 0.0, 0.0)
	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY + 0.1)
	assert_lt(_loaded_creature_list().size(), before, "a crashed population should thin out")


## ... but never by culling the animal the player has invested in.
func test_a_crashed_population_still_does_not_cull_the_players_pet():
	manager.update(_berlin_tile)
	var animals := _loaded_creature_list()
	assert_gt(animals.size(), 0, "precondition: Berlin has animals")
	var pet = animals[0]
	pet.trust = 1.0
	for chunk_coord in manager._loaded_chunks.keys():
		manager._ecosystem.seed_populations(chunk_coord, 0.0, 0.0)
	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY + 0.1)
	assert_true(is_instance_valid(pet), "the herd can crash; your horse does not vanish with it")


# -- courting butterflies cannot fill the sky --------------------------------
#
# Courtship gives flyers births (see Courtship), and a population with births
# and no ceiling only goes one way: the flyer count was measured climbing
# steadily across a single session, which is exactly how the deer explosion
# started.

func test_courting_flyers_stop_breeding_once_the_chunk_is_full():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	if not manager._loaded_ambient_flyers.has(chunk_coord):
		return  # no flyers loaded here; nothing to overfill
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	for _i in 400:
		manager.spawn_flyer_offspring("monarch", centre)
	# Measured against the ceiling for THIS meadow, not the bare-ground one.
	# Berlin's chunk is full of flowers, so its pollinator budget is scaled up
	# (see AmbientFlyerRenderer.scented_budget) -- comparing a scented chunk
	# against the unscented sum is the same stale-number mistake the guard
	# itself used to make, and it read as "the cap leaks" when the cap was
	# working and the yardstick was wrong.
	assert_lte(
		manager._loaded_ambient_flyers[chunk_coord].size(),
		AmbientFlyerRenderer.max_flyers_per_chunk(
			manager._pollinator_multiplier_for(chunk_coord)
		),
		"a meadow supports what it supports"
	)


## ...and the aggregate hears about the ones that DID happen, so a birth in
## front of the player is not lost when the chunk unloads.
func test_a_flyer_birth_is_reported_to_the_regions_population():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	if not manager._loaded_ambient_flyers.has(chunk_coord):
		return
	manager._ecosystem.seed_populations(chunk_coord, 0.1, 0.0)
	var before: float = manager._ecosystem.herbivore_population(chunk_coord)
	manager.spawn_flyer_offspring("monarch", Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE)
	assert_gt(
		manager._ecosystem.herbivore_population(chunk_coord), before,
		"an individual birth must move the aggregate it belongs to"
	)


# -- land ecology survives a real restart ------------------------------------
#
# Fish already persisted; herbivores, predators and vegetation lived only in
# the in-memory `_unloaded_ecology` record, so quitting the game reset every
# region to a freshly-seeded population at full carrying capacity. A herd the
# player hunted down, or one they watched grow, was back to default next
# launch -- which on a life cycle measured in real days (see LifeCycle) means
# the timescale could never mean anything.

func test_unloading_a_chunk_writes_its_land_ecology_to_disk():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var path: String = manager._ecology_path(chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	# Walk far enough that Berlin's chunks are evicted.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))
	assert_true(FileAccess.file_exists(path), "an unloaded region must leave a record")
	DirAccess.remove_absolute(path)


## The point of persisting it: a region the player emptied is still empty when
## they come back in a later session, rather than re-seeded at full capacity.
##
## Exercises the restore path directly rather than building a second world:
## constructing a whole EarthChunkManager against detached nodes is a lot of
## machinery to stand up for one question, and the question is whether a saved
## record actually overrides the fresh seeding.
func test_a_region_emptied_in_a_past_session_does_not_come_back_full():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var capacity: float = manager._ecosystem.herbivore_capacity_at(chunk_coord)
	assert_gt(capacity, 0.0, "precondition: Berlin supports herbivores")
	assert_gt(
		manager._ecosystem.herbivore_population(chunk_coord), capacity * 0.5,
		"precondition: a freshly-seeded region starts near capacity"
	)

	# The record a previous session would have left: hunted out, saved just
	# now so barely any catch-up time has passed.
	DirAccess.make_dir_recursive_absolute(EarthChunkManager.ECOLOGY_DIR)
	manager._chunk_serializer.save_ecology(
		{
			"herbivores": 0.0, "predators": 0.0, "vegetation": 0.5,
			"saved_at_unix": Time.get_unix_time_from_system(),
		},
		manager._ecology_path(chunk_coord)
	)
	manager._apply_persisted_ecology(chunk_coord)
	assert_lt(
		manager._ecosystem.herbivore_population(chunk_coord), capacity * 0.5,
		"a hunted-out region must not be re-seeded at full capacity"
	)
	DirAccess.remove_absolute(manager._ecology_path(chunk_coord))


## A region with no saved record keeps the freshly-seeded population -- a
## world the player has never visited should look like a living one, not an
## empty one.
func test_a_region_never_visited_before_keeps_its_fresh_population():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	if FileAccess.file_exists(manager._ecology_path(chunk_coord)):
		DirAccess.remove_absolute(manager._ecology_path(chunk_coord))
	var before: float = manager._ecosystem.herbivore_population(chunk_coord)
	manager._apply_persisted_ecology(chunk_coord)
	assert_almost_eq(manager._ecosystem.herbivore_population(chunk_coord), before, 0.001)


# -- land health: overharvesting leaves a lasting mark ------------------------
#
# docs/concept/world.md "Land health: overharvesting leaves a lasting mark,
# not just a slower respawn". land_health_near/record_vegetation_harvest_near
# mirror the existing vegetation_density_near/fish_population_near/
# record_fish_catch_near "_near" accessor pattern exactly.

func test_land_health_near_matches_the_chunks_land_health():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_almost_eq(
		manager.land_health_near(pixel), manager._ecosystem.land_health(center_chunk), 0.001
	)


## A freshly-loaded, never-touched region is pristine.
func test_land_health_near_starts_at_full_health():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	assert_almost_eq(manager.land_health_near(pixel), 1.0, 0.001)


func test_record_vegetation_harvest_near_reduces_the_right_chunks_density():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	var before := manager.vegetation_density_near(pixel)
	manager.record_vegetation_harvest_near(pixel, 0.1)
	assert_lt(manager.vegetation_density_near(pixel), before)


# -- grazing (horses/sheep) is a real land-health depletion driver too, the
# same way a working farmer NPC already is (see NpcEconomy._gather) --
# previously TallGrass's cosmetic per-tuft sim and EcosystemSimulation's
# aggregate land-health density never spoke, so no amount of grazing ever
# moved vegetation_density_near/land_health_near, no matter how bare a field
# got. Both real grazing paths (GrazerForaging's deliberate walk-to-a-tuft
# bite via graze_grass_at, AND the ambient any-non-predator-standing-on-
# mature-grass sweep via _graze_by_herbivores) must leave the same real mark.

## Mirrors test_record_vegetation_harvest_near_reduces_the_right_chunks_
## density's own shape, but through the real player-observed grazing bite
## instead of an invented amount.
func test_graze_grass_at_records_a_real_vegetation_harvest():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "precondition: something to graze")
	var eaten: Vector2 = tufts[0].position
	var before := manager.vegetation_density_near(eaten)
	assert_true(manager.graze_grass_at(eaten), "precondition: the bite lands")
	assert_lt(
		manager.vegetation_density_near(eaten), before,
		"a real grazing bite must leave a real mark on land health's own density field, not just the cosmetic tuft layer"
	)


## The other real grazing path -- ambient herbivore-standing-on-grass,
## driven by _graze_by_herbivores rather than GrazerForaging's deliberate
## bite -- must leave the same real mark for the same reason: a wandering
## horse or sheep grazing where its wander happened to take it is genuine
## herbivore pressure too, not just a horse that deliberately walked to a
## sensed tuft.
func test_ambient_herbivore_grazing_records_a_real_vegetation_harvest():
	manager.update(_berlin_tile)
	var centre := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var tufts: Array = manager.grass_near(centre, 40)
	assert_gt(tufts.size(), 0, "precondition: something to graze")
	var tuft_position: Vector2 = tufts[0].position
	var tuft_tile := manager._world_tile_for_pixel(tuft_position)
	_tame_a_horse_here(tuft_tile)
	var before := manager.vegetation_density_near(tuft_position)
	manager._graze_by_herbivores()
	assert_lt(
		manager.vegetation_density_near(tuft_position), before,
		"a horse standing on a mature tuft must deplete land health's density field, not just the cosmetic tuft layer"
	)


# -- land health survives a real restart (same persistence path land ecology
# already uses -- see the "land ecology survives a real restart" tests above)

## A degraded region's land health must not come back pristine on reload --
## the entire point of the concept doc's "lasting mark" framing.
func test_a_degraded_land_health_region_does_not_come_back_pristine():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)

	DirAccess.make_dir_recursive_absolute(EarthChunkManager.ECOLOGY_DIR)
	manager._chunk_serializer.save_ecology(
		{
			"herbivores": 1.0, "predators": 0.0, "vegetation": 0.5,
			"saved_at_unix": Time.get_unix_time_from_system(), "land_health": 0.2,
		},
		manager._ecology_path(chunk_coord)
	)
	manager._apply_persisted_ecology(chunk_coord)

	assert_lt(
		manager._ecosystem.land_health(chunk_coord), 0.9,
		"a badly degraded region saved moments ago must not come back pristine"
	)
	DirAccess.remove_absolute(manager._ecology_path(chunk_coord))


func test_unloading_a_chunk_persists_a_degraded_land_health():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	manager._ecosystem.seed_land_health(chunk_coord, 0.25)
	var path: String = manager._ecology_path(chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	# Walk far enough that Berlin's chunks are evicted.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))

	assert_true(FileAccess.file_exists(path), "an unloaded region must leave a record")
	var loaded := manager._chunk_serializer.load_ecology(path)
	assert_almost_eq(float(loaded.get("land_health", 1.0)), 0.25, 0.001)
	DirAccess.remove_absolute(path)


# -- the player's own animals survive a chunk unload -------------------------
#
# Creature markers are freed with their chunk and re-spawned from the region's
# aggregate population, which is right for a wild herd -- one deer is much
# like another -- and wrong for a horse the player spent an evening taming or
# deliberately tied to a tree. Those are particular animals in particular
# places (see KeptAnimals).

func _tame_a_horse_here(tile: Vector2i) -> CreatureMarker:
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(tile)
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", Vector2(tile) * TerrainRenderer.TILE_SIZE, manager, TerrainRenderer.TILE_SIZE
	)
	horse.trust = 1.0
	manager._loaded_creatures[chunk_coord].append(horse)
	return horse


func test_a_tamed_horse_is_still_there_after_its_chunk_unloads():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var horse := _tame_a_horse_here(_berlin_tile)
	var where := horse.position

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))  # evict
	manager.update(_berlin_tile)  # come back

	var found = null
	for creature in manager._loaded_creatures.get(chunk_coord, []):
		if is_instance_valid(creature) and creature.is_tame():
			found = creature
	assert_not_null(found, "a tamed horse must survive its chunk unloading")
	assert_almost_eq(found.position.distance_to(where), 0.0, 1.0, "and be where it was left")
	DirAccess.remove_absolute(manager._kept_animals_path(chunk_coord))


## A wild animal is NOT kept individually -- it belongs to the aggregate, and
## keeping every deer would be a save file that grows without bound.
func test_an_ordinary_wild_animal_is_not_kept_individually():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var kept := manager._save_kept_animals(chunk_coord)
	assert_eq(kept, 0, "a chunk of wild animals should keep none of them individually")
	DirAccess.remove_absolute(manager._kept_animals_path(chunk_coord))


## A tied animal is kept even at zero trust: the player put it there on
## purpose and expects to find it there.
func test_a_horse_tied_to_a_tree_is_kept_even_untamed():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE,
		manager, TerrainRenderer.TILE_SIZE
	)
	horse.restrain_to(horse.position, true)
	manager._loaded_creatures[chunk_coord].append(horse)
	assert_eq(manager._save_kept_animals(chunk_coord), 1, "a tied horse is kept")
	DirAccess.remove_absolute(manager._kept_animals_path(chunk_coord))


# -- /season and /weather ----------------------------------------------------

## Jumping a season must not make the world replay the time it skipped.
##
## The jump is up to a YEAR of world time (see SeasonCycle.seconds_until_season),
## and fruiting counts what fell between the last time it ran and now. Moving
## the clock without moving that mark hands `fallen_between` a year-long span,
## so `/season autumn` would empty every nearby canopy onto the ground in a
## single step -- a year's windfall at once. The same two-clocks trap that has
## bitten bird dispersal and tree maturity here already: two numbers that have
## to agree, moved independently.
func test_jumping_a_season_does_not_replay_the_skipped_year():
	watch_signals(WorldItemBus)
	manager.jump_to_season("autumn")
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, Vector2.ZERO)
	var after_jump = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_lt(
		after_jump, 50,
		"a season jump should not tip a year of fruit onto the ground at once"
	)


func test_jumping_a_season_actually_changes_the_season():
	for name in SeasonCycle.SEASONS:
		assert_true(manager.jump_to_season(name))
		assert_eq(manager.current_season(), name)


## Forward only -- a tree's age is measured against this clock, and winding it
## back would make a sapling younger than the moment it was planted.
func test_a_season_jump_never_moves_the_clock_backwards():
	for name in SeasonCycle.SEASONS:
		var before := manager.world_age_seconds()
		manager.jump_to_season(name)
		assert_gte(manager.world_age_seconds(), before)


func test_an_unknown_season_is_refused():
	var before := manager.world_age_seconds()
	assert_false(manager.jump_to_season("harvest"))
	assert_eq(manager.world_age_seconds(), before)


# -- a new world starts at a random point in the year -------------------------
#
# _world_age_seconds used to start at a hardcoded 0.0 for every new game, and
# SeasonCycle's own phase formula puts that exact moment at warmth ~0.1465 --
# just under Snowfall.FREEZING_WARMTH (0.15) -- so every fresh save began
# mid-winter-adjacent and reliably snowed within minutes (reported: "it starts
# to snow deterministically"). A brand new world should be free to start
# anywhere in the year; a LOADED world must resume exactly where it left off
# (see the persistence tests further down, and World._on_menu_start_requested
# / _spawn_local_singleplayer_from_save for the real call sites).

func test_a_freshly_constructed_manager_starts_at_world_age_zero():
	# The precondition the randomization tests below lean on: only an
	# explicit randomize_world_age()/set_world_age_seconds() call should ever
	# move this away from zero.
	assert_eq(manager.world_age_seconds(), 0.0)


func test_randomize_world_age_lands_within_one_year():
	for i in 20:
		var other := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
		other.randomize_world_age()
		assert_gte(other.world_age_seconds(), 0.0)
		assert_lt(other.world_age_seconds(), SeasonCycle.SECONDS_PER_YEAR)


## The actual bug, restated: every new game landing on the SAME moment.
func test_randomize_world_age_does_not_always_land_on_the_same_moment():
	var ages := {}
	for i in 20:
		var other := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
		other.randomize_world_age()
		ages[other.world_age_seconds()] = true
	assert_gt(ages.size(), 1, "every new game landing on the same world-age is the bug this exists to fix")


## The report's own terms: a fresh world should not always start in the same
## SEASON either -- this is the direct, real-world-visible symptom.
func test_randomize_world_age_can_start_in_more_than_one_season():
	var seasons := {}
	for i in 40:
		var other := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
		other.randomize_world_age()
		seasons[other.current_season()] = true
	assert_gt(seasons.size(), 1, "40 fresh worlds should not all start in the same season")


## set_world_age_seconds (used by both randomize_world_age and
## load_world_clock) has to move every OTHER mark that measures itself
## against the clock too -- the same "two clocks that have to agree" trap
## jump_to_season's own doc comment already describes, just at world-creation
## time rather than a /season skip. Proven against snow: if _snow_world_age
## were left behind at 0 while the real clock jumped to a random mid-year
## start, the very first step_snow call would see the WHOLE random offset as
## elapsed time and dump a season's worth of accumulation into one step.
func test_set_world_age_seconds_does_not_fake_a_catch_up_on_the_first_snow_step():
	manager.set_world_age_seconds(20000.0)
	manager.advance_world_age(1.0)
	manager.step_snow(true, 0.0)  # cold and snowing
	assert_lt(
		manager.snow_depth(), 0.1,
		"one real second of snowfall should barely dust the ground, not fake a huge catch-up jump"
	)


## Forcing weather reaches every reader, not just the overlay: soil moisture is
## what makes seeds root, so a forced downpour has to wet the ground too.
func test_forcing_weather_reaches_the_whole_world():
	assert_true(manager.force_weather("storm"))
	assert_eq(manager.current_weather(Vector2.ZERO), "storm")
	assert_eq(manager.current_weather(Vector2(9999.0, -4242.0)), "storm")
	manager.clear_forced_weather()
	assert_false(manager.is_weather_forced())


func test_an_unknown_weather_state_is_refused():
	assert_false(manager.force_weather("sunny"))
	assert_false(manager.is_weather_forced())


# -- emergence: the Weather glass item reads weather one period ahead
# (docs/concept/wayfinding.md's Weather glass item) -- upcoming_weather
# mirrors current_weather's own internals (same day/region-seed derivation)
# but calls WeatherForecast.upcoming_weather(_weather_model, day, seed)
# instead of _weather_model.weather_at(day, seed) directly, one day ahead.

## Proven by advancing the world clock forward exactly one weather period
## and comparing against current_weather's own reading there -- rather than
## re-deriving WEATHER_PERIOD_SECONDS/region-seed math in the test, which
## would just restate the implementation instead of proving it.
func test_upcoming_weather_matches_current_weather_one_period_later():
	manager.set_world_age_seconds(0.0)
	var forecast: String = manager.upcoming_weather(Vector2.ZERO)

	manager.set_world_age_seconds(EarthChunkManager.WEATHER_PERIOD_SECONDS)
	var next_periods_current := manager.current_weather(Vector2.ZERO)

	assert_eq(forecast, next_periods_current)


# -- snow keeps the world's clock, not the frame's ---------------------------

## Snow melts on WORLD time, the same clock the season is on.
##
## It used to melt on the real frame delta while the season ran on the world
## clock, so the two could not agree. `/season summer` leaps the world clock up
## to a year forward; the snow saw one frame -- about sixteen milliseconds --
## and went on lying there in the sunshine (reported: setting the season to
## summer does not thaw the snow). The same mismatch made a `/ecotest` winter
## thaw at real-time speed while the seasons flew past.
##
## Reading the world clock directly is what makes it impossible to drift again:
## there is only one clock now, not two that have to be kept in step.
func test_summer_thaws_lying_snow():
	manager.jump_to_season("winter")
	manager.set_snow_depth(1.0)
	assert_eq(manager.snow_depth(), 1.0, "precondition: snow is lying")

	manager.jump_to_season("summer")
	manager.step_snow(false, 1.0)
	assert_eq(manager.snow_depth(), 0.0, "a season in the sun should clear the snow")


## And it is the world clock that does it, not the number of calls: stepping
## without the world moving melts nothing.
func test_snow_does_not_melt_while_the_world_stands_still():
	manager.set_snow_depth(1.0)
	for index in 20:
		manager.step_snow(false, 1.0)
	assert_eq(manager.snow_depth(), 1.0, "no world time passed, so no thaw")


## A short warm spell melts a little, not everything -- so an ordinary thaw is
## still something you watch happen.
func test_a_short_warm_spell_melts_only_part_of_it():
	manager.set_snow_depth(1.0)
	manager.advance_world_age(Snowfall.SECONDS_TO_THAW * 0.25)
	manager.step_snow(false, 1.0)
	assert_almost_eq(manager.snow_depth(), 0.75, 0.02)


## Cold and not snowing leaves it lying, which is what makes a frozen landscape
## persist through a clear winter day.
func test_a_clear_frozen_day_leaves_the_snow_where_it_is():
	manager.set_snow_depth(0.8)
	manager.advance_world_age(Snowfall.SECONDS_TO_THAW)
	manager.step_snow(false, 0.0)
	assert_eq(manager.snow_depth(), 0.8)


func test_snow_accumulates_while_it_falls():
	manager.set_snow_depth(0.0)
	manager.advance_world_age(Snowfall.SECONDS_TO_COVER)
	manager.step_snow(true, 0.0)
	assert_almost_eq(manager.snow_depth(), 1.0, 0.02)


## is_snowing() exposes the SAME per-frame active-precipitation boolean
## World already computes and hands to step_snow to accumulate against (see
## docs/concept/weather.md's "Weather feeds creature behaviour") -- a second
## reader (CreatureMarker) has to read that one answer rather than deriving
## its own, or an animal could disagree with the ground about whether it's
## snowing right now.
func test_is_snowing_reflects_the_last_step_snow_call():
	manager.step_snow(true, 0.0)  # cold and snowing
	assert_true(manager.is_snowing())
	manager.step_snow(false, 1.0)  # warm and dry
	assert_false(manager.is_snowing())


func test_is_snowing_defaults_to_false_before_any_step():
	assert_false(manager.is_snowing())


## The five tests that used to live here (a partial snowfall paints a MIX of
## bare/covered tiles; painted tiles carry a real per-tile variant; coverage
## advances within a single depth band; a realistic step_snow-driven
## snowfall paints more than one band; coverage trickles in rather than
## batching every ~18s) all asserted the OLD per-tile band+variant painting
## mechanism -- SnowLayer, and the atlas coords _paint_snow_tile wrote from
## it. SnowBombShader deletes that mechanism outright: coverage, variant,
## level and onset are now read per PIXEL, straight from world position, by
## the shader itself (see docs/concept/snow_cover.md). There is no longer a
## painted band or variant for a test to inspect, and no sweep cadence to
## time, because there is no sweep -- every one of those five tests' own
## claims is either meaningless against the new mechanism or true by
## construction of it. The tests below assert what the TileMapLayer's
## narrower remaining job actually is.

## SnowBombShader's fragment() never reads TEXTURE -- it writes COLOR
## unconditionally from its own stamp_atlas/trail_mask samplers -- so the
## ONLY thing a painted cell still means is "snow may render here at all".
## Water never takes snow (freezing is a different, unbuilt mechanic, not
## this one), so ocean tiles must stay unpainted -- an erased cell draws no
## quad and never runs fragment() at all, which is what keeps snow off water
## without the shader needing to know what a biome is.
func test_snow_presence_is_painted_on_land_and_never_on_ocean():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)
	# Presence is gated on snow actually lying (see _sync_snow_presence) --
	# an empty layer while it is not snowing is deliberate, not a bug this
	# test should catch; the 0 -> nonzero transition is what paints it.
	manager.set_snow_depth(0.5)

	var land_painted := 0
	var ocean_painted := 0
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				var painted := snow_layer.get_cell_source_id(Vector2i(global_x, global_y)) != -1
				if manager.biome_at_global(global_x, global_y) == "ocean":
					if painted:
						ocean_painted += 1
				elif painted:
					land_painted += 1
	assert_gt(land_painted, 0, "precondition: at least one land tile got a presence cell")
	assert_eq(ocean_painted, 0, "water must never carry a snow presence cell")
	snow_layer.free()


## Presence painted unconditionally, regardless of season, was a real
## reported regression: it means the entire visible ground always submits
## real quads to a custom-shader material -- the old per-tile mechanism
## this replaces painted NOTHING while it was not snowing (a genuinely
## empty layer, costing what it did before this shader existed at all), and
## a full summer with snow_depth flat at 0.0 must cost the same today.
func test_snow_presence_is_empty_while_nothing_is_snowing():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)
	assert_eq(
		snow_layer.get_used_cells().size(), 0,
		"the snow layer must have nothing painted while snow_depth is 0"
	)
	snow_layer.free()


## The other half of the same regression: presence must actually clear back
## to empty on a full thaw, not stay painted forever once a snowfall has
## happened once.
func test_snow_presence_clears_on_a_full_thaw():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)
	manager.set_snow_depth(0.8)
	assert_gt(snow_layer.get_used_cells().size(), 0, "precondition: presence painted while lying")

	manager.set_snow_depth(0.0)
	assert_eq(
		snow_layer.get_used_cells().size(), 0,
		"presence should clear back to an empty layer once the snow has fully thawed"
	)
	snow_layer.free()


## The direct behavioural contrast with the deleted mechanism: presence used
## to be repainted (or at least diffed) on every depth change, which is
## exactly the class of bug ("a whole chunk snaps instantly", "nothing
## repaints for ~18s then a batch pops") the five deleted tests existed to
## catch. Coverage is the shader's job now, keyed off snow_depth alone --
## presence is painted once, at chunk load, and never again.
func test_snow_presence_does_not_change_with_depth():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)
	manager.set_snow_depth(0.5)  # something already painted under the old mechanism too
	var before := snow_layer.get_used_cells().size()
	assert_gt(before, 0, "precondition: something is painted to watch for a change")

	# Deliberately no 0.0 in this sweep -- the OLD mechanism cleared the whole
	# layer at zero depth, which would make this pass by coincidence (0 == 0)
	# rather than for the real reason.
	manager.set_snow_depth(0.02)
	manager.set_snow_depth(1.0)
	manager.set_snow_depth(0.13)

	assert_eq(
		snow_layer.get_used_cells().size(), before,
		"presence cells changed with depth -- coverage should be the shader's job now, not the tile grid's"
	)
	snow_layer.free()


## Depth reaches the GPU through the shared material's uniform now, not
## through any per-tile atlas coord -- there is nothing else left to read it
## from.
func test_snow_depth_reaches_the_shared_shader_material():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.set_snow_depth(0.42)
	var material := snow_layer.material as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter("snow_depth")), 0.42, 0.0001)
	snow_layer.free()


## Footprints reach the GPU as a real trail mask texture keyed to world
## position -- the bridge SnowTrail.build_mask_texture exists for (see its
## own doc comment). Read back through the exact origin/world_size the
## shader itself would use, not just "some texture changed".
func test_treading_snow_reaches_the_shared_trail_mask():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.set_snow_depth(1.0)

	var trodden_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(trodden_pixel)
	manager.step_snow(false, 0.0)

	var material := snow_layer.material as ShaderMaterial
	var mask: Texture2D = material.get_shader_parameter("trail_mask")
	var origin: Vector2 = material.get_shader_parameter("trail_origin")
	var world_size: float = material.get_shader_parameter("trail_world_size")
	var image := mask.get_image()
	var uv := (trodden_pixel - origin) / world_size
	var pixel := Vector2i(uv * Vector2(image.get_width(), image.get_height()))
	assert_gt(
		image.get_pixel(pixel.x, pixel.y).r, 0.0,
		"the trodden tile should show up, at its own real position, in the mask pushed to the shader"
	)
	snow_layer.free()


## Individually-simulated creatures (deer, boar, wolves, ...) must leave the
## SAME kind of trail mark the player's own footsteps do -- tread_snow_at's
## new move_trail_window argument is exactly what lets World.gd call it for
## every CreatureMarker too (see its own doc comment): the player anchors the
## trail window (move_trail_window left at its true default), and a creature
## treads a NEIGHBOURING tile with move_trail_window = false, well within
## that same window but distinct from the player's own tile, so this proves
## the creature's OWN mark reaches the shared mask rather than coincidentally
## reusing the player's.
func test_creature_treading_snow_reaches_the_shared_trail_mask_the_same_way_the_player_does():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.set_snow_depth(1.0)

	var player_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(player_pixel)

	var creature_tile := _berlin_tile + Vector2i(5, 0)
	var creature_pixel := Vector2(creature_tile) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(creature_pixel, false)
	manager.step_snow(false, 0.0)

	var material := snow_layer.material as ShaderMaterial
	var mask: Texture2D = material.get_shader_parameter("trail_mask")
	var origin: Vector2 = material.get_shader_parameter("trail_origin")
	var world_size: float = material.get_shader_parameter("trail_world_size")
	var image := mask.get_image()
	var uv := (creature_pixel - origin) / world_size
	var pixel := Vector2i(uv * Vector2(image.get_width(), image.get_height()))
	assert_gt(
		image.get_pixel(pixel.x, pixel.y).r, 0.0,
		"a creature's own tread should show up, at its own real position, in the same shared mask the player's does"
	)
	snow_layer.free()


## The trail mask WINDOW has to keep following the player, not snap to
## wherever a creature happens to be standing -- see tread_snow_at's own
## doc comment on move_trail_window. Several creatures updating after the
## player in the same frame must not relocate _snow_trail_center_tile away
## from wherever the player's own last tread put it, or the window could
## carry the player's own nearby tracks right out of view.
func test_creature_treading_snow_does_not_move_the_trail_window():
	manager.set_snow_depth(1.0)
	var player_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(player_pixel)

	var far_creature_pixel := Vector2(_berlin_tile + Vector2i(40, 40)) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(far_creature_pixel, false)

	assert_eq(
		manager._snow_trail_center_tile, _berlin_tile,
		"a creature's own tread should not relocate the trail mask window away from the player"
	)


# -- gradual snow clearing (see SnowTrail.step_on/TREAD_PER_STEP) --
#
# Reported live: "should also remove snow gradually when walking back and
# forth". tread_snow_at used to fire every single RENDERED FRAME with no
# per-tile-entry gate, unlike PathScarring's own _last_scar_step_tile debounce
# -- so a tile saturated to SnowTrail.MAX_TREAD within about three frames
# of first entry (TREAD_PER_STEP=0.34, 1.0/0.34 = ~3), regardless of whether
# the player kept walking. That reads as an instant flat clearing rather
# than a gradual one, and makes "walking back and forth" pointless -- the
# tile is already maxed out after the very first pass.


func test_treading_the_same_tile_repeatedly_in_one_frame_does_not_stack_wear():
	manager.set_snow_depth(1.0)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	for i in 10:
		manager.tread_snow_at(pixel)
	assert_almost_eq(
		manager._snow_trail.tread_at(_berlin_tile), SnowTrail.TREAD_PER_STEP, 0.0001,
		"standing on/re-entering the identical tile within the same visit must not stack tread"
	)


## Leaving a tile and coming back is a genuinely NEW entry -- "walking back
## and forth" must keep deepening the tread, up to SnowTrail's own
## MAX_TREAD ceiling, not get stuck at whatever the first visit produced.
func test_leaving_and_returning_to_a_tile_deepens_tread_further():
	manager.set_snow_depth(1.0)
	var here := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var elsewhere := Vector2(_berlin_tile + Vector2i(3, 0)) * TerrainRenderer.TILE_SIZE

	manager.tread_snow_at(here)
	var after_first_visit := manager._snow_trail.tread_at(_berlin_tile)
	manager.tread_snow_at(elsewhere)
	manager.tread_snow_at(here)

	assert_almost_eq(
		manager._snow_trail.tread_at(_berlin_tile), after_first_visit + SnowTrail.TREAD_PER_STEP, 0.0001,
		"returning to a tile after leaving it should deepen the tread further"
	)


## The debounce is player-only (move_trail_window=true, the default) --
## creatures keep their existing every-call behaviour, an explicit, narrower
## scope decision (see tread_snow_at's own doc comment) rather than an
## oversight.
func test_a_creature_still_treads_every_call_unlike_the_player():
	manager.set_snow_depth(1.0)
	var creature_tile := _berlin_tile + Vector2i(5, 0)
	var creature_pixel := Vector2(creature_tile) * TerrainRenderer.TILE_SIZE
	manager.tread_snow_at(creature_pixel, false)
	manager.tread_snow_at(creature_pixel, false)
	assert_almost_eq(
		manager._snow_trail.tread_at(creature_tile), 2.0 * SnowTrail.TREAD_PER_STEP, 0.0001,
		"a creature's own repeated tread is not debounced by tile entry"
	)


## A fallen fruit is ONE fruit, landing under where it hung.
##
## Windfall used to be spawned as up to five arbitrary stacks scattered by a
## hash unrelated to the canopy, so what hit the ground had no connection to
## what had been hanging there -- a new cherry rather than the one on the tree
## (reported). Each fruit now leaves its own place in the canopy and lands
## under it.
func test_fallen_fruit_lands_as_individual_fruit():
	manager.update(_berlin_tile)
	var berlin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.advance_world_age(SeasonCycle.SECONDS_PER_YEAR)
	watch_signals(WorldItemBus)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, berlin_pixel)

	var drops = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_gt(drops, 0, "precondition: something should have fallen over a year")
	for i in drops:
		var stack = get_signal_parameters(WorldItemBus, "item_dropped", i)[0]
		assert_eq(stack.count, 1, "each fruit should fall as itself, not as a pile")


## And it lands near its own trunk rather than anywhere in the wood.
func test_fallen_fruit_lands_under_its_own_tree():
	manager.update(_berlin_tile)
	var berlin_pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	manager.advance_world_age(SeasonCycle.SECONDS_PER_YEAR)
	watch_signals(WorldItemBus)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, berlin_pixel)

	var drops = get_signal_emit_count(WorldItemBus, "item_dropped")
	assert_gt(drops, 0, "precondition: something should have fallen")
	var reach := ProceduralTreeSprite.FRUIT_GROUND_REACH * 1.5
	for i in drops:
		var at: Vector2 = get_signal_parameters(WorldItemBus, "item_dropped", i)[1]
		var nearest := INF
		for node in entities_parent.get_children():
			if node.has_method("ripe_fruit_count"):
				nearest = minf(nearest, at.distance_to(node.position))
		assert_lt(nearest, reach, "a fruit landed nowhere near any tree")


# -- emergence: a settlement founding is a real, once-only event ------------

## Founding a settlement is recorded once, as a real historical event (see
## docs/emergence, VillageRenderer.spawn_village's duck-typed hook into this).
##
## Both directions witness each other: the settlement founded event lists
## every villager as a WITNESS (they were there), and each villager's own
## npc_settled event lists the settlement as a witness in return -- so
## /history on either side surfaces both events, which is the richer,
## honest provenance docs/emergence's witnesses[] field exists for, not a
## narrower "only the direct actor" history.
func test_founding_a_settlement_records_settlement_founded_and_npc_settled():
	var chunk_coord := Vector2i(5, -3)
	var npcs: Array = [NpcIdentity.new(111), NpcIdentity.new(222)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var history: Array = manager.event_store().events_for_entity(settlement_id)
	var history_types: Array = []
	for event in history:
		history_types.append(event.type)
	assert_true(history_types.has("settlement_founded"))
	assert_eq(history_types.count("npc_settled"), npcs.size())

	for npc in npcs:
		var npc_history: Array = manager.event_store().events_for_entity(EntityRef.for_npc(npc.seed_value))
		var npc_types: Array = []
		for event in npc_history:
			npc_types.append(event.type)
		assert_true(npc_types.has("npc_settled"), "the NPC should be the actor of its own settling")
		assert_true(npc_types.has("settlement_founded"), "the NPC witnessed the settlement it settled at")


func test_settlement_and_villagers_witness_each_other():
	var chunk_coord := Vector2i(9, 9)
	var npcs: Array = [NpcIdentity.new(1)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var npc_id := EntityRef.for_npc(npcs[0].seed_value)

	var founded_event = manager.event_store().events_of_type("settlement_founded")[0]
	assert_true(founded_event.witnesses.has(npc_id))

	var settled_event = manager.event_store().events_of_type("npc_settled")[0]
	assert_true(settled_event.witnesses.has(settlement_id))


## A chunk RELOAD must not re-record a founding -- this is what keeps the
## store honest across the normal load/unload/reload cycle every other chunk
## system already goes through.
func test_reloading_the_same_settlement_does_not_record_it_twice():
	var chunk_coord := Vector2i(5, -3)
	var npcs: Array = [NpcIdentity.new(111)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	assert_eq(manager.event_store().events_of_type("settlement_founded").size(), 1)
	assert_eq(manager.event_store().events_of_type("npc_settled").size(), 1)


## Two different settlements are two different entities.
func test_two_different_settlements_are_recorded_separately():
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	manager.record_settlement_founded_if_new(Vector2i(2, 2), [NpcIdentity.new(2)])
	assert_eq(manager.event_store().events_of_type("settlement_founded").size(), 2)
	var first: Array = manager.event_store().events_for_entity(EntityRef.for_settlement(Vector2i(1, 1)))
	var second: Array = manager.event_store().events_for_entity(EntityRef.for_settlement(Vector2i(2, 2)))
	assert_ne(first[0].id, second[0].id, "each settlement should get its own founding event")


func test_the_settlement_founded_event_witnesses_every_villager():
	var chunk_coord := Vector2i(7, 7)
	var npcs: Array = [NpcIdentity.new(1), NpcIdentity.new(2)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	var event = manager.event_store().events_for_entity(EntityRef.for_settlement(chunk_coord))[0]
	for npc in npcs:
		assert_true(event.witnesses.has(EntityRef.for_npc(npc.seed_value)))


# -- emergence: the event store persists like everything else world-scoped ---

## Save/load round-trips the live store through the same convention
## PlayerSave/ChunkSerializer already established (see EventStorePersistence)
## -- proven end to end here, not just at EventStorePersistence's own unit
## level, since this is the path the real game actually calls.
func test_save_event_store_then_load_event_store_round_trips_live_state():
	# Reuses the one fixture `manager` (save, reset, load back into itself)
	# rather than constructing a second EarthChunkManager -- a second real
	# instance re-triggers the elevation-resource load warning every ECM
	# construction makes, which GUT's own per-test error tracking then
	# (harmlessly, but incorrectly) flags as an unexpected test failure.
	var path := "user://test_ecm_emergence_events.bin"
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(Vector2i(1, 1))
	var before: int = manager.event_store().events_for_entity(settlement_id).size()

	manager.save_event_store(path)
	manager.reset_event_store()
	assert_eq(manager.event_store().size(), 0, "precondition: reset actually cleared it")
	manager.load_event_store(path)

	assert_eq(manager.event_store().events_for_entity(settlement_id).size(), before)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_reset_event_store_clears_live_state():
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	assert_gt(manager.event_store().size(), 0, "precondition")
	manager.reset_event_store()
	assert_eq(manager.event_store().size(), 0)


func test_wipe_event_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_events_wipe.bin"
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	manager.save_event_store(path)
	manager.wipe_event_store(path)

	assert_eq(manager.event_store().size(), 0, "memory should be cleared")
	assert_false(FileAccess.file_exists(path), "disk save should be gone")


# -- the world clock persists like everything else world-scoped -------------
#
# A LOADED game must resume from exactly where it stopped, not re-randomize
# (see randomize_world_age's own doc comment) -- proven end to end here, the
# same real-call-site convention PlayerSave/EventStorePersistence already
# established (see WorldClockPersistence).

func test_save_world_clock_then_load_world_clock_round_trips():
	var path := "user://test_ecm_world_clock.bin"
	manager.set_world_age_seconds(12345.6)
	manager.save_world_clock(path)

	var other := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	other.load_world_clock(path)
	assert_almost_eq(other.world_age_seconds(), 12345.6, 0.001)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Loading with nothing saved yet must not rewind a clock already running
## (e.g. a --solo dev launch with no save present) -- it leaves the clock
## exactly where it was, matching PlayerSave/EventStorePersistence's own
## "nothing to load" behaviour rather than silently resetting to zero.
func test_load_world_clock_with_no_save_leaves_the_clock_untouched():
	var path := "user://test_ecm_world_clock_missing.bin"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	manager.set_world_age_seconds(500.0)
	manager.load_world_clock(path)
	assert_eq(manager.world_age_seconds(), 500.0)


func test_wipe_world_clock_removes_the_saved_file():
	var path := "user://test_ecm_world_clock_wipe.bin"
	manager.set_world_age_seconds(777.0)
	manager.save_world_clock(path)
	manager.wipe_world_clock(path)
	assert_false(FileAccess.file_exists(path), "disk save should be gone")


# -- emergence: founding forms memories too, not just events -----------------

## Every villager remembers BOTH events they touch: their own settling
## (firsthand -- they are the actor) and the founding itself (witnessed --
## they were there, per MemoryStore.witness_event indexing actors AND
## witnesses exactly like EventStore already does).
func test_founding_a_settlement_forms_real_memories():
	var chunk_coord := Vector2i(11, 11)
	var npcs: Array = [NpcIdentity.new(1)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	var npc_id := EntityRef.for_npc(npcs[0].seed_value)
	var npc_memories: Array = manager.memory_store().memories_for(npc_id)
	var remembered_events: Array = []
	var sources: Array = []
	for memory in npc_memories:
		remembered_events.append(memory.remembered_type)
		sources.append(memory.source_type)
	assert_true(remembered_events.has("npc_settled"), "should remember its own settling")
	assert_true(remembered_events.has("settlement_founded"), "should remember the founding it witnessed")
	assert_true(sources.has(MemoryRecord.FIRSTHAND), "settling itself should be firsthand")
	assert_true(sources.has(MemoryRecord.WITNESSED), "the founding should be witnessed, not firsthand")


## The settlement itself remembers being founded too -- firsthand, since it
## is the actor of its own founding event (it also picks up a WITNESSED
## memory of each villager's settling, the same cross-witnessing the event
## store itself already models -- see test_settlement_and_villagers_witness_each_other).
func test_the_settlement_remembers_its_own_founding():
	var chunk_coord := Vector2i(13, 13)
	var npcs: Array = [NpcIdentity.new(1)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var memories: Array = manager.memory_store().memories_for(settlement_id)
	var founding_memories: Array = []
	for memory in memories:
		if memory.remembered_type == "settlement_founded":
			founding_memories.append(memory)
	assert_eq(founding_memories.size(), 1)
	assert_eq(founding_memories[0].source_type, MemoryRecord.FIRSTHAND)


# -- emergence: the memory store persists alongside the event store -----------

func test_save_memory_store_then_load_memory_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_memories.bin"
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	var npc_id := EntityRef.for_npc(1)
	var before: int = manager.memory_store().memories_for(npc_id).size()

	manager.save_memory_store(path)
	manager.reset_memory_store()
	assert_eq(manager.memory_store().memories_for(npc_id).size(), 0, "precondition: reset cleared it")
	manager.load_memory_store(path)

	assert_eq(manager.memory_store().memories_for(npc_id).size(), before)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_memory_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_memories_wipe.bin"
	manager.record_settlement_founded_if_new(Vector2i(1, 1), [NpcIdentity.new(1)])
	manager.save_memory_store(path)
	manager.wipe_memory_store(path)

	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(1)).size(), 0)
	assert_false(FileAccess.file_exists(path))


# -- emergence: founding forms a household per villager, owning its house ----

## Every villager gets a household of their own -- single-member, since no
## partnership/reproduction system exists yet (see docs/roadmap.md's
## Emergence Phase 3 note) -- and that household owns the house it lives in,
## a real piece of property recorded against a real structure
## VillageRenderer actually stamps.
func test_founding_a_settlement_forms_a_household_owning_its_own_house():
	var chunk_coord := Vector2i(21, 21)
	var npcs: Array = [NpcIdentity.new(1), NpcIdentity.new(2)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	for i in npcs.size():
		var npc_id := EntityRef.for_npc(npcs[i].seed_value)
		var household = manager.household_store().household_for(npc_id)
		assert_not_null(household, "villager %d should have a household" % i)
		assert_eq(household.members, [npc_id])
		assert_eq(household.property.size(), 1, "villager %d should own exactly one house" % i)


## Two different villagers own two different houses -- not the same one.
func test_two_villagers_own_two_different_houses():
	var chunk_coord := Vector2i(23, 23)
	var npcs: Array = [NpcIdentity.new(1), NpcIdentity.new(2)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	var first = manager.household_store().household_for(EntityRef.for_npc(1))
	var second = manager.household_store().household_for(EntityRef.for_npc(2))
	assert_ne(first.property[0], second.property[0])


## Reloading the same settlement must not re-grant or duplicate property --
## the same founding-is-once-only guard the events themselves already have.
func test_reloading_a_settlement_does_not_duplicate_property():
	var chunk_coord := Vector2i(25, 25)
	var npcs: Array = [NpcIdentity.new(1)]
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	manager.record_settlement_founded_if_new(chunk_coord, npcs)
	var household = manager.household_store().household_for(EntityRef.for_npc(1))
	assert_eq(household.property.size(), 1)


# -- emergence: the household store persists alongside the others ------------

func test_save_household_store_then_load_household_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_households.bin"
	manager.record_settlement_founded_if_new(Vector2i(31, 31), [NpcIdentity.new(1)])
	var npc_id := EntityRef.for_npc(1)
	var before = manager.household_store().household_for(npc_id).property

	manager.save_household_store(path)
	manager.reset_household_store()
	assert_null(manager.household_store().household_for(npc_id), "precondition: reset cleared it")
	manager.load_household_store(path)

	assert_eq(manager.household_store().household_for(npc_id).property, before)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_household_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_households_wipe.bin"
	manager.record_settlement_founded_if_new(Vector2i(33, 33), [NpcIdentity.new(1)])
	manager.save_household_store(path)
	manager.wipe_household_store(path)

	assert_null(manager.household_store().household_for(EntityRef.for_npc(1)))
	assert_false(FileAccess.file_exists(path))


# -- emergence: the Deed item claims real property (docs/concept/
# player_citizenship.md's Deed item) -- the same form_household/
# grant_property mechanism NPC houses already use, keyed by the player's
# own PlayerIdentity.PLAYER_ENTITY_ID rather than an npc id.

func test_claiming_property_with_a_deed_forms_a_household_owning_it():
	var household = manager.claim_property_with_deed("house:99_99_0")
	assert_not_null(household)
	assert_eq(household.members, [PlayerIdentity.PLAYER_ENTITY_ID])
	assert_true(household.property.has("house:99_99_0"))


## Idempotent, matching HouseholdStore.grant_property's own idempotence --
## claiming the same property a second time does not error and the property
## stays owned by the same household.
func test_claiming_the_same_property_twice_stays_owned_by_the_same_household():
	var first = manager.claim_property_with_deed("house:98_98_0")
	var second = manager.claim_property_with_deed("house:98_98_0")
	assert_eq(first.id, second.id)
	assert_eq(manager.household_store().owner_of("house:98_98_0"), first.id)


func test_claiming_property_with_a_deed_records_a_real_event():
	var household = manager.claim_property_with_deed("house:97_97_0")
	var claimed: Array = manager.event_store().events_of_type("player_claimed_property")
	assert_eq(claimed.size(), 1)
	assert_eq(claimed[0].actors, [household.id])
	assert_eq(claimed[0].tags, ["house:97_97_0"])


# -- emergence: contracts are coordinated with events, same as founding -----

## Proposing a contract through EarthChunkManager both creates the contract
## AND records a real event -- the same "one call, two stores kept in sync"
## shape record_settlement_founded_if_new already establishes, so a contract
## can never exist without a matching history event.
func test_proposing_a_contract_records_a_real_event():
	var contract = manager.propose_contract(
		"rent", ["household:1", "household:2"], ["10 wood/week"], "shelter", -1.0
	)
	assert_not_null(contract)
	var history: Array = manager.event_store().events_for_entity("household:1")
	var types: Array = []
	for event in history:
		types.append(event.type)
	assert_true(types.has("contract_proposed"))


## A breach is exactly the kind of failure the exit criterion cares about:
## "agreement failures create deterministic social/economic/history
## consequences" -- proven here even with no live gameplay trigger yet.
func test_breaching_a_contract_records_a_real_breach_event():
	var contract = manager.propose_contract("rent", ["household:1"], [], "", -1.0)
	manager.accept_contract(contract.id)
	manager.activate_contract(contract.id)
	assert_true(manager.breach_contract(contract.id))

	assert_eq(manager.contract_store().get_contract(contract.id).status, "breached")
	var breach_events: Array = manager.event_store().events_of_type("contract_breached")
	assert_eq(breach_events.size(), 1)
	assert_eq(breach_events[0].actors, ["household:1"])


func test_an_invalid_transition_records_no_event():
	var contract = manager.propose_contract("rent", ["household:1"], [], "", -1.0)
	assert_false(manager.fulfill_contract(contract.id))  # not active yet
	assert_eq(manager.event_store().events_of_type("contract_fulfilled").size(), 0)


# -- emergence: the Ledger item proposes real player contracts (docs/
# concept/player_citizenship.md's Ledger item) -- a thin wrapper over the
# existing propose_contract naming the player's own household as one party.

func test_player_propose_contract_names_the_players_household_and_counterparty():
	var contract = manager.player_propose_contract(
		"trade", "household:50", ["10 wood/week"], "shelter", -1.0
	)
	assert_not_null(contract)
	var player_household_id: String = manager.household_store().household_for(
		PlayerIdentity.PLAYER_ENTITY_ID
	).id
	assert_true(contract.parties.has(player_household_id))
	assert_true(contract.parties.has("household:50"))


## The existing generic lifecycle methods already work unchanged for a
## player-named contract -- ContractStore._transition never assumes
## anything about WHICH entity a party is, so accept_contract/
## fulfill_contract need no player-specific counterpart.
func test_a_player_proposed_contract_can_be_accepted_and_fulfilled():
	var contract = manager.player_propose_contract("trade", "household:51", [], "", -1.0)
	assert_true(manager.accept_contract(contract.id))
	assert_true(manager.activate_contract(contract.id))
	assert_true(manager.fulfill_contract(contract.id))
	assert_eq(manager.contract_store().get_contract(contract.id).status, "fulfilled")


# -- emergence: the contract store persists alongside the others -------------

func test_save_contract_store_then_load_contract_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_contracts.bin"
	var contract = manager.propose_contract("rent", ["household:1"], [], "", -1.0)

	manager.save_contract_store(path)
	manager.reset_contract_store()
	assert_null(manager.contract_store().get_contract(contract.id), "precondition: reset cleared it")
	manager.load_contract_store(path)

	assert_eq(manager.contract_store().get_contract(contract.id).status, "proposed")

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_contract_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_contracts_wipe.bin"
	var contract = manager.propose_contract("rent", ["household:1"], [], "", -1.0)
	manager.save_contract_store(path)
	manager.wipe_contract_store(path)

	assert_null(manager.contract_store().get_contract(contract.id))
	assert_false(FileAccess.file_exists(path))


# -- emergence: production is coordinated with events, same as contracts ----

## A resource shortage causes a real, event-sourced production failure --
## the Phase 5 exit criterion made concrete: "a resource shortage can raise
## prices and cause downstream production failure without scripted events."
func test_attempting_production_with_a_shortage_records_a_failure_event():
	var result = manager.attempt_production("settlement:0_0", "stone_pickaxe")
	assert_false(result.success)

	var failures: Array = manager.event_store().events_of_type("production_failed")
	assert_eq(failures.size(), 1)
	assert_eq(failures[0].actors, ["settlement:0_0"])
	assert_eq(failures[0].tags, ["stone_pickaxe"])


func test_attempting_production_with_enough_stock_records_a_success_event():
	var market = manager.market_store().market_for("settlement:1_1")
	market.add_stock("stick", 2)
	market.add_stock("rock", 3)

	var result = manager.attempt_production("settlement:1_1", "stone_pickaxe")
	assert_true(result.success)

	var successes: Array = manager.event_store().events_of_type("production_succeeded")
	assert_eq(successes.size(), 1)


## The settlement forms a real memory of its own production failure too --
## the same composition contracts already demonstrated with memory.
func test_a_production_failure_is_remembered_by_the_settlement():
	manager.attempt_production("settlement:2_2", "stone_pickaxe")
	var memories: Array = manager.memory_store().memories_for("settlement:2_2")
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].source_type, MemoryRecord.FIRSTHAND)


# -- emergence: the market store persists alongside the others ---------------

func test_save_market_store_then_load_market_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_markets.bin"
	manager.market_store().market_for("settlement:0_0").add_stock("wood", 5)

	manager.save_market_store(path)
	manager.reset_market_store()
	assert_eq(manager.market_store().market_for("settlement:0_0").stock_of("wood"), 0, "precondition: reset cleared it")
	manager.load_market_store(path)

	assert_eq(manager.market_store().market_for("settlement:0_0").stock_of("wood"), 5)

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_market_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_markets_wipe.bin"
	manager.market_store().market_for("settlement:0_0").add_stock("wood", 5)
	manager.save_market_store(path)
	manager.wipe_market_store(path)

	assert_eq(manager.market_store().market_for("settlement:0_0").stock_of("wood"), 0)
	assert_false(FileAccess.file_exists(path))


# -- emergence: institutions form from real repeated coordination -----------

func _fulfill_contracts_between(a: String, b: String, count: int) -> void:
	for i in count:
		var contract = manager.propose_contract("trade", [a, b], [], "", -1.0)
		manager.accept_contract(contract.id)
		manager.activate_contract(contract.id)
		manager.fulfill_contract(contract.id)


## Below the formation threshold, nothing forms -- the whole point of a real
## threshold rather than "the first time these two do business together."
func test_attempting_formation_below_threshold_forms_nothing():
	_fulfill_contracts_between("household:1", "household:2", 2)
	var institution = manager.attempt_institution_formation("guild", "household:1", "household:2")
	assert_null(institution)
	assert_eq(manager.event_store().events_of_type("institution_formed").size(), 0)


## At the threshold, a real institution forms AND is recorded as a real
## event -- the exit criterion made concrete: "NPCs can independently form
## ... an institution," gated by real accumulated history, not a bare
## create-on-demand call.
func test_attempting_formation_at_threshold_forms_a_real_institution():
	_fulfill_contracts_between("household:3", "household:4", 3)
	var institution = manager.attempt_institution_formation("guild", "household:3", "household:4")
	assert_not_null(institution)
	assert_eq(institution.members, ["household:3", "household:4"])

	var formed: Array = manager.event_store().events_of_type("institution_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["household:3", "household:4"])


## Asking again once already formed does not duplicate it -- the same
## once-only guard every other coordinator in this file already uses.
func test_attempting_formation_twice_does_not_duplicate_it():
	_fulfill_contracts_between("household:5", "household:6", 3)
	manager.attempt_institution_formation("guild", "household:5", "household:6")
	manager.attempt_institution_formation("guild", "household:5", "household:6")
	assert_eq(manager.institution_store().institutions_for("household:5").size(), 1)


func test_dissolving_an_institution_records_a_real_event():
	_fulfill_contracts_between("household:7", "household:8", 3)
	var institution = manager.attempt_institution_formation("guild", "household:7", "household:8")
	assert_true(manager.dissolve_institution(institution.id))

	assert_eq(manager.institution_store().get_institution(institution.id).status, "dissolved")
	var dissolved: Array = manager.event_store().events_of_type("institution_dissolved")
	assert_eq(dissolved.size(), 1)


# -- emergence: the Charter item forms real player institutions (docs/
# concept/player_citizenship.md's Charter item) -- a thin wrapper over the
# existing attempt_institution_formation naming the player's own household
# as one party, gated by the SAME real InstitutionFormation.should_form
# threshold an NPC pair is held to.

func _player_fulfill_contracts_with(counterparty_id: String, count: int) -> void:
	for i in count:
		var contract = manager.player_propose_contract("trade", counterparty_id, [], "", -1.0)
		manager.accept_contract(contract.id)
		manager.activate_contract(contract.id)
		manager.fulfill_contract(contract.id)


func test_player_attempt_institution_formation_below_threshold_forms_nothing():
	_player_fulfill_contracts_with("household:60", 2)
	var institution = manager.player_attempt_institution_formation("guild", "household:60")
	assert_null(institution)


func test_player_attempt_institution_formation_at_threshold_forms_a_real_institution_containing_the_players_household():
	_player_fulfill_contracts_with("household:61", InstitutionFormation.FORMATION_THRESHOLD)
	var institution = manager.player_attempt_institution_formation("guild", "household:61")
	assert_not_null(institution)

	var player_household_id: String = manager.household_store().household_for(
		PlayerIdentity.PLAYER_ENTITY_ID
	).id
	assert_true(institution.members.has(player_household_id))
	assert_true(institution.members.has("household:61"))


# -- emergence: the institution store persists alongside the others ---------

func test_save_institution_store_then_load_institution_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_institutions.bin"
	var institution = manager.institution_store().form("guild", ["household:1"], 1.0)

	manager.save_institution_store(path)
	manager.reset_institution_store()
	assert_null(manager.institution_store().get_institution(institution.id), "precondition: reset cleared it")
	manager.load_institution_store(path)

	assert_eq(manager.institution_store().get_institution(institution.id).type, "guild")

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_institution_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_institutions_wipe.bin"
	var institution = manager.institution_store().form("guild", ["household:1"], 1.0)
	manager.save_institution_store(path)
	manager.wipe_institution_store(path)

	assert_null(manager.institution_store().get_institution(institution.id))
	assert_false(FileAccess.file_exists(path))


# -- emergence: settlements are assessed automatically, on a real clock -----

## step_settlements is throttled -- it must not do anything before its own
## interval has elapsed, the same shape step_tree_spread already uses.
func test_step_settlements_does_nothing_before_its_interval_elapses():
	manager.record_settlement_founded_if_new(Vector2i(41, 41), [NpcIdentity.new(1)])
	manager.step_settlements(1.0)
	assert_eq(manager.event_store().events_of_type("settlement_growing").size(), 0)
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 0)


## A settlement with households and no food is genuinely under pressure --
## once the interval elapses, that is recorded as a real, automatic event,
## with no manual /command call.
func test_step_settlements_records_a_real_decline_when_food_runs_out():
	var chunk_coord := Vector2i(43, 43)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var declines: Array = manager.event_store().events_of_type("settlement_declining")
	assert_eq(declines.size(), 1)
	assert_eq(declines[0].actors, [settlement_id])


## A settlement with plenty of food shows real headroom -- growing, not
## declining, from the exact same real mechanism.
func test_step_settlements_records_growing_when_food_is_plentiful():
	var chunk_coord := Vector2i(45, 45)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("settlement_growing").size(), 1)
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 0)


## The status is not re-recorded every tick once it has settled -- only a
## real CHANGE is event-sourced, the same "do not event-source every
## low-level movement" principle every other coordinator already respects.
func test_step_settlements_does_not_repeat_an_unchanged_status():
	var chunk_coord := Vector2i(47, 47)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 1)


## ...but "changed" is not the same as "news". While capacity read only the
## persisted emergence Market it was ~always 0, status was pinned DECLINING
## and this event effectively never re-fired. It now tracks the LIVE
## VillageMarket, which rises every time a villager gathers and falls every
## time one eats -- so a settlement parked on a band boundary crosses it
## again every single step, and each crossing appends an event AND fans a
## MemoryRecord to every villager into an unbounded, persisted MemoryStore.
## One villager's dinner is not a settlement changing its fortunes: food
## oscillating across the STABLE/GROWING boundary is worth exactly the one
## event its first real status already was.
func test_step_settlements_does_not_flip_status_on_oscillating_live_food():
	var village_market_script := preload("res://src/world/village_market.gd")
	var chunk_coord := Vector2i(63, 63)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])

	var village_market = village_market_script.new()
	village_market.add_stock("meat", 4.0)  # capacity 1 for one household -> stable
	var economy := _FakeVillagerEconomy.new()
	economy.market = village_market
	var villager := _FakeVillager.new()
	villager.economy = economy
	manager._loaded_villages[chunk_coord] = [villager]

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	for step in 8:
		if step % 2 == 0:
			village_market.add_stock("meat", 4.0)  # capacity 2 -> growing
		else:
			village_market.remove_stock("meat", 4.0)  # capacity 1 -> stable
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("settlement_stable").size(), 1)
	assert_eq(manager.event_store().events_of_type("settlement_growing").size(), 0)
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 0)

	manager._loaded_villages.erase(chunk_coord)
	villager.free()


## The dwell is a filter, not a mute: a change that HOLDS is a real change
## and still lands, on exactly the step it has held long enough. The window
## is not a taste number, but it is an ordinal borrowed from the capacity
## rule rather than a duration measured against the clock -- capacity is
## floor(food / FOOD_PER_HOUSEHOLD) and a VillageMarket's smallest real move
## is one whole meal, so FOOD_PER_HOUSEHOLD single-meal moves is the
## smallest food change that can shift capacity by one whole household.
## Meals are not assessments (many meals move between two assessments 30
## world-seconds apart), so what this test pins is the behaviour, not an
## equivalence: a change that has not held for the whole window is not news,
## and one that has, is.
func test_step_settlements_records_a_status_change_that_holds_for_the_dwell():
	assert_eq(
		EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS,
		SettlementState.FOOD_PER_HOUSEHOLD,
		"the dwell is derived from the food it takes to move capacity, not picked"
	)

	var chunk_coord := Vector2i(65, 65)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # no food -> declining
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 1)

	manager.market_store().market_for(settlement_id).add_stock("meat", 200)
	for step in EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS - 1:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("settlement_growing").size(),
		0,
		"a change that has not held for the whole dwell yet is not news"
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(manager.event_store().events_of_type("settlement_growing").size(), 1)


func test_household_count_for_settlement_counts_real_households():
	var chunk_coord := Vector2i(49, 49)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.household_count_for_settlement(settlement_id), 2)


func test_household_count_for_an_unfounded_settlement_is_zero():
	assert_eq(manager.household_count_for_settlement("settlement:999_999"), 0)


# -- emergence: step_settlements also drives production, trade, and ---------
# -- institution formation automatically (closing Phase 4/5/6's own gap) ----

## step_settlements now also attempts each household's occupation-grounded
## recipe (see OccupationProduction) -- Emergence Phase 5's automatic
## trigger. Seed 5 is a real hunter (NpcIdentity.new(5).occupation ==
## "hunter"), which OccupationProduction maps to "cooked_meat"; with real
## "meat" stock already in the settlement's market, the attempt succeeds and
## is recorded exactly like a manual attempt_production call.
func test_step_settlements_attempts_production_for_a_producer_occupation():
	var chunk_coord := Vector2i(51, 51)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	# One meal's worth of meat ON TOP of what the household eats this same
	# assessment: the granary is drawn down before production runs against
	# it (see _step_settlement_granary), so a fixture that stocks exactly
	# the recipe's input is stocking a settlement's dinner, not its
	# workshop. Written off SettlementGranary's own draw rather than as a
	# larger magic number, so it tracks FOOD_PER_HOUSEHOLD if that moves.
	manager.market_store().market_for(settlement_id).add_stock(
		"meat", 1 + SettlementGranary.subsistence_draw(1)
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var successes: Array = manager.event_store().events_of_type("production_succeeded")
	assert_eq(successes.size(), 1)
	assert_eq(successes[0].tags, ["cooked_meat"])


## This used to pin the opposite case -- a settlement whose only villager
## has NO grounded recipe attempts nothing -- with seed 2 (a real guard) as
## the fixture. That premise no longer exists by design: OccupationProduction
## now maps all eight of NpcIdentity.OCCUPATIONS, on its own reasoning that an
## occupation with no recipe can never fall short of an input and so its
## household can never ask a player for anything. The guard has a recipe now,
## so what is worth pinning here is the other half of the same step: the
## settlement's market has never held that recipe's inputs, and the FIRST
## time a shortage is discovered it is real news -- one attempt, one
## production_failed. A second step re-attempts and stays silent, which is
## attempt_production's change-guard (_settlement_production_outcome) saying
## the same shortage twice is not news.
func test_step_settlements_records_a_first_production_shortfall_once():
	var recipe_id := OccupationProduction.recipe_for(NpcIdentity.new(2).occupation)
	assert_ne(recipe_id, "", "precondition: seed 2's occupation is a mapped one")

	var chunk_coord := Vector2i(53, 53)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(2)])
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var failures: Array = manager.event_store().events_of_type("production_failed")
	assert_eq(failures.size(), 1)
	assert_eq(failures[0].tags, [recipe_id])
	assert_eq(manager.event_store().events_of_type("production_succeeded").size(), 0)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("production_failed").size(),
		1,
		"the same shortage a second time is not news"
	)


## step_settlements also drives a settlement's own internal trade --
## Emergence Phase 4's automatic trigger. Two households in the same
## settlement propose/accept/activate/fulfill a real trade contract every
## step, with no manual /command call.
func test_step_settlements_trades_between_its_own_households_when_prospering():
	var chunk_coord := Vector2i(55, 55)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(10), NpcIdentity.new(11)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)  # plenty -> growing/stable

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("contract_fulfilled").size(), 1)


## A settlement with only one household has no one to trade with -- skipped,
## not forced onto a solo "trade."
func test_step_settlements_does_not_trade_with_only_one_household():
	var chunk_coord := Vector2i(57, 57)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(manager.event_store().events_of_type("contract_proposed").size(), 0)


## A DECLINING settlement's own internal trade breaches instead of
## fulfilling -- the same real number (food-driven prosperity, Phase 7) now
## drives Phase 4's automatic outcome too, not just its status label.
func test_step_settlements_breaches_trade_in_a_declining_settlement():
	var chunk_coord := Vector2i(59, 59)
	# Founders who gather NOTHING, so "no food" is a property of the
	# settlement rather than of an arbitrary chunk index. Before the
	# emergence market had a source this was free -- every settlement in the
	# world was permanently declining -- and a fixture that says "no food"
	# now has to actually mean it.
	var founders: Array = []
	for a_seed in _non_producer_seeds(2):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # no food -> declining

	assert_eq(manager.event_store().events_of_type("contract_breached").size(), 1)
	assert_eq(manager.event_store().events_of_type("contract_fulfilled").size(), 0)


## Given enough real settlement steps, the same two households' repeated
## fulfilled trades cross InstitutionFormation's real threshold and an
## institution forms with NO manual /command call -- Emergence Phase 6's
## automatic trigger, genuinely downstream of Phase 4's (it needs real
## fulfilled contracts to exist before it can find anything).
func test_step_settlements_eventually_forms_an_institution_from_repeated_trade():
	var chunk_coord := Vector2i(61, 61)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(30), NpcIdentity.new(31)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	for i in InstitutionFormation.FORMATION_THRESHOLD:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("institution_formed").size(), 1)


# -- emergence: Phase 8 -- worn paths are a real, causally-grounded entity --

## The literal "repeated movement creates infrastructure" exit criterion
## (docs/emergence/04): the FIRST time a tile becomes worn, that is a real,
## `/why`-inspectable event, not just a texture change.
func test_recording_a_worn_path_records_a_real_event():
	manager.record_path_worn_if_new(Vector2i(5, 5))
	var formed: Array = manager.event_store().events_of_type("path_worn")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["path:5_5"])


## Idempotent while already worn -- the caller (World._step_path_scarring)
## only calls this at a real state transition, but the store itself is ALSO
## guarded (reading real persisted event history, not the caller's own
## in-memory transition flag) so a reload cannot record a duplicate
## founding for a path already known to be worn.
func test_recording_the_same_worn_path_twice_does_not_duplicate_it():
	manager.record_path_worn_if_new(Vector2i(6, 6))
	manager.record_path_worn_if_new(Vector2i(6, 6))
	assert_eq(manager.event_store().events_for_entity("path:6_6").size(), 1)


## Nature reclaiming a path (docs/emergence/04 "Infrastructure degrades") is
## exactly as recorded as a path forming.
func test_reclaiming_a_worn_path_records_a_real_event():
	manager.record_path_worn_if_new(Vector2i(7, 7))
	manager.record_path_reclaimed(Vector2i(7, 7))
	var reclaimed: Array = manager.event_store().events_of_type("path_reclaimed")
	assert_eq(reclaimed.size(), 1)
	assert_eq(reclaimed[0].actors, ["path:7_7"])


## A path that was never worn cannot be reclaimed -- there is nothing real
## to record.
func test_reclaiming_a_path_that_was_never_worn_records_nothing():
	manager.record_path_reclaimed(Vector2i(8, 8))
	assert_eq(manager.event_store().events_for_entity("path:8_8").size(), 0)


## A path can be worn, reclaimed by nature, and worn again over a real
## session -- each cycle is real, distinct history, not a duplicate of the
## first.
func test_a_reclaimed_path_can_be_worn_again():
	manager.record_path_worn_if_new(Vector2i(9, 9))
	manager.record_path_reclaimed(Vector2i(9, 9))
	manager.record_path_worn_if_new(Vector2i(9, 9))
	assert_eq(manager.event_store().events_of_type("path_worn").size(), 2)


## The same composition contracts every other phase already demonstrated:
## the path forms a real firsthand memory of its own founding.
func test_a_worn_path_is_remembered():
	manager.record_path_worn_if_new(Vector2i(10, 10))
	var memories: Array = manager.memory_store().memories_for("path:10_10")
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].source_type, MemoryRecord.FIRSTHAND)


# -- the trail tier (docs/concept/infrastructure.md's "path -> trail -> road",
# PathScarring.TRAIL_THRESHOLD/is_trail) -- the SAME real path entity
# deepening, not a new kind of thing.

## Sustained, heavier use of an already-worn path is just as real and
## `/why`-inspectable an event as the path forming in the first place.
func test_recording_a_formed_trail_records_a_real_event():
	manager.record_trail_formed_if_new(Vector2i(11, 11))
	var formed: Array = manager.event_store().events_of_type("trail_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["path:11_11"])


func test_recording_the_same_formed_trail_twice_does_not_duplicate_it():
	manager.record_trail_formed_if_new(Vector2i(12, 12))
	manager.record_trail_formed_if_new(Vector2i(12, 12))
	assert_eq(manager.event_store().events_for_entity("path:12_12").size(), 1)


## Tapering from Trail back down to an ordinary worn Path is a real, DISTINCT
## transition from a full path_reclaimed -- the ground is still a path, just
## no longer compacted to the ceiling.
func test_reclaiming_a_trail_records_a_real_event_distinct_from_a_full_reclaim():
	manager.record_trail_formed_if_new(Vector2i(13, 13))
	manager.record_trail_reclaimed(Vector2i(13, 13))
	var reclaimed: Array = manager.event_store().events_of_type("trail_reclaimed")
	assert_eq(reclaimed.size(), 1)
	assert_eq(reclaimed[0].actors, ["path:13_13"])
	assert_eq(manager.event_store().events_of_type("path_reclaimed").size(), 0)


func test_reclaiming_a_trail_that_was_never_formed_records_nothing():
	manager.record_trail_reclaimed(Vector2i(14, 14))
	assert_eq(manager.event_store().events_for_entity("path:14_14").size(), 0)


## A tile can decay straight from Trail past Path to bare ground within one
## real gap (a long absence, a big delta) without an intermediate refresh
## ever observing the plain "worn but not a trail" state in between --
## record_path_reclaimed still has to recognize that as a real reclaim
## rather than silently refusing it because the last-seen tier was the
## deeper one.
func test_a_path_can_be_fully_reclaimed_straight_from_its_trail_tier():
	manager.record_path_worn_if_new(Vector2i(15, 15))
	manager.record_trail_formed_if_new(Vector2i(15, 15))
	manager.record_path_reclaimed(Vector2i(15, 15))
	var reclaimed: Array = manager.event_store().events_of_type("path_reclaimed")
	assert_eq(reclaimed.size(), 1)
	assert_eq(reclaimed[0].actors, ["path:15_15"])


# -- emergence: Phase 9 -- town/city tier and specialization, from real flows

## Crossing ALL THREE real dimensions (3 households, 1 active institution
## via the automatic trade chain, 1 distinct produced recipe) becomes a real
## town -- with NO manual call to anything, the whole chain running off the
## same automatic settlement steps Phase 4/5/6 already established.
func test_step_settlements_records_a_real_tier_change_when_crossing_town_thresholds():
	var chunk_coord := Vector2i(63, 63)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(5), NpcIdentity.new(10), NpcIdentity.new(11)]
	)  # seed 5 is a real hunter
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	for i in InstitutionFormation.FORMATION_THRESHOLD:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var became_town: Array = manager.event_store().events_of_type("settlement_became_town")
	assert_eq(became_town.size(), 1)
	assert_eq(became_town[0].actors, [settlement_id])


## The doc's own explicit point, proven through the REAL automatic
## mechanism rather than asserted in the abstract: high population with no
## food means every trade breaches (Phase 4), so no institution ever forms
## (Phase 6) and nothing is ever produced either -- population alone stays
## a hamlet.
func test_step_settlements_stays_a_hamlet_on_population_alone():
	var chunk_coord := Vector2i(65, 65)
	var npcs: Array = []
	for i in 5:
		npcs.append(NpcIdentity.new(100 + i))
	manager.record_settlement_founded_if_new(chunk_coord, npcs)

	for i in InstitutionFormation.FORMATION_THRESHOLD:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("settlement_became_town").size(), 0)


## Specialization is "derived from flows" made concrete: a real hunter
## household with real meat stock produces cooked_meat, and that shows up
## as a real, automatic settlement_specialized event.
func test_step_settlements_records_specialization_once_grounded():
	var chunk_coord := Vector2i(67, 67)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var specialized: Array = manager.event_store().events_of_type("settlement_specialized")
	assert_eq(specialized.size(), 1)
	assert_eq(specialized[0].tags, ["hunting center"])


## A tier that has already settled is not re-recorded every step -- the same
## "only a real CHANGE is event-sourced" discipline every other coordinator
## here already respects.
func test_step_settlements_does_not_repeat_an_unchanged_tier():
	var chunk_coord := Vector2i(69, 69)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(5), NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	for i in InstitutionFormation.FORMATION_THRESHOLD + 1:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("settlement_became_town").size(), 1)


func test_active_institution_count_for_settlement_counts_real_active_institutions():
	var chunk_coord := Vector2i(71, 71)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id
	_fulfill_contracts_between(household_a, household_b, InstitutionFormation.FORMATION_THRESHOLD)
	manager.attempt_institution_formation("guild", household_a, household_b)

	assert_eq(manager.active_institution_count_for_settlement(settlement_id), 1)


func test_active_institution_count_for_an_unfounded_settlement_is_zero():
	assert_eq(manager.active_institution_count_for_settlement("settlement:999_999"), 0)


func test_production_counts_for_settlement_counts_real_successes_by_recipe():
	var settlement_id := "settlement:73_73"
	manager.market_store().market_for(settlement_id).add_stock("meat", 3)
	manager.attempt_production(settlement_id, "cooked_meat")
	manager.attempt_production(settlement_id, "cooked_meat")

	assert_eq(manager.production_counts_for_settlement(settlement_id), {"cooked_meat": 2})


func test_production_counts_ignore_failed_attempts():
	var settlement_id := "settlement:75_75"
	manager.attempt_production(settlement_id, "cooked_meat")  # no stock -- fails
	assert_eq(manager.production_counts_for_settlement(settlement_id), {})


# -- emergence: Phase 10 -- ruins, formed from at least 3 independent causes -

## Source 1 (docs/emergence/05 "Historical catastrophe"): a real event
## records a real ruin, with the causing event actually LINKED as its
## cause -- "Creation causes must be stored," made concrete and traceable,
## not just a bare label.
func test_record_ruin_from_settlement_decline_records_a_real_event_with_a_real_cause():
	var cause := Event.new("settlement_declining", 1.0)
	var cause_id := manager.event_store().append(cause)

	manager.record_ruin_from_settlement_decline("settlement:77_77", cause_id)

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["ruin:settlement_77_77"])
	var causes: Array = manager.event_store().causes_of(formed[0].id)
	assert_eq(causes.size(), 1)
	assert_eq(causes[0].id, cause_id)


func test_recording_the_same_settlement_decline_ruin_twice_does_not_duplicate_it():
	var cause_id := manager.event_store().append(Event.new("settlement_declining", 1.0))
	manager.record_ruin_from_settlement_decline("settlement:79_79", cause_id)
	manager.record_ruin_from_settlement_decline("settlement:79_79", cause_id)
	assert_eq(manager.event_store().events_for_entity("ruin:settlement_79_79").size(), 1)


## Source 2 (docs/emergence/05 "Ecological transformation... overgrown
## ruins"): nature reclaiming a path IS this dungeon source, verbatim.
func test_record_ruin_from_reclaimed_path_records_a_real_event_with_a_real_cause():
	var cause_id := manager.event_store().append(Event.new("path_reclaimed", 1.0))
	manager.record_ruin_from_reclaimed_path("path:5_5", cause_id)

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["ruin:path_5_5"])


## Source 3 (docs/emergence/05 "Social transformation... abandoned
## prisons"): a dissolved institution's old headquarters. Institution ids
## are NOT EntityRef "kind:key" strings (InstitutionStore.form's own
## "inst_<ordinal>_<type>" shape) -- used verbatim rather than run through
## EntityRef.key_of, which only strips a colon-separated prefix.
func test_record_ruin_from_dissolved_institution_records_a_real_event_with_a_real_cause():
	var cause_id := manager.event_store().append(Event.new("institution_dissolved", 1.0))
	manager.record_ruin_from_dissolved_institution("inst_3_guild", cause_id)

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["ruin:institution_inst_3_guild"])


## The literal exit criterion: at least three INDEPENDENT causal sources,
## proven by using the exact same raw location number ("5_5") across all
## three source kinds without collapsing into one ruin -- each source's own
## kind prefix keeps them genuinely independent.
func test_three_different_ruin_sources_produce_three_independent_ruins():
	var cause_a := manager.event_store().append(Event.new("settlement_declining", 1.0))
	var cause_b := manager.event_store().append(Event.new("path_reclaimed", 1.0))
	var cause_c := manager.event_store().append(Event.new("institution_dissolved", 1.0))

	manager.record_ruin_from_settlement_decline("settlement:5_5", cause_a)
	manager.record_ruin_from_reclaimed_path("path:5_5", cause_b)
	manager.record_ruin_from_dissolved_institution("inst_5_5", cause_c)

	assert_eq(manager.event_store().events_of_type("ruin_formed").size(), 3)


## The same composition contracts every other phase already demonstrated:
## a ruin forms a real firsthand memory of its own founding.
func test_a_ruin_is_remembered():
	var cause_id := manager.event_store().append(Event.new("path_reclaimed", 1.0))
	manager.record_ruin_from_reclaimed_path("path:9_9", cause_id)
	var memories: Array = manager.memory_store().memories_for("ruin:path_9_9")
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].source_type, MemoryRecord.FIRSTHAND)


# -- emergence: Phase 10's automatic triggers -------------------------------

## A settlement that automatically declines (Phase 7's own real trigger)
## automatically leaves behind a real ruin too -- with ZERO manual call to
## record_ruin_from_settlement_decline.
func test_step_settlements_forms_a_ruin_automatically_when_a_settlement_declines():
	var chunk_coord := Vector2i(81, 81)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # no food -> declines

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["ruin:settlement_%d_%d" % [chunk_coord.x, chunk_coord.y]])

	var declines: Array = manager.event_store().events_of_type("settlement_declining")
	var causes: Array = manager.event_store().causes_of(formed[0].id)
	assert_eq(causes[0].id, declines[0].id)


## A path nature reclaims (Phase 8's own real trigger) automatically leaves
## a ruin behind too -- with ZERO manual call to
## record_ruin_from_reclaimed_path.
func test_record_path_reclaimed_forms_a_ruin_automatically():
	manager.record_path_worn_if_new(Vector2i(11, 11))
	manager.record_path_reclaimed(Vector2i(11, 11))

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)
	assert_eq(formed[0].actors, ["ruin:path_11_11"])


## Dissolving an institution (Phase 6's real, callable mechanism) forms a
## real ruin too, in the same call.
func test_dissolving_an_institution_forms_a_ruin():
	_fulfill_contracts_between("household:9", "household:10", InstitutionFormation.FORMATION_THRESHOLD)
	var institution := manager.attempt_institution_formation("guild", "household:9", "household:10")

	manager.dissolve_institution(institution.id)

	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1)


# -- emergence: Phase 11 -- world bosses, promoted from real fitness data ---

## Below the real, tested WorldBossFitness threshold, nothing is promoted --
## the whole point of a real threshold rather than a bare create-on-demand
## call.
func test_attempting_promotion_below_threshold_promotes_nothing():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var boss := manager.attempt_world_boss_promotion(
		"creature:1", "herbivore", 1, 0, 5.0, "a small boar", generator
	)
	assert_null(boss)
	assert_eq(manager.event_store().events_of_type("world_boss_promoted").size(), 0)


## At/above the real threshold, a real boss is promoted AND recorded as a
## real event -- docs/emergence/05's own "Boss emergence... must
## permanently affect the world" made concrete: a real, /why-inspectable
## promotion, not a scripted one.
func test_attempting_promotion_at_threshold_promotes_a_real_boss():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var boss := manager.attempt_world_boss_promotion(
		"creature:2", "predator", 50, 200, 500000.0, "an apex wolf", generator
	)
	assert_not_null(boss)
	assert_eq(boss.species, "predator")
	assert_eq(boss.phases, generator.generate_phases("an apex wolf"))

	var promoted: Array = manager.event_store().events_of_type("world_boss_promoted")
	assert_eq(promoted.size(), 1)
	assert_eq(promoted[0].actors, ["creature:2"])
	assert_eq(promoted[0].tags, ["predator"])


## Asking again once already promoted does not duplicate it -- the same
## once-only guard every other coordinator in this file already uses.
func test_attempting_promotion_twice_does_not_duplicate_it():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	manager.attempt_world_boss_promotion("creature:3", "predator", 50, 200, 500000.0, "x", generator)
	manager.attempt_world_boss_promotion("creature:3", "predator", 50, 200, 500000.0, "x", generator)
	assert_eq(manager.event_store().events_of_type("world_boss_promoted").size(), 1)


## The phase generator (which may wrap a real, costly LLM call) is never
## invoked for an ineligible individual -- WorldBossFitness's own guarantee,
## still true through the coordinator.
func test_attempting_promotion_below_threshold_never_invokes_the_phase_generator():
	var counting_generator := _CountingPhaseGenerator.new()
	manager.attempt_world_boss_promotion("creature:4", "herbivore", 1, 0, 5.0, "x", counting_generator)
	assert_eq(counting_generator.call_count, 0)


func test_defeating_a_boss_records_a_real_event():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var boss := manager.attempt_world_boss_promotion(
		"creature:5", "predator", 50, 200, 500000.0, "an apex wolf", generator
	)
	assert_true(manager.defeat_world_boss(boss.id))

	assert_eq(manager.world_boss_store().get_boss(boss.id).status, WorldBoss.DEFEATED)
	var defeated: Array = manager.event_store().events_of_type("world_boss_defeated")
	assert_eq(defeated.size(), 1)
	assert_eq(defeated[0].actors, ["creature:5"])


func test_defeating_an_unknown_boss_fails_and_records_nothing():
	assert_false(manager.defeat_world_boss("boss_999_predator"))
	assert_eq(manager.event_store().events_of_type("world_boss_defeated").size(), 0)


## The same composition contracts every other phase already demonstrated:
## the promoted individual forms a real firsthand memory of its own
## promotion.
func test_a_promoted_boss_is_remembered():
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	manager.attempt_world_boss_promotion("creature:6", "predator", 50, 200, 500000.0, "x", generator)
	var memories: Array = manager.memory_store().memories_for("creature:6")
	assert_eq(memories.size(), 1)
	assert_eq(memories[0].source_type, MemoryRecord.FIRSTHAND)


# -- emergence: the world-boss store persists alongside the others ---------

func test_save_world_boss_store_then_load_world_boss_store_round_trips_live_state():
	var path := "user://test_ecm_emergence_world_bosses.bin"
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var boss := manager.attempt_world_boss_promotion(
		"creature:7", "predator", 50, 200, 500000.0, "x", generator
	)

	manager.save_world_boss_store(path)
	manager.reset_world_boss_store()
	assert_null(manager.world_boss_store().get_boss(boss.id), "precondition: reset cleared it")
	manager.load_world_boss_store(path)

	assert_eq(manager.world_boss_store().get_boss(boss.id).species, "predator")

	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_wipe_world_boss_store_clears_both_memory_and_disk():
	var path := "user://test_ecm_emergence_world_bosses_wipe.bin"
	var generator := WorldBossFitness.FakePhaseGenerator.new()
	var boss := manager.attempt_world_boss_promotion(
		"creature:8", "predator", 50, 200, 500000.0, "x", generator
	)
	manager.save_world_boss_store(path)
	manager.wipe_world_boss_store(path)

	assert_null(manager.world_boss_store().get_boss(boss.id))
	assert_false(FileAccess.file_exists(path))


## Test double that counts calls, matching test_world_boss_fitness.gd's own
## _CountingPhaseGenerator convention.
class _CountingPhaseGenerator extends WorldBossFitness.PhaseGenerator:
	var call_count := 0

	func generate_phases(_trait_description: String) -> Array:
		call_count += 1
		return []


# -- gap-closing: automatic institution dissolution (Phase 6's own gap) -----

## The literal gap closed: an institution with plenty of all-time
## fulfilled-contract history (which alone would have kept the old
## all-time-count check from ever firing) genuinely dissolves once real
## time passes with no NEW coordination -- with a real, automatic call to
## step_settlements, not a direct call to dissolve_institution.
func test_step_settlements_dissolves_an_institution_that_has_gone_quiet():
	var chunk_coord := Vector2i(83, 83)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id

	_fulfill_contracts_between(household_a, household_b, InstitutionFormation.FORMATION_THRESHOLD)
	var institution := manager.attempt_institution_formation("cooperative", household_a, household_b)
	assert_not_null(institution, "precondition: institution formed")

	manager.set_world_age_seconds(InstitutionFormation.RECENT_WINDOW_SECONDS + 100.0)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.institution_store().get_institution(institution.id).status, "dissolved")
	assert_eq(manager.event_store().events_of_type("institution_dissolved").size(), 1)


## An institution whose pair keeps trading every real automatic step (a
## settlement that stays prospering, never running out of food) stays
## active well past the recent window's length -- ongoing activity
## genuinely protects it, proven through repeated real automatic steps
## rather than a single isolated post-jump trade (which would only ever
## produce exactly ONE recent contract -- itself at or below
## DISSOLUTION_THRESHOLD, an easy false-dissolve trap this test guards
## against by simulating real sustained activity instead).
func test_step_settlements_does_not_dissolve_an_institution_still_actively_trading():
	var chunk_coord := Vector2i(85, 85)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)  # keeps it prospering
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id

	for i in InstitutionFormation.FORMATION_THRESHOLD + 5:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var institution := manager.institution_store().active_institution_for([household_a, household_b])
	assert_not_null(institution, "precondition: institution formed")
	assert_eq(institution.status, "active")
	assert_eq(manager.event_store().events_of_type("institution_dissolved").size(), 0)


# -- gap-closing: rumor auto-propagation at real NPC meetings (Phase 2) -----

func _add_scheduled_npc(seed_value: int, location_tag: String) -> NpcMarker:
	var npc := NpcMarker.new()
	npc.identity = NpcIdentity.new(seed_value)
	npc.schedule = [{"time_block": "midday", "location_tag": location_tag, "activity": "idle"}]
	creatures_parent.add_child(npc)
	return npc


## Real end-to-end: two NPCs at the same real landmark, on their real
## schedule, at a real shared hour derived from the world clock -- the
## literal npc.md exit language ("NPCs already meet at a settlement's
## shared landmarks... on their daily schedule") made concrete, with zero
## manual calls to MemoryStore.transmit anywhere in this test.
func test_step_npc_encounters_transmits_a_memory_between_two_npcs_at_the_same_landmark():
	manager.set_world_age_seconds(30.0)  # hour 12 == "midday"
	var teller := _add_scheduled_npc(1, "well")
	var listener := _add_scheduled_npc(2, "well")
	manager._loaded_villages[Vector2i(0, 0)] = [teller, listener]

	var teller_id := EntityRef.for_npc(1)
	var listener_id := EntityRef.for_npc(2)
	var event := Event.new("something_happened", 1.0)
	event.actors.append(teller_id)
	manager.event_store().append(event)
	manager.memory_store().witness_event(event, 1.0)

	manager.step_npc_encounters(EarthChunkManager.NPC_ENCOUNTER_INTERVAL)

	var listener_memories: Array = manager.memory_store().memories_for(listener_id)
	assert_eq(listener_memories.size(), 1)
	assert_eq(listener_memories[0].event_id, event.id)
	assert_eq(listener_memories[0].source_type, MemoryRecord.TRUSTED_TESTIMONY)

	teller.free()
	listener.free()


## Throttled -- the same shape every other periodic coordinator here uses.
func test_step_npc_encounters_does_nothing_before_its_interval_elapses():
	manager.set_world_age_seconds(30.0)
	var teller := _add_scheduled_npc(1, "well")
	var listener := _add_scheduled_npc(2, "well")
	manager._loaded_villages[Vector2i(0, 0)] = [teller, listener]
	var event := Event.new("something_happened", 1.0)
	event.actors.append(EntityRef.for_npc(1))
	manager.event_store().append(event)
	manager.memory_store().witness_event(event, 1.0)

	manager.step_npc_encounters(1.0)

	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(2)).size(), 0)
	teller.free()
	listener.free()


## Two NPCs at DIFFERENT landmarks never exchange -- no invented meeting.
func test_step_npc_encounters_does_not_transmit_between_npcs_at_different_landmarks():
	manager.set_world_age_seconds(30.0)
	var teller := _add_scheduled_npc(1, "well")
	var elsewhere := _add_scheduled_npc(2, "gate")
	manager._loaded_villages[Vector2i(0, 0)] = [teller, elsewhere]
	var event := Event.new("something_happened", 1.0)
	event.actors.append(EntityRef.for_npc(1))
	manager.event_store().append(event)
	manager.memory_store().witness_event(event, 1.0)

	manager.step_npc_encounters(EarthChunkManager.NPC_ENCOUNTER_INTERVAL)

	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(2)).size(), 0)
	teller.free()
	elsewhere.free()


## A meeting is bidirectional -- each npc's own most recent memory
## transmits to the other, not just one direction.
func test_step_npc_encounters_transmission_is_bidirectional():
	manager.set_world_age_seconds(30.0)
	var a := _add_scheduled_npc(1, "well")
	var b := _add_scheduled_npc(2, "well")
	manager._loaded_villages[Vector2i(0, 0)] = [a, b]

	var event_a := Event.new("thing_a", 1.0)
	event_a.actors.append(EntityRef.for_npc(1))
	manager.event_store().append(event_a)
	manager.memory_store().witness_event(event_a, 1.0)

	var event_b := Event.new("thing_b", 2.0)
	event_b.actors.append(EntityRef.for_npc(2))
	manager.event_store().append(event_b)
	manager.memory_store().witness_event(event_b, 2.0)

	manager.step_npc_encounters(EarthChunkManager.NPC_ENCOUNTER_INTERVAL)

	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(1)).size(), 2)
	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(2)).size(), 2)
	a.free()
	b.free()


## An npc with no memories yet has nothing to tell -- a real no-op, not an
## error.
func test_step_npc_encounters_handles_an_npc_with_no_memories_gracefully():
	manager.set_world_age_seconds(30.0)
	var a := _add_scheduled_npc(1, "well")
	var b := _add_scheduled_npc(2, "well")
	manager._loaded_villages[Vector2i(0, 0)] = [a, b]

	manager.step_npc_encounters(EarthChunkManager.NPC_ENCOUNTER_INTERVAL)

	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(1)).size(), 0)
	assert_eq(manager.memory_store().memories_for(EntityRef.for_npc(2)).size(), 0)
	a.free()
	b.free()


# -- emergence: Phase 12 -- quests as real projections, never new state ----

## A real settlement with a real blacksmith household and an empty market
## produces a real, discoverable quest -- reading straight off the same
## household/market state every other coordinator already touches.
func test_production_shortfall_quests_for_settlement_reads_real_state():
	var chunk_coord := Vector2i(87, 87)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(8)])  # seed 8 is a real blacksmith
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	var quests := manager.production_shortfall_quests_for_settlement(settlement_id)

	assert_eq(quests.size(), 1)
	assert_eq(quests[0]["recipe_id"], "stone_pickaxe")


## Once the market genuinely has what the recipe needs, the SAME query
## reflects that immediately -- no stale quest hanging around, proving this
## is a live projection, not recorded state.
func test_production_shortfall_quests_disappear_once_the_market_is_stocked():
	var chunk_coord := Vector2i(89, 89)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(8)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.production_shortfall_quests_for_settlement(settlement_id).size(), 1, "precondition")

	manager.market_store().market_for(settlement_id).add_stock("stick", 2)
	manager.market_store().market_for(settlement_id).add_stock("rock", 3)

	assert_eq(manager.production_shortfall_quests_for_settlement(settlement_id).size(), 0)


func test_production_shortfall_quests_for_an_unfounded_settlement_is_empty():
	assert_eq(manager.production_shortfall_quests_for_settlement("settlement:999_999"), [])


# -- emergence: Phase 13 -- governance form and legitimacy, from real flows -

func test_governance_form_for_settlement_reads_real_institution_history():
	var chunk_coord := Vector2i(91, 91)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id
	_fulfill_contracts_between(household_a, household_b, InstitutionFormation.FORMATION_THRESHOLD)
	manager.attempt_institution_formation("militia", household_a, household_b)

	assert_eq(manager.governance_form_for_settlement(settlement_id), "military rule")


func test_institution_type_counts_for_settlement_counts_real_history():
	var chunk_coord := Vector2i(101, 101)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)])
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id
	_fulfill_contracts_between(household_a, household_b, InstitutionFormation.FORMATION_THRESHOLD)
	manager.attempt_institution_formation("militia", household_a, household_b)

	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.institution_type_counts_for_settlement(settlement_id), {"militia": 1})


func test_governance_form_for_a_settlement_with_no_institutions_is_none():
	var chunk_coord := Vector2i(93, 93)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.governance_form_for_settlement(settlement_id), "none")


func test_legitimacy_for_settlement_reads_real_food_status():
	var chunk_coord := Vector2i(95, 95)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)
	assert_eq(manager.legitimacy_for_settlement(settlement_id), "high")


func test_legitimacy_for_an_empty_market_settlement_is_low():
	var chunk_coord := Vector2i(97, 97)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.legitimacy_for_settlement(settlement_id), "low")


## The real "changes actual decisions" test: a settlement with a real
## military-rule history (a militia already formed between a DIFFERENT
## pair of its households) has its NEXT automatic institution formation
## attempt a militia too -- not the old hardcoded "cooperative" -- proven
## through the real automatic step_settlements chain, not a direct call.
func test_step_settlements_forms_the_governance_appropriate_institution_type():
	var chunk_coord := Vector2i(99, 99)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2), NpcIdentity.new(3)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)
	var household_1: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_3: String = manager.household_store().household_for(EntityRef.for_npc(3)).id

	# Establish military-rule governance via a DIFFERENT pair
	# (household:1/household:3) than the one step_settlements' own
	# automatic trade will use (the lowest two, household:1/household:2) --
	# so this doesn't block the automatic pair's own formation.
	_fulfill_contracts_between(household_1, household_3, InstitutionFormation.FORMATION_THRESHOLD)
	manager.attempt_institution_formation("militia", household_1, household_3)
	assert_eq(manager.governance_form_for_settlement(settlement_id), "military rule", "precondition")

	for i in InstitutionFormation.FORMATION_THRESHOLD:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var household_2: String = manager.household_store().household_for(EntityRef.for_npc(2)).id
	var new_institution := manager.institution_store().active_institution_for([household_1, household_2])
	assert_not_null(new_institution, "precondition: the automatic pair actually formed one")
	assert_eq(new_institution.type, "militia")


# -- emergence: Phase 14 -- regional trade, one real edge at a time --------

## A real settlement with a real production shortfall (Phase 12's own
## Quest) has a caravan dispatched from the nearest OTHER real settlement's
## real surplus -- the supplier's stock is gone immediately (goods really
## in transit, real risk -- see docs/concept/trade.md), but the shortage
## settlement isn't credited yet: that only happens once the caravan
## actually finishes walking there (see the arrival test below).
func test_step_regional_trade_departs_a_caravan_but_defers_the_shortage_credit():
	var shortage_coord := Vector2i(0, 0)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])  # blacksmith
	var shortage_id := EntityRef.for_settlement(shortage_coord)

	var supplier_coord := Vector2i(1, 0)
	manager.record_settlement_founded_if_new(supplier_coord, [NpcIdentity.new(1)])
	var supplier_id := EntityRef.for_settlement(supplier_coord)
	manager.market_store().market_for(supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(supplier_id).add_stock("stick", 20)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)

	# The supplier is really out this stock right away -- stone_pickaxe
	# needs 2 stick + 3 rock.
	assert_eq(manager.market_store().market_for(supplier_id).stock_of("rock"), 17)
	assert_eq(manager.market_store().market_for(supplier_id).stock_of("stick"), 18)
	# But the shortage settlement has nothing yet -- it's still on the road.
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("rock"), 0)
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("stick"), 0)

	# stone_pickaxe needs both rock and stick -- one real caravan per missing
	# item, each its own departure event.
	var departed: Array = manager.event_store().events_of_type("regional_trade_departed")
	assert_eq(departed.size(), 2)
	for event in departed:
		assert_eq(event.actors, [supplier_id, shortage_id])
	assert_eq(manager.event_store().events_of_type("regional_trade_shipped").size(), 0)
	assert_eq(manager._active_caravans.size(), 2)


## The other real half of the same trip: once a departed caravan actually
## finishes walking the real route to the shortage settlement's own well,
## the shortage settlement is credited and the "shipped" event becomes
## real -- not at the moment of departure. supplier=(-1,0) is a real fixed
## point where actually running CaravanRaid.roll_for on both real items
## (rock, stick) at departure_age 0.0 clears HARD tier's own chance for
## neither -- a clean, deliberately unraided pair, contrasting with the
## deliberately-raided one the raid test below uses.
func test_a_departed_caravan_credits_the_shortage_settlement_on_real_arrival():
	var shortage_coord := Vector2i(0, 0)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])
	var shortage_id := EntityRef.for_settlement(shortage_coord)

	var supplier_coord := Vector2i(-1, 0)
	manager.record_settlement_founded_if_new(supplier_coord, [NpcIdentity.new(1)])
	var supplier_id := EntityRef.for_settlement(supplier_coord)
	manager.market_store().market_for(supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(supplier_id).add_stock("stick", 20)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)
	assert_eq(manager._active_caravans.size(), 2, "precondition: both caravans are on the road")

	# Walk them all the way there -- one real chunk apart is a short enough
	# route that a handful of seconds-sized steps comfortably clears it,
	# whatever CaravanTrip.WALK_SPEED_PX_PER_SEC happens to be tuned to.
	for i in 200:
		manager.advance_world_age(1.0)
		manager.step_caravans()
		if manager._active_caravans.is_empty():
			break

	assert_true(manager._active_caravans.is_empty(), "both caravans should have resolved by now")
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("rock"), 3)
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("stick"), 2)

	var shipped: Array = manager.event_store().events_of_type("regional_trade_shipped")
	assert_eq(shipped.size(), 2)
	for event in shipped:
		assert_eq(event.actors, [supplier_id, shortage_id])


## Walking a real route wears it, the same real PathScarring.step_on every
## other repeated-traffic system in this codebase already uses (see
## docs/concept/infrastructure.md) -- a caravan is a second real caller of
## it, not a cosmetic-only walk.
func test_a_caravan_wears_a_real_path_along_its_route():
	var shortage_coord := Vector2i(0, 0)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])
	var supplier_coord := Vector2i(1, 0)
	manager.record_settlement_founded_if_new(supplier_coord, [NpcIdentity.new(1)])
	var supplier_id := EntityRef.for_settlement(supplier_coord)
	manager.market_store().market_for(supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(supplier_id).add_stock("stick", 20)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)
	assert_eq(manager._caravan_path_scarring.tracked_tile_count(), 0, "precondition: no wear yet")

	# A handful of small steps partway along the route -- enough to cross
	# several tiles without necessarily finishing the whole trip.
	for i in 10:
		manager.advance_world_age(1.0)
		manager.step_caravans()

	assert_gt(manager._caravan_path_scarring.tracked_tile_count(), 0)


## A raided trip never reaches the shortage settlement -- its carried goods
## scatter into the world via WorldItemBus (the same real drop path a
## felled tree or a smashed stone already uses) instead of being credited.
## supplier=(0,1)/shortage=(0,0)/departure_age=0.0 is a real fixed point:
## exercising the real, production CaravanRaid.roll_for with these exact
## real inputs (not mocked, not invented) puts the ROCK trip's roll under
## HARD tier's real chance while the STICK trip's roll clears it -- so this
## one scenario also proves two caravans from the same shortage resolve
## fully independently. Found once by actually running roll_for with these
## inputs, the same "chosen coordinates that force a specific real outcome"
## approach test_step_regional_trade_prefers_the_nearest_surplus_settlement
## already uses for distance.
func test_a_raided_caravan_scatters_its_goods_while_its_sibling_still_arrives():
	var shortage_coord := Vector2i(0, 0)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])  # blacksmith
	var shortage_id := EntityRef.for_settlement(shortage_coord)

	var supplier_coord := Vector2i(0, 1)
	manager.record_settlement_founded_if_new(supplier_coord, [NpcIdentity.new(1)])
	var supplier_id := EntityRef.for_settlement(supplier_coord)
	manager.market_store().market_for(supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(supplier_id).add_stock("stick", 20)

	var dropped_stacks: Array = []
	var dropped_positions: Array = []
	WorldItemBus.item_dropped.connect(
		func(item_stack, world_position): dropped_stacks.append(item_stack); dropped_positions.append(world_position)
	)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)
	assert_eq(manager._active_caravans.size(), 2, "precondition: both caravans are on the road")

	for i in 200:
		manager.advance_world_age(1.0)
		manager.step_caravans()
		if manager._active_caravans.is_empty():
			break

	assert_true(manager._active_caravans.is_empty(), "both caravans should have resolved by now")
	# Rock was raided -- never arrives. Stick wasn't -- it arrives normally,
	# exactly like the plain arrival test above.
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("rock"), 0, "raided goods never arrive")
	assert_eq(manager.market_store().market_for(shortage_id).stock_of("stick"), 2, "the unraided sibling still arrives")

	var shipped: Array = manager.event_store().events_of_type("regional_trade_shipped")
	assert_eq(shipped.size(), 1)
	assert_eq(shipped[0].tags, ["stick"])

	var raided: Array = manager.event_store().events_of_type("regional_trade_raided")
	assert_eq(raided.size(), 1)
	assert_eq(raided[0].actors, [supplier_id, shortage_id])
	assert_eq(raided[0].tags, ["rock"])

	assert_eq(dropped_stacks.size(), 1, "the caravan's carried rock scatters into the world exactly once")
	assert_eq(dropped_stacks[0].item.id, "rock")
	assert_eq(dropped_stacks[0].count, 3)


## Given two candidate suppliers, the CLOSER one (real Euclidean distance
## between real chunk coordinates) is chosen.
func test_step_regional_trade_prefers_the_nearest_surplus_settlement():
	var shortage_coord := Vector2i(10, 10)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])
	var shortage_id := EntityRef.for_settlement(shortage_coord)

	var near_coord := Vector2i(11, 10)  # distance 1
	manager.record_settlement_founded_if_new(near_coord, [NpcIdentity.new(1)])
	var near_id := EntityRef.for_settlement(near_coord)
	manager.market_store().market_for(near_id).add_stock("rock", 20)
	manager.market_store().market_for(near_id).add_stock("stick", 20)

	var far_coord := Vector2i(100, 10)  # distance 90
	manager.record_settlement_founded_if_new(far_coord, [NpcIdentity.new(2)])
	var far_id := EntityRef.for_settlement(far_coord)
	manager.market_store().market_for(far_id).add_stock("rock", 20)
	manager.market_store().market_for(far_id).add_stock("stick", 20)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)

	assert_eq(manager.market_store().market_for(near_id).stock_of("rock"), 17, "the near settlement supplied")
	assert_eq(manager.market_store().market_for(far_id).stock_of("rock"), 20, "the far settlement untouched")


## A settlement with SOME stock but not real surplus (below the safety
## margin) never trades its own reserve away.
func test_step_regional_trade_does_not_resupply_from_insufficient_surplus():
	var shortage_coord := Vector2i(0, 2)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])
	var shortage_id := EntityRef.for_settlement(shortage_coord)

	var barely_stocked_coord := Vector2i(1, 2)
	manager.record_settlement_founded_if_new(barely_stocked_coord, [NpcIdentity.new(1)])
	var barely_stocked_id := EntityRef.for_settlement(barely_stocked_coord)
	manager.market_store().market_for(barely_stocked_id).add_stock("rock", 3)  # exactly the need, no margin
	manager.market_store().market_for(barely_stocked_id).add_stock("stick", 2)

	manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)

	assert_eq(manager.market_store().market_for(shortage_id).stock_of("rock"), 0)
	assert_eq(manager.event_store().events_of_type("regional_trade_shipped").size(), 0)


func test_step_regional_trade_does_nothing_before_its_interval_elapses():
	var shortage_coord := Vector2i(0, 3)
	manager.record_settlement_founded_if_new(shortage_coord, [NpcIdentity.new(8)])
	var supplier_coord := Vector2i(1, 3)
	manager.record_settlement_founded_if_new(supplier_coord, [NpcIdentity.new(1)])
	var supplier_id := EntityRef.for_settlement(supplier_coord)
	manager.market_store().market_for(supplier_id).add_stock("rock", 20)
	manager.market_store().market_for(supplier_id).add_stock("stick", 20)

	manager.step_regional_trade(1.0)

	assert_eq(manager.event_store().events_of_type("regional_trade_shipped").size(), 0)


# -- a building piece occupies its tile against vegetation -------------------
#
# Reported: a village house stamped straight over a standing tree -- trunk
# rooted in the stone floor, canopy drawn over the masonry. Three directions,
# not one, because _load_chunk spawns trees BEFORE it spawns the village that
# stamps houses over them, and loads chunk.modifications from disk before
# BOTH: (A) the house arriving second must clear what is growing where it
# lands (stamp_structure_at_global, below), (B) the forest respawning next
# load must skip a cell a persisted piece holds (TreeRenderer.spawn_trees,
# covered in test_tree_renderer.gd), and (C) a spread seed must not take root
# on a floor (_can_root_at, below). Only REAL BuildingPieces occupy -- an
# earth path or a campfire is a chunk modification too.

const _OccupancyTreeRooting = preload("res://src/world/tree_rooting.gd")


func _tree_standing_at(tile: Vector2i) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = Vector2(
		(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	entities_parent.add_child(tree)
	manager._loaded_trees[_chunk_coord_for_tile(tile)].append(tree)
	return tree


func test_building_piece_occupancy_clears_trees_on_a_stamped_footprint():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(10, 10)
	var tree := _tree_standing_at(origin)

	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "stone_floor"}, {})

	assert_false(
		manager._loaded_trees[chunk_coord].has(tree),
		"a tree was left standing inside a freshly stamped floor"
	)
	assert_true(tree.is_queued_for_deletion())


## ...but only what the footprint actually covers. Clearing wider than the
## stamp would strip a house's whole clearing bare.
func test_building_piece_occupancy_leaves_a_tree_beside_the_footprint_standing():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(10, 10)
	var neighbour := _tree_standing_at(origin + Vector2i(3, 0))

	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "stone_floor"}, {})

	assert_true(
		manager._loaded_trees[chunk_coord].has(neighbour),
		"a tree three tiles from the footprint should still be standing"
	)
	assert_false(neighbour.is_queued_for_deletion())


## A persisted sapling under the footprint has to go from the RECORD too, or
## it simply comes back from disk on the next load (see Chunk.planted_trees).
func test_building_piece_occupancy_forgets_a_persisted_sapling_under_the_footprint():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var chunk = manager._loaded_chunks[chunk_coord]
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(12, 12)
	var under := Vector2(
		(origin.x + 0.5) * TerrainRenderer.TILE_SIZE, (origin.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	var beside := Vector2(
		(origin.x + 3.5) * TerrainRenderer.TILE_SIZE, (origin.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	chunk.planted_trees.append({"position": under, "planted_at": 0.0})
	chunk.planted_trees.append({"position": beside, "planted_at": 0.0})

	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "wood_floor"}, {})

	var kept_positions := []
	for record in chunk.planted_trees:
		kept_positions.append(record["position"])
	assert_false(kept_positions.has(under), "a persisted sapling survives under the house floor")
	assert_true(kept_positions.has(beside), "the sapling beside the house should be untouched")


## Nothing takes root on a floor afterwards either -- TreeRooting answers the
## BIOME question only, and occupancy is a separate refusal.
func test_building_piece_occupancy_refuses_a_sapling_rooting_on_a_piece():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var chunk = manager._loaded_chunks[chunk_coord]
	var rootable := Vector2i(-1, -1)
	for y in range(4, EarthChunkManager.CHUNK_SIZE - 4):
		for x in range(4, EarthChunkManager.CHUNK_SIZE - 4):
			if _OccupancyTreeRooting.can_root_in(chunk.biome[y * chunk.width + x]):
				rootable = chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(x, y)
				break
		if rootable != Vector2i(-1, -1):
			break
	if rootable == Vector2i(-1, -1):
		pass_test("no rootable cell in Berlin's own chunk this run")
		return
	var position := Vector2(
		(rootable.x + 0.5) * TerrainRenderer.TILE_SIZE,
		(rootable.y + 0.5) * TerrainRenderer.TILE_SIZE
	)

	manager.stamp_structure_at_global(chunk_coord, rootable, {Vector2i(0, 0): "wood_floor"}, {})
	var before: int = chunk.planted_trees.size()
	manager._plant_sapling_record(chunk, chunk_coord, position)

	assert_eq(
		chunk.planted_trees.size(), before,
		"a sapling took root on a building piece"
	)


## The same rule for STONE. _load_chunk spawns boulders and mountain ore veins
## (both land in _loaded_stones) before the village stamps its houses, so on a
## first visit a boulder standing where a wall goes is enclosed by it exactly
## the way a tree was. No persisted-record half here: stones carry no
## planted_trees equivalent -- they regenerate deterministically, and the
## respawn direction is closed in StoneRenderer.
func _stone_standing_at(tile: Vector2i) -> Node2D:
	var stone := Node2D.new()
	stone.position = Vector2(
		(tile.x + 0.5) * TerrainRenderer.TILE_SIZE, (tile.y + 0.5) * TerrainRenderer.TILE_SIZE
	)
	entities_parent.add_child(stone)
	manager._loaded_stones[_chunk_coord_for_tile(tile)].append(stone)
	return stone


func test_building_piece_occupancy_clears_stones_on_a_stamped_footprint():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(14, 14)
	var boulder := _stone_standing_at(origin)

	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "stone_floor"}, {})

	assert_false(
		manager._loaded_stones[chunk_coord].has(boulder),
		"a boulder was left standing inside a freshly stamped floor"
	)
	assert_true(boulder.is_queued_for_deletion())


## ...and, as with trees, only what the footprint actually covers.
func test_building_piece_occupancy_leaves_a_stone_beside_the_footprint_standing():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE + Vector2i(14, 14)
	var neighbour := _stone_standing_at(origin + Vector2i(3, 0))

	manager.stamp_structure_at_global(chunk_coord, origin, {Vector2i(0, 0): "stone_floor"}, {})

	assert_true(
		manager._loaded_stones[chunk_coord].has(neighbour),
		"a boulder three tiles from the footprint should still be standing"
	)
	assert_false(neighbour.is_queued_for_deletion())


# -- record_death_at, and what it is FOR ---------------------------------------
#
# The individual half of the simulation telling the aggregate half that an
# animal is gone -- record_birth_at's mirror (see
# EcosystemSimulation.record_death and concept/animal_husbandry.md's
# "Consequence"). The middle layer between CreatureMarker._die() and the
# aggregate, which is the piece with the pixel->chunk conversion in it.

func test_record_death_at_lowers_the_owning_regions_herbivore_population():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		_berlin_tile.x * TerrainRenderer.TILE_SIZE, _berlin_tile.y * TerrainRenderer.TILE_SIZE
	)
	var before := manager.herbivore_population_at_chunk(center_chunk)
	assert_gt(before, 0.0, "precondition: the chunk under Berlin carries some herbivores")

	manager.record_death_at(pixel, false)

	assert_almost_eq(
		manager.herbivore_population_at_chunk(center_chunk), maxf(0.0, before - 1.0), 0.001
	)


## The predator pool is separate and its own capacity is derived from the
## herbivore one, so a wolf booked against the wrong pool would both
## under-count wolves and shrink what the land is said to support.
func test_record_death_at_lowers_the_predator_population_for_a_predator():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		_berlin_tile.x * TerrainRenderer.TILE_SIZE, _berlin_tile.y * TerrainRenderer.TILE_SIZE
	)
	var herbivores_before := manager.herbivore_population_at_chunk(center_chunk)
	var predators_before: float = manager._ecosystem.predator_population(center_chunk)
	assert_gt(predators_before, 0.0, "precondition: the chunk under Berlin carries some predators")

	manager.record_death_at(pixel, true)

	assert_almost_eq(
		manager._ecosystem.predator_population(center_chunk),
		maxf(0.0, predators_before - 1.0),
		0.001
	)
	assert_almost_eq(
		manager.herbivore_population_at_chunk(center_chunk), herbivores_before, 0.001,
		"a predator's death must not come off the herbivore books"
	)


## THE point of the whole seam, and the behaviour that did not exist before it:
## a region hunted out has to STAY hunted out. Previously
## _reconcile_chunk_creatures sized a chunk's markers against an aggregate that
## never heard about the kill, so a valley emptied by the player simply
## refilled on the next ecosystem refresh.
##
## Modelled on this file's own fished-out test above: every loaded chunk is
## emptied, not just one, so there is no untouched neighbour left to migrate
## animals back in from -- migration restocking a single emptied chunk from a
## healthy neighbour is correct, intended behaviour and not what this asserts.
func test_a_hunted_out_region_stops_showing_creature_markers():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var any_animals := false
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		var herbivores := manager.herbivore_population_at_chunk(chunk_coord)
		if herbivores > 0.0:
			any_animals = true
		manager._ecosystem.record_death(chunk_coord, false, herbivores)
		manager._ecosystem.record_death(
			chunk_coord, manager._ecosystem.predator_population(chunk_coord), true
		)
	assert_true(any_animals, "precondition: some loaded chunk near Berlin carries herbivores")

	manager.step_ecosystem(EarthChunkManager.SECONDS_PER_SIMULATED_DAY)

	assert_eq(
		_loaded_creature_list().size(), 0,
		"an entirely hunted-out region should show no creature markers after the next refresh"
	)


# -- emergence: the player is a real member of the place they settle in -------
#
# Owning property and LIVING somewhere are two different facts, and only the
# first existed. _households_in_settlement derives membership purely from
# npc_settled, so a player holding a deed inside a village was invisible to
# every system that asks "who lives here" -- settlement tier, institution
# formation thresholds, the market's participant set (see
# concept/player_citizenship.md's "Residency").
#
# A new player_settled event TYPE rather than reusing npc_settled: the player
# is not an NPC, and a log that said otherwise would be a lie told to every
# later reader of the event graph -- /why included, which exists to explain
# that graph back to the player.

func test_recording_the_player_settling_makes_them_a_member_of_that_settlement():
	var chunk_coord := Vector2i(75, 75)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_eq(manager.household_count_for_settlement(settlement_id), 1)

	assert_true(manager.record_player_settled_if_new(settlement_id))

	assert_eq(manager.household_count_for_settlement(settlement_id), 2)


func test_the_player_settling_records_a_real_event():
	var chunk_coord := Vector2i(76, 76)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	manager.record_player_settled_if_new(settlement_id)

	var settled: Array = manager.event_store().events_of_type("player_settled")
	assert_eq(settled.size(), 1)
	assert_eq(settled[0].witnesses, [settlement_id])


## The event graph is the authority on what exists, the same way
## record_settlement_founded_if_new and record_path_worn_if_new already treat
## it. Claiming a deed out in empty wilderness makes you a landowner, not a
## citizen -- there is no one there to be a citizen among.
func test_the_player_cannot_settle_a_settlement_that_was_never_founded():
	var settlement_id := EntityRef.for_settlement(Vector2i(999, 999))

	assert_false(manager.record_player_settled_if_new(settlement_id))

	assert_eq(manager.event_store().events_of_type("player_settled").size(), 0)
	assert_eq(manager.household_count_for_settlement(settlement_id), 0)


## /deed re-run in the same chunk is ordinary play, not an exploit attempt --
## but it must not count the player twice, which would otherwise be a free way
## to push a hamlet over a tier threshold or an institution over its own
## formation minimum without another soul moving in.
func test_recording_the_player_settling_twice_does_not_count_them_twice():
	var chunk_coord := Vector2i(77, 77)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	assert_true(manager.record_player_settled_if_new(settlement_id))
	assert_false(manager.record_player_settled_if_new(settlement_id))

	assert_eq(manager.household_count_for_settlement(settlement_id), 2)
	assert_eq(manager.event_store().events_of_type("player_settled").size(), 1)


## The Deed is the player-facing verb; residency is what it MEANS when the
## land you claim is inside a place that already exists.
func test_claiming_a_deed_inside_a_real_settlement_settles_the_player_there():
	var chunk_coord := Vector2i(78, 78)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(1)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	manager.claim_property_with_deed("house:player_claim_78_78", settlement_id)

	assert_eq(manager.household_count_for_settlement(settlement_id), 2)
	assert_eq(manager.event_store().events_of_type("player_settled").size(), 1)


## Claiming land in the wilderness still works and still forms a household --
## it just does not make you a member of anything.
func test_claiming_a_deed_outside_any_settlement_still_grants_the_property():
	var household = manager.claim_property_with_deed("house:wilderness_0")
	assert_not_null(household)
	assert_true(household.property.has("house:wilderness_0"))
	assert_eq(manager.event_store().events_of_type("player_settled").size(), 0)


# -- the merchant you are standing at belongs to a real settlement ------------
#
# Shop pricing is per-settlement (see Shop.market_price_of and
# docs/emergence/03's "Do not use one global price"), so buying needs the
# market of the place the merchant actually stands in. Same loop
# has_merchant_near already runs, returning the market instead of a bool --
# _loaded_villages is keyed by chunk, and a chunk is what EntityRef.for_settlement
# names a settlement by, so the merchant's own key IS the answer.

func test_merchant_market_near_returns_the_markets_of_the_settlement_it_stands_in():
	manager.update(_berlin_tile)
	var merchant := _add_fake_merchant(Vector2(100, 100))
	var expected := manager.market_store().market_for(EntityRef.for_settlement(Vector2i(0, 0)))

	var market = manager.merchant_market_near(Vector2(105, 100), 10.0)

	assert_not_null(market)
	assert_true(market == expected, "should be the settlement's own market, not a new one")
	merchant.free()


## A merchant's market is stocked with what a merchant sells, so a village the
## player has never traded at charges the plain catalog price rather than the
## 20x an empty market would price at (see Shop.stock_initial_goods).
func test_a_merchants_market_is_stocked_with_the_goods_they_sell():
	manager.update(_berlin_tile)
	var merchant := _add_fake_merchant(Vector2(100, 100))

	var market = manager.merchant_market_near(Vector2(105, 100), 10.0)

	var shop := Shop.new()
	for item_id in shop.known_item_ids():
		assert_eq(
			shop.market_price_of(item_id, market), shop.price_of(item_id),
			"an untraded village should charge the plain catalog price for %s" % item_id
		)
	merchant.free()


func test_merchant_market_near_is_null_with_no_merchant_in_range():
	manager.update(_berlin_tile)
	var merchant := _add_fake_merchant(Vector2(100, 100))
	assert_null(manager.merchant_market_near(Vector2(500, 500), 10.0))
	merchant.free()


func test_merchant_market_near_is_null_with_no_settlement_loaded():
	assert_null(manager.merchant_market_near(Vector2(100, 100), 10000.0))

# -- emergence: villagers actually WITNESS what happens to their settlement --

## A minimal stand-in for the one thing SettlementFood.village_market_for
## duck-types out of `_loaded_villages` (`node.economy.market`, the single
## VillageMarket every NpcMarker of a settlement shares -- see
## NpcMarker.setup_economy). Built here rather than spawning a real village
## because a real one needs a loaded chunk, and a loaded chunk needs
## manager.update(), the single slowest call in this suite.
class _FakeVillagerEconomy:
	extends RefCounted
	var market


class _FakeVillager:
	extends Node2D
	var economy


## Every emitter in this file records what happened; until now only
## settlement_founded/npc_settled recorded WHO WAS THERE, so a villager's
## memory bank held founding trivia and nothing else. A settlement's own
## status change is the most basic thing its villagers would all know.
func test_a_settlement_status_change_is_witnessed_by_every_one_of_its_villagers():
	var chunk_coord := Vector2i(131, 131)
	# Two founders who gather nothing, so the settlement really is short of
	# food rather than merely sitting on a ledger nothing could ever stock
	# (see _step_settlement_granary).
	var seeds := _non_producer_seeds(2)
	var founders: Array = []
	for a_seed in seeds:
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var declines: Array = manager.event_store().events_of_type("settlement_declining")
	assert_eq(declines.size(), 1)
	assert_true(declines[0].witnesses.has(EntityRef.for_npc(seeds[0])))
	assert_true(declines[0].witnesses.has(EntityRef.for_npc(seeds[1])))

	# ...and it really is in their heads, not merely named on the event.
	var remembered: Array = []
	for memory in manager.memory_store().memories_for(EntityRef.for_npc(seeds[1])):
		remembered.append(memory.remembered_type)
	assert_true(
		remembered.has("settlement_declining"),
		"a villager should remember their own settlement declining"
	)


## Production is the settlement's daily work -- the villagers are the ones
## doing it, so they are the ones who know how it went.
func test_a_production_outcome_is_witnessed_by_the_settlements_villagers():
	var chunk_coord := Vector2i(133, 133)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 1)

	manager.attempt_production(settlement_id, "cooked_meat")

	var successes: Array = manager.event_store().events_of_type("production_succeeded")
	assert_eq(successes.size(), 1)
	assert_eq(successes[0].witnesses, [EntityRef.for_npc(11)])


## _step_settlement_production attempts every household's recipe every
## SETTLEMENT_STEP_INTERVAL, so an unstocked settlement was appending an
## identical production_failed record forever -- within ten minutes every
## villager's entire news is "production failed". Event-source a real
## CHANGE only, exactly as _settlement_status already does.
func test_a_repeated_production_failure_is_not_witnessed_twice():
	var chunk_coord := Vector2i(135, 135)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("production_failed").size(), 1)


## ...and the guard must not silence the settlement permanently: a run that
## succeeded and then broke down again is genuine news the second time too.
## Seed 5 is a real hunter (cooked_meat, one "meat" per attempt).
func test_a_production_failure_is_witnessed_again_after_a_real_success():
	var chunk_coord := Vector2i(137, 137)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	# One meat for the recipe, plus this household's own dinner: the granary
	# is eaten before production runs against it (see
	# _step_settlement_granary), so stocking exactly the recipe's input
	# stocks a meal instead.
	manager.market_store().market_for(settlement_id).add_stock(
		"meat", 1 + SettlementGranary.subsistence_draw(1)
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # the one meat
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # nothing left
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # still nothing

	assert_eq(manager.event_store().events_of_type("production_succeeded").size(), 1)
	assert_eq(manager.event_store().events_of_type("production_failed").size(), 1)


func test_a_settlement_tier_change_is_witnessed_by_its_villagers():
	var settlement_tier := preload("res://src/emergence/settlement_tier.gd")
	var chunk_coord := Vector2i(139, 139)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var became: Array = manager.event_store().events_of_type(
		"settlement_became_%s" % settlement_tier.HAMLET
	)
	assert_eq(became.size(), 1)
	assert_eq(became[0].witnesses, [EntityRef.for_npc(11)])


## An institution's parties are HOUSEHOLDS, not settlements -- so the
## witnesses have to be resolved back through the household's founder to
## the settlement they settled at.
func test_an_institution_forming_is_witnessed_by_its_parties_villagers():
	var chunk_coord := Vector2i(141, 141)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(1), NpcIdentity.new(2)]
	)
	var household_a: String = manager.household_store().household_for(EntityRef.for_npc(1)).id
	var household_b: String = manager.household_store().household_for(EntityRef.for_npc(2)).id
	_fulfill_contracts_between(household_a, household_b, InstitutionFormation.FORMATION_THRESHOLD)

	manager.attempt_institution_formation("guild", household_a, household_b)

	var formed: Array = manager.event_store().events_of_type("institution_formed")
	assert_eq(formed.size(), 1)
	assert_true(formed[0].witnesses.has(EntityRef.for_npc(1)))
	assert_true(formed[0].witnesses.has(EntityRef.for_npc(2)))


## A ruin has no villagers of its own -- but whoever watched the settlement
## decline (or the institution collapse) that CAUSED it is exactly who
## watched the ruin appear, and _record_ruin_from already holds that cause.
func test_a_ruin_is_witnessed_by_whoever_witnessed_the_event_that_caused_it():
	var cause := Event.new("settlement_declining", 1.0)
	cause.actors.append("settlement:143_143")
	cause.witnesses.append(EntityRef.for_npc(11))
	var cause_id := manager.event_store().append(cause)

	manager.record_ruin_from_settlement_decline("settlement:143_143", cause_id)

	var ruins: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(ruins.size(), 1)
	assert_eq(ruins[0].witnesses, [EntityRef.for_npc(11)])


## The settlement status step read only the persisted emergence Market,
## which live play essentially never stocks -- so every settlement was
## classified DECLINING forever while its villagers' own VillageMarket sat
## full of real gathered food. 8 whole meals over SettlementState.
## FOOD_PER_HOUSEHOLD (4) is capacity 2 for one household: real headroom.
func test_a_settlement_with_live_village_market_food_is_witnessed_growing():
	var village_market_script := preload("res://src/world/village_market.gd")
	var chunk_coord := Vector2i(145, 145)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])

	var village_market = village_market_script.new()
	village_market.add_stock("meat", 8.0)
	var economy := _FakeVillagerEconomy.new()
	economy.market = village_market
	var villager := _FakeVillager.new()
	villager.economy = economy
	manager._loaded_villages[chunk_coord] = [villager]

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("settlement_growing").size(), 1)
	assert_eq(manager.event_store().events_of_type("settlement_declining").size(), 0)

	manager._loaded_villages.erase(chunk_coord)
	villager.free()


## Contracts are the highest-volume real settlement activity in this file --
## _step_settlement_trade runs the whole propose/accept/activate/fulfil
## chain for the same two households every single step -- and they were the
## last emitter still recording nobody as having been there. Their actors
## are HOUSEHOLDS, which _villager_witnesses_of already resolves back
## through _settlement_of_party, so the villagers whose settlement that
## trade IS are the ones who remember how it went.
func test_a_fulfilled_contract_is_witnessed_by_the_settlements_villagers():
	var chunk_coord := Vector2i(147, 147)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)  # -> fulfils

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var fulfilled: Array = manager.event_store().events_of_type("contract_fulfilled")
	assert_eq(fulfilled.size(), 1)
	assert_true(fulfilled[0].witnesses.has(EntityRef.for_npc(10)))
	assert_true(fulfilled[0].witnesses.has(EntityRef.for_npc(11)))

	# ...and it really is in their heads, not merely named on the event.
	var remembered: Array = []
	for memory in manager.memory_store().memories_for(EntityRef.for_npc(11)):
		remembered.append(memory.remembered_type)
	assert_true(
		remembered.has("contract_fulfilled"),
		"a villager should remember their own settlement's trade being made good"
	)


## The same guard the status path needed, for the same reason: the SAME two
## households trade every step forever, so an unguarded fan-out would hand
## every villager a fresh MemoryRecord of an identical outcome once per
## step. The outcome is what a villager carries, and a repeat of it is not
## news -- exactly _settlement_production_outcome's rule, keyed on the pair
## instead of on settlement|recipe. The EVENTS are untouched: each contract
## really is its own contract, and the event ledger stays the full record.
func test_a_repeated_identical_contract_outcome_is_not_re_witnessed():
	var chunk_coord := Vector2i(149, 149)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var fulfilled: Array = manager.event_store().events_of_type("contract_fulfilled")
	assert_eq(fulfilled.size(), 2, "both trades really happened and are both on record")
	assert_true(fulfilled[1].witnesses.is_empty(), "the second identical outcome is not news")

	var remembered := 0
	for memory in manager.memory_store().memories_for(EntityRef.for_npc(11)):
		if memory.remembered_type == "contract_fulfilled":
			remembered += 1
	assert_eq(remembered, 1)


## Only how a trade ENDED is fanned to the villagers. propose/accept/active
## all fire in the same step as the outcome (see _step_settlement_trade: the
## whole lifecycle runs within one step), so witnessing them too would hand
## every villager four memories of one trade.
func test_contract_bookkeeping_steps_are_not_witnessed_by_villagers():
	var chunk_coord := Vector2i(151, 151)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	for event_type in ["contract_proposed", "contract_accepted", "contract_active"]:
		var events: Array = manager.event_store().events_of_type(event_type)
		assert_eq(events.size(), 1, "%s still happened and is still on record" % event_type)
		assert_true(events[0].witnesses.is_empty(), "%s is bookkeeping, not news" % event_type)


## Why.explain_settlement now reads food/capacity off SettlementFood, which
## needs the LIVE VillageMarket step_settlements classifies with -- and
## _loaded_villages is private. Public wrapper, the same "for a console
## command to report without reaching into private reconstruction"
## convention household_count_for_settlement already set. Null for a
## settlement whose chunk is not loaded: the normal case for most of the
## world, not a failure.
func test_village_market_for_settlement_reaches_the_live_market():
	var village_market_script := preload("res://src/world/village_market.gd")
	var chunk_coord := Vector2i(153, 153)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	assert_null(manager.village_market_for_settlement(settlement_id))

	var village_market = village_market_script.new()
	var economy := _FakeVillagerEconomy.new()
	economy.market = village_market
	var villager := _FakeVillager.new()
	villager.economy = economy
	manager._loaded_villages[chunk_coord] = [villager]

	assert_eq(manager.village_market_for_settlement(settlement_id), village_market)
	assert_null(manager.village_market_for_settlement("settlement:999_999"))

	manager._loaded_villages.erase(chunk_coord)
	villager.free()


# -- emergence: a session's status guards have to survive a RELOAD ----------
#
# _settlement_status/_contract_outcome_witnessed are in-memory session state,
# but every store they guard writes into (_event_store, _memory_store) is
# persisted. A guard that forgets on load is not merely weaker across loads,
# it is WORSE than none: it re-fires once per settlement per load, straight
# into a persisted store that only ever grows.


## Persists every store step_settlements reads and loads them back into a
## FRESH manager, whose in-memory session state starts empty exactly as it
## does when World builds a new EarthChunkManager over an existing save.
## Cleans up its own files.
##
## These six are exactly the six World._load_saved_game loads (see
## scenes/world.gd) minus the world boss store, which no settlement path
## reads. It said "the real reload path" while loading FIVE of them: the
## institution store was missing, so attempt_institution_formation's dedupe
## -- which asks _institution_store, not the event history -- read an empty
## store and re-founded an institution that already existed. A harness that
## reloads less than the game does cannot see the bug the game has, and the
## sentence claiming otherwise is what kept it invisible.
##
## The world CLOCK is restored too, even though it is a scalar rather than a
## store. It used to be left at zero, on the reasoning that it "only shifts
## the TIMESTAMPS on events recorded after the reload, which none of the
## change-guards below key on" -- that stopped being true the moment routine
## trade got its own guard, which reads InstitutionFormation's
## RECENT_WINDOW_SECONDS against the live clock (see
## _routine_trade_is_worth_running). A harness resuming at age 0 makes every
## contract ever signed look like it was signed moments ago, so a test built
## on it would pass on an artifact of the harness rather than on the guard.
##
## Still deliberately NOT restored, and named rather than implied: the world
## boss store, which nothing in step_settlements touches.
func _reloaded_manager(tag: String) -> EarthChunkManager:
	var paths: Array[String] = []
	for store in ["events", "memories", "households", "markets", "contracts", "institutions"]:
		paths.append("user://test_ecm_reload_%s_%s.bin" % [tag, store])
	manager.save_event_store(paths[0])
	manager.save_memory_store(paths[1])
	manager.save_household_store(paths[2])
	manager.save_market_store(paths[3])
	manager.save_contract_store(paths[4])
	manager.save_institution_store(paths[5])

	var reloaded := EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	reloaded.load_event_store(paths[0])
	reloaded.load_memory_store(paths[1])
	reloaded.load_household_store(paths[2])
	reloaded.load_market_store(paths[3])
	reloaded.load_contract_store(paths[4])
	reloaded.load_institution_store(paths[5])
	reloaded.set_world_age_seconds(manager.world_age_seconds())

	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	return reloaded


func _remembered_count(a_manager: EarthChunkManager, npc_id: String, event_type: String) -> int:
	var count := 0
	for memory in a_manager.memory_store().memories_for(npc_id):
		if memory.remembered_type == event_type:
			count += 1
	return count


## The dwell deliberately exempts a settlement's FIRST assessment -- and on
## a fresh load EVERY settlement ever founded is a first assessment, because
## the dwell's own bookkeeping is in memory while the settlement's recorded
## status is on disk. So every load re-fired one settlement_<status> event
## and one MemoryRecord per villager for a settlement nothing had happened
## to: unbounded growth in a persisted store, the exact failure the dwell
## exists to prevent, escaping through the one door it did not cover. The
## last status actually event-sourced is right there in the persisted event
## history -- read it back, the same way record_path_worn_if_new and
## _record_ruin_from already dedupe against real history rather than a flag.
func test_step_settlements_does_not_re_fire_a_status_unchanged_since_the_last_load():
	var chunk_coord := Vector2i(157, 157)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)  # no food -> declining
	assert_eq(
		manager.event_store().events_of_type("settlement_declining").size(),
		1,
		"precondition: the first real assessment is news"
	)

	var reloaded := _reloaded_manager("status")
	var remembered_before := _remembered_count(
		reloaded, EntityRef.for_npc(11), "settlement_declining"
	)
	assert_eq(remembered_before, 1, "precondition: the memory persisted too")

	reloaded.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		reloaded.event_store().events_of_type("settlement_declining").size(),
		1,
		"a status that has not changed since the last session is not news again"
	)
	assert_eq(
		_remembered_count(reloaded, EntityRef.for_npc(11), "settlement_declining"),
		remembered_before,
		"and no villager re-learns what they already knew"
	)


## The same hole, one store over: _contract_outcome_witnessed is keyed on
## the party pair and never persisted, so the same two households fulfilling
## the same contract re-fanned a MemoryRecord to every villager once per
## load. Smaller blast radius than the status path, identical root cause and
## identical fix -- read the pair's last recorded outcome back out of the
## persisted event history.
func test_a_contract_outcome_unchanged_since_the_last_load_is_not_re_witnessed():
	var chunk_coord := Vector2i(159, 159)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("contract_fulfilled").size(),
		1,
		"precondition: one real trade, witnessed once"
	)

	var reloaded := _reloaded_manager("contract")
	var remembered_before := _remembered_count(
		reloaded, EntityRef.for_npc(11), "contract_fulfilled"
	)
	assert_eq(remembered_before, 1, "precondition: the memory persisted too")

	reloaded.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var fulfilled: Array = reloaded.event_store().events_of_type("contract_fulfilled")
	assert_eq(fulfilled.size(), 2, "the second trade really happened and is still on record")
	assert_true(
		fulfilled[1].witnesses.is_empty(),
		"an outcome identical to the one on record is not news again after a load"
	)
	assert_eq(
		_remembered_count(reloaded, EntityRef.for_npc(11), "contract_fulfilled"),
		remembered_before
	)


## A settlement whose chunk is not loaded has no live VillageMarket in
## memory at all (SettlementFood.village_market_for returns null), so its
## combined food reads 0 and status_for calls it DECLINING. That is the
## market being out of memory, not the settlement starving -- and it is the
## normal state of almost the whole world, immediately after a load most of
## all. Once a settlement HAS a status on record, a zero-capacity reading
## taken with no live market and no persisted stock behind it is an absence
## of evidence, not evidence of famine: the last real reading stands until
## something can actually be read again.
func test_a_settlement_is_not_declared_declining_purely_because_its_chunk_unloaded():
	var village_market_script := preload("res://src/world/village_market.gd")
	var chunk_coord := Vector2i(161, 161)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])

	var village_market = village_market_script.new()
	village_market.add_stock("meat", 8.0)  # capacity 2 for one household -> growing
	var economy := _FakeVillagerEconomy.new()
	economy.market = village_market
	var villager := _FakeVillager.new()
	villager.economy = economy
	manager._loaded_villages[chunk_coord] = [villager]

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("settlement_growing").size(),
		1,
		"precondition: really growing, read off a real live market"
	)

	# The player walks away: the chunk unloads and the food goes with it.
	manager._loaded_villages.erase(chunk_coord)
	for step in EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS + 2:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		manager.event_store().events_of_type("settlement_declining").size(),
		0,
		"a market that is merely out of memory is not a famine"
	)
	assert_eq(
		manager.event_store().events_of_type("ruin_formed").size(),
		0,
		"and no ruin is built on a reading nobody actually took"
	)

	villager.free()


## ...and the guard is exactly that narrow. A LOADED settlement whose live
## market is really empty is a real famine read off a real market, and it
## still declines -- which is also the only place the delayed decline path
## is exercised at all: record_ruin_from_settlement_decline hangs off the
## DECLINING transition, and every other ruin test declines on a FIRST
## assessment, which is deliberately immediate. A decline that follows an
## already-recorded status has to hold for SETTLEMENT_STATUS_DWELL_STEPS
## assessments first, and nothing proved the ruin still forms at the far
## end of that wait.
func test_a_decline_that_has_to_dwell_first_still_forms_a_ruin():
	var village_market_script := preload("res://src/world/village_market.gd")
	var chunk_coord := Vector2i(163, 163)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(11)])

	var village_market = village_market_script.new()
	village_market.add_stock("meat", 8.0)  # capacity 2 for one household -> growing
	var economy := _FakeVillagerEconomy.new()
	economy.market = village_market
	var villager := _FakeVillager.new()
	villager.economy = economy
	manager._loaded_villages[chunk_coord] = [villager]

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("settlement_growing").size(),
		1,
		"precondition: an established status to decline away FROM"
	)

	village_market.remove_stock("meat", 8.0)  # the food is really gone, and we can see it
	for step in EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS - 1:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("ruin_formed").size(),
		0,
		"the decline has not held long enough to be real yet"
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var declines: Array = manager.event_store().events_of_type("settlement_declining")
	assert_eq(declines.size(), 1)
	var formed: Array = manager.event_store().events_of_type("ruin_formed")
	assert_eq(formed.size(), 1, "a decline that dwelled still leaves a real ruin")
	assert_eq(formed[0].actors, ["ruin:settlement_%d_%d" % [chunk_coord.x, chunk_coord.y]])
	assert_eq(manager.event_store().causes_of(formed[0].id)[0].id, declines[0].id)

	manager._loaded_villages.erase(chunk_coord)
	villager.free()


## The same hole, three doors further along. _settlement_status and
## _contract_outcome_witnessed were seeded from persisted history; the other
## three change-guards in this file were not, so a settlement nothing had
## happened to still paid a fresh event AND a fresh MemoryRecord per
## villager on every single load. Measured on a real reload of an unchanged
## one-household settlement: +2 events, +2 memories per villager, once per
## load, forever, into stores that only ever grow.
##
## What this proves, stated at the size it actually is. A settlement with
## nothing new to report -- unchanged tier, specialization, production
## outcome, status AND contract outcome -- adds nothing at all across a
## load: no event, no MemoryRecord, no contract.
##
## The previous version of this comment called that "the strongest possible
## statement of the fix, so no fourth door goes unnoticed" while quietly
## using a ONE-household settlement, which is the single configuration with
## no trade partner and therefore the only one the sentence was true of. A
## settlement with two or more households appended four contract events and
## signed one fresh contract every assessment, load or no load, and the
## sentence walked straight past it. It is a MULTI-household settlement now,
## and the claim is a claim about the guards rather than about a fixture.
##
## AND HERE IS WHAT IT STILL DOES NOT COVER, because these are real activity
## and not re-announcements: a settlement that is genuinely PRODUCING
## appends a production_succeeded every assessment (successes are
## deliberately unguarded -- _production_counts_for_settlement counts them
## one by one), and a pair with a LIVING institution keeps signing contracts
## at InstitutionFormation's own dissolution-window rate, because an
## institution nobody has coordinated with recently is meant to be at risk.
## Neither is a settlement repeating itself; both are pinned by their own
## tests (test_a_settlement_specialization_unchanged_since_a_load_is_not_re_
## recorded, test_a_living_institution_is_kept_alive_at_the_dissolution_
## windows_own_rate). This fixture's founders gather nothing, so it has
## neither -- which is exactly what "unchanged" has to mean.
func test_step_settlements_adds_nothing_at_all_for_a_settlement_unchanged_since_a_load():
	var chunk_coord := Vector2i(165, 165)
	var seeds := _non_producer_seeds(3)
	var founders: Array = []
	for a_seed in seeds:
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)
	for step in 3:
		manager.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("settlement_became_hamlet").size(),
		1,
		"precondition: the tier really was assessed and recorded once"
	)
	assert_gt(
		manager.event_store().events_of_type("production_failed").size(),
		0,
		"precondition: the shortage really was recorded"
	)
	assert_eq(
		manager.event_store().events_of_type("contract_breached").size(),
		1,
		"precondition: this settlement really does have a trade partner, and traded once"
	)

	var reloaded := _reloaded_manager("unchanged")
	var events_before: int = reloaded.event_store().size()
	var contracts_before: int = reloaded.contract_store().to_dicts().size()
	var memories_before: int = (
		reloaded.memory_store().memories_for(EntityRef.for_npc(seeds[0])).size()
	)

	reloaded.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	reloaded.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		reloaded.event_store().size(),
		events_before,
		"nothing changed about this settlement, so nothing is news after a load"
	)
	assert_eq(
		reloaded.contract_store().to_dicts().size(),
		contracts_before,
		"and it signs no fresh contract to say it with either"
	)
	assert_eq(
		reloaded.memory_store().memories_for(EntityRef.for_npc(seeds[0])).size(),
		memories_before,
		"and no villager re-learns, once per load forever, what they already knew"
	)


## The specialization door on its own, because it is the one the blanket
## test above cannot reach: a specialization needs real production
## SUCCESSES, and successes are deliberately never guarded (each one is real
## goods really made, and _production_counts_for_settlement counts them one
## by one). So the settlement genuinely does append production_succeeded
## again after a load -- what it must not do is re-announce that it still
## specializes in exactly what it already specialized in.
func test_a_settlement_specialization_unchanged_since_a_load_is_not_re_recorded():
	var chunk_coord := Vector2i(167, 167)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(5)])
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var specialized: Array = manager.event_store().events_of_type("settlement_specialized")
	assert_eq(specialized.size(), 1, "precondition: a real hunting center, recorded once")
	assert_eq(specialized[0].tags, ["hunting center"])

	var reloaded := _reloaded_manager("specialization")
	var remembered_before := _remembered_count(
		reloaded, EntityRef.for_npc(5), "settlement_specialized"
	)

	reloaded.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		reloaded.event_store().events_of_type("production_succeeded").size(),
		2,
		"the second batch really was made and is still recorded, guard or no guard"
	)
	assert_eq(
		reloaded.event_store().events_of_type("settlement_specialized").size(),
		1,
		"but what it specializes in has not changed, so it is not news again"
	)
	assert_eq(
		_remembered_count(reloaded, EntityRef.for_npc(5), "settlement_specialized"),
		remembered_before
	)


## The harness itself was lying. _reloaded_manager called itself "the real
## reload path" while loading five of World's six stores -- the institution
## store was missing, so attempt_institution_formation's own dedupe (which
## reads _institution_store, not history) came back to an EMPTY store and
## re-formed an institution that already existed: institution_formed 1 -> 2,
## one more memory per villager per load. A test that reloads less than the
## game does cannot see the bug the game has.
func test_an_institution_already_formed_is_not_re_formed_after_a_load():
	var chunk_coord := Vector2i(169, 169)
	manager.record_settlement_founded_if_new(
		chunk_coord, [NpcIdentity.new(5), NpcIdentity.new(10), NpcIdentity.new(11)]
	)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)

	for i in InstitutionFormation.FORMATION_THRESHOLD + 1:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("institution_formed").size(),
		1,
		"precondition: one real institution, formed off real accumulated trade"
	)

	var reloaded := _reloaded_manager("institution")
	assert_eq(
		reloaded.active_institution_count_for_settlement(settlement_id),
		1,
		"the institution survived the reload, exactly as it does in a real load"
	)
	var remembered_before := _remembered_count(
		reloaded, EntityRef.for_npc(11), "institution_formed"
	)

	reloaded.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		reloaded.event_store().events_of_type("institution_formed").size(),
		1,
		"an institution that already exists is not founded a second time"
	)
	assert_eq(
		_remembered_count(reloaded, EntityRef.for_npc(11), "institution_formed"),
		remembered_before
	)
	assert_eq(
		reloaded.event_store().events_of_type("settlement_became_town").size(),
		1,
		"and its tier, which that institution is half the reason for, is unchanged too"
	)



# -- the emergence market's missing source (docs/concept/dialogue.md's own
# "Substrate first" table: "capacity read the persisted emergence Market,
# which is never stocked") --

## Eight founder seeds covering all eight of NpcIdentity.OCCUPATIONS, found
## by search rather than hardcoded: NpcIdentity._index picks an occupation by
## a modulo of a hash, so which seed is a hunter is an implementation detail
## that has already been reshuffled once (see NpcIdentity's own doc comment).
func _seeds_covering_every_occupation() -> Array:
	var by_occupation := {}
	var seed_value := 1
	while by_occupation.size() < NpcIdentity.OCCUPATIONS.size() and seed_value < 10000:
		var occupation := NpcIdentity.new(seed_value).occupation
		if not by_occupation.has(occupation):
			by_occupation[occupation] = seed_value
		seed_value += 1
	var seeds: Array = []
	for occupation in NpcIdentity.OCCUPATIONS:
		seeds.append(by_occupation[occupation])
	return seeds


func _founders_covering_every_occupation() -> Array:
	var founders: Array = []
	for a_seed in _seeds_covering_every_occupation():
		founders.append(NpcIdentity.new(a_seed))
	return founders


## The chunk a settlement founded on real inland land sits in -- the same
## Berlin tile every other live-world test in this file uses, so the region's
## vegetation/herbivore/fish numbers are real land numbers rather than
## whatever an arbitrary index happens to land on (open ocean, typically).
func _berlin_chunk() -> Vector2i:
	return Vector2i(
		floori(float(_berlin_tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(_berlin_tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func _run_settlement_probe(a_manager: EarthChunkManager, steps: int) -> void:
	for step in steps:
		a_manager.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		a_manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		a_manager.step_regional_trade(EarthChunkManager.REGIONAL_TRADE_INTERVAL)
		a_manager.step_caravans()


func test_probe_eight_household_settlement():
	var chunk_coord := _berlin_chunk()
	manager.record_settlement_founded_if_new(chunk_coord, _founders_covering_every_occupation())
	var settlement_id := EntityRef.for_settlement(chunk_coord)

	_run_settlement_probe(manager, 40)

	var market := manager.market_store().market_for(settlement_id)
	gut.p("PROBE stock = %s" % [market.stock])
	gut.p("PROBE production_succeeded = %d" % manager.event_store().events_of_type("production_succeeded").size())
	gut.p("PROBE production_failed = %d" % manager.event_store().events_of_type("production_failed").size())
	gut.p("PROBE capacity = %d" % SettlementState.carrying_capacity(market))
	gut.p("PROBE event_store size = %d" % manager.event_store().size())
	gut.p("PROBE contract events = %d, contracts signed = %d" % [
		manager.event_store().events_of_type("contract_proposed").size()
			+ manager.event_store().events_of_type("contract_accepted").size()
			+ manager.event_store().events_of_type("contract_active").size()
			+ manager.event_store().events_of_type("contract_fulfilled").size()
			+ manager.event_store().events_of_type("contract_breached").size(),
		manager.contract_store().to_dicts().size(),
	])
	gut.p("PROBE specialization = %s" % [manager.event_store().events_of_type("settlement_specialized").size()])

	assert_false(market.stock.is_empty(), "the emergence market has a real source")
	assert_gt(SettlementState.carrying_capacity(market), 0, "capacity is a real number")


## Probe B: the two consequences a single settlement cannot show on its own
## -- a caravan needs somewhere to go AND a supplier with real surplus to
## leave from, and RegionalTrade.has_surplus could never once be true
## anywhere in the world.
##
## Both settlements sit on the same real inland land, so neither is
## advantaged by terrain. What separates them is APPETITE: settlement B is
## deliberately built past its own break-even -- one hunter feeding a census
## sized, from the region's own real herbivore count, so that subsistence
## eats the whole catch (see SettlementGranary's break-even test for the
## same arithmetic). Its cooked_meat attempt is then a real shortage of meat
## standing next to a real surplus of meat one chunk away, which is exactly
## the edge RegionalTrade was written for.
func test_probe_a_caravan_departs_between_a_real_surplus_and_a_real_shortage():
	var rich_chunk := _berlin_chunk()
	var hungry_chunk := rich_chunk + Vector2i(1, 0)
	manager.record_settlement_founded_if_new(rich_chunk, _founders_covering_every_occupation())

	var hunter_seed: int = _seeds_covering_every_occupation()[NpcIdentity.OCCUPATIONS.find("hunter")]
	var region = manager._seeded_region_for(EntityRef.for_settlement(hungry_chunk))
	var catch: float = float(
		SettlementGranary.gathered_over(["hunter"], region, EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
			.get("meat", 0.0)
	)
	assert_gt(catch, 0.0, "precondition: there really is game here for the hunter to out-eat")
	var mouths := int(ceil(catch / float(SettlementState.FOOD_PER_HOUSEHOLD))) + 1
	var founders: Array = [NpcIdentity.new(hunter_seed)]
	for a_seed in _non_producer_seeds(mouths - 1):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(hungry_chunk, founders)

	_run_settlement_probe(manager, 40)

	var rich_stock: Dictionary = manager.market_store().market_for(EntityRef.for_settlement(rich_chunk)).stock
	var hungry_stock: Dictionary = manager.market_store().market_for(EntityRef.for_settlement(hungry_chunk)).stock
	var departed: Array = manager.event_store().events_of_type("regional_trade_departed")
	gut.p("PROBE B hungry census = %d households around one hunter catching %.2f/step" % [mouths, catch])
	gut.p("PROBE B caravans departed = %d" % departed.size())
	gut.p("PROBE B caravans shipped = %d" % manager.event_store().events_of_type("regional_trade_shipped").size())
	gut.p("PROBE B caravans raided = %d" % manager.event_store().events_of_type("regional_trade_raided").size())
	gut.p("PROBE B supplier stock = %s" % [rich_stock])
	gut.p("PROBE B shortage stock = %s" % [hungry_stock])
	for event in manager.event_store().events_of_type("settlement_specialized"):
		gut.p("PROBE B specialized: %s -> %s" % [event.actors, event.tags])

	assert_gt(departed.size(), 0, "a caravan can finally leave, because a supplier finally has surplus")
	assert_gt(
		manager.event_store().events_of_type("settlement_specialized").size(), 0,
		"and a settlement can finally specialize, because production can finally succeed"
	)
# -- routine trade is not news the four-thousandth time --


## MEASURED, not asserted: before this guard a settlement with more than one
## household appended contract_proposed + contract_accepted +
## contract_active + contract_fulfilled-or-breached EVERY assessment,
## forever, and signed one fresh Contract to go with them -- +4.0 events and
## +1.0 contract per step, into two stores that are persisted and only ever
## grow. The MEMORY side was already guarded (see _record_contract_event) so
## villagers do not re-learn what they know; the stores themselves were not.
##
## The same pair, the same terms, the same outcome, every thirty seconds, is
## exactly the shape _settlement_production_outcome and the status dwell
## already refuse to record.
func test_routine_trade_between_the_same_pair_stops_appending_once_nothing_changes():
	var chunk_coord := _berlin_chunk() + Vector2i(0, 3)
	var founders: Array = []
	for a_seed in _non_producer_seeds(3):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)

	manager.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("contract_breached").size(),
		1,
		"precondition: a settlement with nothing to eat really does breach, once"
	)

	var events_before: int = manager.event_store().size()
	var contracts_before: int = manager.contract_store().to_dicts().size()
	for step in 10:
		manager.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	gut.p("TRADE events per step = %.2f" % ((manager.event_store().size() - events_before) / 10.0))
	gut.p("TRADE contracts per step = %.2f" % ((manager.contract_store().to_dicts().size() - contracts_before) / 10.0))

	assert_eq(
		manager.event_store().size(),
		events_before,
		"nothing about this settlement changed, so it says nothing at all"
	)
	assert_eq(
		manager.contract_store().to_dicts().size(),
		contracts_before,
		"and signs no fresh contracts to say it with"
	)


## The guard is a change guard, not a mute button: a settlement whose
## fortunes really turn trades again, and that turn is recorded.
func test_a_pair_whose_outcome_really_changes_trades_again_and_says_so():
	var chunk_coord := _berlin_chunk() + Vector2i(0, 4)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var founders: Array = []
	for a_seed in _non_producer_seeds(2):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	var breaches_before: int = manager.event_store().events_of_type("contract_breached").size()
	assert_eq(breaches_before, 1, "precondition: hard times, on record")

	# Real food in the real ledger: the settlement can make good again.
	manager.market_store().market_for(settlement_id).add_stock("meat", 200)
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		manager.event_store().events_of_type("contract_fulfilled").size(),
		1,
		"a pair that can deliver again really does, and it is news"
	)


## The one thing routine trade genuinely has to keep doing: an institution
## between two households dissolves if they stop coordinating (
## InstitutionFormation.should_dissolve is windowed on purpose), so the
## guard must keep the window stocked. It does -- at the minimum rate that
## window requires, rather than one contract per assessment.
func test_a_living_institution_is_kept_alive_at_the_dissolution_windows_own_rate():
	var chunk_coord := _berlin_chunk() + Vector2i(0, 5)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var founders: Array = []
	for a_seed in _non_producer_seeds(3):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)
	manager.market_store().market_for(settlement_id).add_stock("meat", 4000)

	var steps := int(
		InstitutionFormation.RECENT_WINDOW_SECONDS / EarthChunkManager.SETTLEMENT_STEP_INTERVAL
	) * 3
	for step in steps:
		manager.advance_world_age(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var contracts: int = manager.contract_store().to_dicts().size()
	gut.p("TRADE contracts over %d steps spanning 3 dissolution windows = %d" % [steps, contracts])
	assert_eq(
		manager.active_institution_count_for_settlement(settlement_id),
		1,
		"the institution is still alive, so the guard really did keep coordinating"
	)
	assert_lt(
		contracts, steps,
		"but not by signing one contract per assessment, which is the growth this guard is for"
	)


## `count` distinct founder seeds whose occupation gathers no food at all.
func _non_producer_seeds(count: int) -> Array:
	var production := NpcProduction.new()
	var seeds: Array = []
	var seed_value := 1
	while seeds.size() < count and seed_value < 100000:
		if not production.is_producer(NpcIdentity.new(seed_value).occupation):
			seeds.append(seed_value)
		seed_value += 1
	return seeds


# -- the two things the empty ledger made impossible --


## Offscreen GROWTH. Before the granary had a source, capacity was
## permanently 0 for every settlement in the world, so status_for called
## every settlement with anybody in it DECLINING and a village could only
## ever be doing well while the player stood in it with a live VillageMarket
## loaded. This settlement's chunk is never loaded at all.
##
## It starts with nothing stored -- a newly founded village has no granary
## -- and fills one out of its own real gathering, on its very first
## assessment.
func test_an_unloaded_settlement_can_grow_on_its_own_gathering():
	# +2,+1 from the Berlin chunk: real inland land with real water in it, so
	# all three producer occupations have something to read. Which chunk is
	# not incidental -- see the note on NpcProduction's scale in
	# test_an_unloaded_settlement_really_declines_by_eating_through_its_stores.
	var chunk_coord := _berlin_chunk() + Vector2i(2, 1)
	manager.record_settlement_founded_if_new(chunk_coord, _founders_covering_every_occupation())
	assert_false(
		manager._loaded_villages.has(chunk_coord), "precondition: nobody is watching this village"
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(
		manager.event_store().events_of_type("settlement_growing").size(),
		1,
		"a village nobody is watching can finally be doing well, off its own work"
	)
	assert_eq(
		manager.event_store().events_of_type("settlement_declining").size(),
		0,
		"and is not called a famine merely because nobody has walked past it"
	)
	assert_gt(
		SettlementState.carrying_capacity(
			manager.market_store().market_for(EntityRef.for_settlement(chunk_coord))
		),
		0,
		"off a real, persisted number rather than a live market that is not there"
	)


## Offscreen DECLINE, which is the same hole from the other side and the
## less obvious half: an empty ledger did not merely stop settlements
## growing, it stopped them declining too. A settlement that reads DECLINING
## on its first assessment and forever after has not declined -- it was
## never alive. A real decline is a village that was doing well and then ate
## through what it had, and that needs stores to eat.
##
## The census is DERIVED rather than picked: one fisher, plus exactly enough
## non-producing neighbours that the settlement's subsistence draw sits just
## above what that fisher's real regional catch brings in. A village
## slightly outgrowing its own water is the slow-motion version of famine,
## and slow is what the status dwell needs before it will believe it -- so
## the test asserts up front that the deficit really is slow enough to be
## seen, out of SettlementState's own band and FOOD_PER_HOUSEHOLD rather
## than out of a chosen number.
##
## THE EDGE THIS DELIBERATELY STOPS SHORT OF, because it is real: once the
## granary goes completely bare, capacity is 0 and step_settlements' own
## "absence of evidence, not evidence of famine" guard suppresses the
## decline for an unloaded settlement. So a village declines offscreen while
## it still has SOMETHING put by and cannot once it has nothing, which is
## the wrong way round; that guard's premise is weaker now that an unloaded
## settlement's granary is a real reading, and narrowing it is its own
## change.
func test_an_unloaded_settlement_really_declines_by_eating_through_its_stores():
	# +0,+1: real water, but a THIN catch by comparison, which is what makes
	# the deficit small enough to watch.
	var chunk_coord := _berlin_chunk() + Vector2i(0, 1)
	var settlement_id := EntityRef.for_settlement(chunk_coord)
	var region = manager._seeded_region_for(settlement_id)
	var catch: float = float(
		SettlementGranary.gathered_over(["fisher"], region, EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
			.get("fish", 0.0)
	)
	assert_gt(catch, 0.0, "precondition: there really is a catch here to fall short of")

	var fisher_seed: int = _seeds_covering_every_occupation()[NpcIdentity.OCCUPATIONS.find("fisher")]
	var draw := float(SettlementState.FOOD_PER_HOUSEHOLD)
	var neighbours := int(ceil((catch - draw) / draw))
	if float(SettlementGranary.subsistence_draw(1 + neighbours)) <= catch:
		neighbours += 1
	var founders: Array = [NpcIdentity.new(fisher_seed)]
	for a_seed in _non_producer_seeds(neighbours):
		founders.append(NpcIdentity.new(a_seed))
	manager.record_settlement_founded_if_new(chunk_coord, founders)

	var households := founders.size()
	var deficit := float(SettlementGranary.subsistence_draw(households)) - catch
	assert_gt(deficit, 0.0, "precondition: this village really does eat more than it lands")

	# How much food the settlement passes through while it reads DECLINING
	# with a capacity above zero -- the only window in which an unloaded
	# settlement's decline is recorded at all (see the doc comment). It has to
	# be wide enough for the dwell to run out inside it.
	var declining_below := (
		float(SettlementGranary.subsistence_draw(households)) / (1.0 + SettlementState.STABLE_BAND)
	)
	assert_gt(
		declining_below - float(SettlementState.FOOD_PER_HOUSEHOLD),
		deficit * float(EarthChunkManager.SETTLEMENT_STATUS_DWELL_STEPS),
		"precondition: the fall is slow enough for the status dwell to see it happen"
	)

	# Three times over its own subsistence draw, so it starts clearly
	# prosperous and has a long way to fall.
	manager.market_store().market_for(settlement_id).add_stock(
		"fish", 3 * SettlementGranary.subsistence_draw(households)
	)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
	assert_eq(
		manager.event_store().events_of_type("settlement_growing").size(),
		1,
		"precondition: it really was doing well, off real stored food"
	)

	var fell := false
	for step in 400:
		manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)
		if manager.event_store().events_of_type("settlement_declining").size() > 0:
			fell = true
			break
	gut.p("DECLINE %d households eating %d against a catch of %.2f -- deficit %.2f/step" % [
		households, SettlementGranary.subsistence_draw(households), catch, deficit
	])
	assert_true(
		fell, "a village nobody was watching genuinely fell, rather than never having risen"
	)
	assert_eq(
		manager.event_store().events_of_type("ruin_formed").size(),
		1,
		"leaving a real ruin behind it, offscreen, with no player anywhere near"
	)


# -- the meadow a chunk bakes, and the wind that shaped it -------------------
#
# Reported live: flowers "spread or grow way too dense", seed "should be
# carried a bit further by the wind and birds so it leaves more space between
# individual flowers", and the baked initial world state "should also respect
# this and simulate spread based on wind strength and direction". These are
# the end-to-end checks that the pure modules (MeadowSpread,
# FlowerEstablishment) are actually WIRED -- the whole point being that
# FlowerPatch.set_wind had been fully built, fully tested and never once
# called by the running game, so its meadows shed in a permanent dead calm.

func _meadow_cells(chunk_coord: Vector2i) -> Array:
	var patch = manager._flower_patches.get(chunk_coord)
	return [] if patch == null else patch.get_flower_cells()


func test_a_loaded_meadow_is_spaced_out_rather_than_carpeted():
	var chunk_coord := _berlin_chunk()
	manager._load_chunk(chunk_coord)
	var cells := _meadow_cells(chunk_coord)
	assert_gt(cells.size(), 0, "precondition: Berlin's grassland grew a meadow")
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			assert_gte(
				Vector2(cells[i] - cells[j]).length(), FlowerEstablishment.MIN_SPACING_TILES,
				"a real loaded chunk put %s and %s on top of each other" % [cells[i], cells[j]]
			)


## The chunk's world origin has to actually reach MeadowSpread, or every chunk
## would grow the meadow that belongs at the world origin and the map would be
## one meadow stamped over and over (which two chunks with DIFFERENT biome
## masks would still hide -- hence comparing against the origin-zero meadow
## for this chunk's own biome, rather than against a neighbour).
func test_a_chunks_meadow_is_grown_at_its_own_place_in_the_world():
	var chunk_coord := _berlin_chunk()
	manager._load_chunk(chunk_coord)
	var chunk := manager.generator.generate_chunk(chunk_coord, EarthChunkManager.CHUNK_SIZE)
	var at_the_origin := MeadowSpread.colonise(
		FlowerPatch.MEADOW_WORLD_SEED,
		Vector2i.ZERO,
		chunk.width,
		chunk.height,
		chunk.biome,
		Vector2.RIGHT,
		0.0,
		FlowerPatch.MAX_FLOWERS
	)
	assert_ne(
		_meadow_cells(chunk_coord), at_the_origin.keys(),
		"this chunk grew the meadow that belongs at world (0, 0) -- its origin never reached MeadowSpread"
	)


## Founders live in world space so a meadow crosses a chunk line. The visible
## consequence, and the thing that would give the seams away: two flowers
## either side of a boundary must be spaced against each other too.
func test_neighbouring_chunks_do_not_crowd_flowers_across_their_seam():
	var here := _berlin_chunk()
	var there := here + Vector2i(1, 0)
	manager._load_chunk(here)
	manager._load_chunk(there)
	var left: Array = []
	for cell in _meadow_cells(here):
		left.append(cell + here * EarthChunkManager.CHUNK_SIZE)
	assert_gt(left.size(), 0, "precondition: the western chunk grew a meadow")
	for cell in _meadow_cells(there):
		var world_cell: Vector2i = cell + there * EarthChunkManager.CHUNK_SIZE
		for other in left:
			assert_gte(
				Vector2(world_cell - other).length(), FlowerEstablishment.MIN_SPACING_TILES,
				"%s and %s crowd each other across the chunk seam" % [world_cell, other]
			)


## The bug this exists to prevent recurring: FlowerPatch.set_wind existed,
## worked, and was called by nothing but its own test file, so every meadow in
## the running game shed its seed in a permanent dead calm and the downwind
## drift the model computes was never applied at all.
func test_the_live_weather_reaches_the_meadow_that_sheds_seed():
	var chunk_coord := _berlin_chunk()
	manager._load_chunk(chunk_coord)
	var patch = manager._flower_patches[chunk_coord]
	manager.step_flowers(0.1)
	assert_gt(
		patch.wind_strength(), 0.0,
		"the meadow is still shedding in a dead calm -- set_wind has no live caller"
	)
	assert_almost_eq(patch.wind_direction().length(), 1.0, 0.001)


# -- naming a flower under the cursor ----------------------------------------

## Reported live: flowers "still don't [show] hover tooltips". Every other
## hoverable entity is a Node2D that joins HoverTargetFinder's group, but
## flowers are ground decoration -- a bare Sprite2D per cell, no script and no
## group, precisely so a meadow costs one texture and not forty nodes. So they
## are answered the way tall grass already is: a cheap query the World's hover
## scan falls through to (see World._update_hover_tooltip).

func test_a_flower_under_the_cursor_can_be_named():
	var chunk_coord := _berlin_chunk()
	manager._load_chunk(chunk_coord)
	var cells := _meadow_cells(chunk_coord)
	assert_gt(cells.size(), 0, "precondition: there is a meadow to point at")
	var named := 0
	for cell in cells:
		var world_cell: Vector2i = cell + chunk_coord * EarthChunkManager.CHUNK_SIZE
		var pixel := Vector2(
			(world_cell.x + 0.5) * TerrainRenderer.TILE_SIZE,
			(world_cell.y + 0.5) * TerrainRenderer.TILE_SIZE
		)
		if manager.flower_name_at(pixel) != "":
			named += 1
	assert_gt(named, 0, "not one flower in a whole meadow could be named")


## And bare ground names nothing -- a tooltip over empty grass would be the
## world claiming something is there that is not.
##
## "Bare" means clear of every bloom's DRAWN extent, not merely a cell with no
## stem in it: a bloom is drawn above its own cell and answers within the
## hover radius of where it is drawn, so the cell next door to a flower is
## legitimately part of that flower.
func test_bare_ground_names_no_flower():
	var chunk_coord := _berlin_chunk()
	manager._load_chunk(chunk_coord)
	var origin := chunk_coord * EarthChunkManager.CHUNK_SIZE
	var flowers := _meadow_cells(chunk_coord)
	assert_gt(flowers.size(), 0, "precondition: a meadow to stand clear of")
	var checked := 0
	for y in 32:
		for x in 32:
			var cell := Vector2i(x, y)
			var clear := true
			for flower in flowers:
				if Vector2(cell - flower).length() < 6.0:
					clear = false
					break
			if not clear:
				continue
			var pixel := Vector2(
				(origin.x + x + 0.5) * TerrainRenderer.TILE_SIZE,
				(origin.y + y + 0.5) * TerrainRenderer.TILE_SIZE
			)
			assert_eq(
				manager.flower_name_at(pixel), "",
				"open ground at %d,%d named a flower" % [x, y]
			)
			checked += 1
			if checked >= 20:
				return
	assert_gt(checked, 0, "the meadow left no open ground to check")


func test_unloaded_ground_names_no_flower():
	assert_eq(manager.flower_name_at(Vector2(999999.0, 999999.0)), "")
