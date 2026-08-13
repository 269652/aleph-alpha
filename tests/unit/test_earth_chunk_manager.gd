extends GutTest

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")

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


## The GPU water overlay (see WaterShader): every loaded ocean cell gets a
## marker cell on the dedicated water layer (which carries the animated
## water material); unloading erases them again.
func test_water_overlay_marks_exactly_the_loaded_ocean_cells():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	var ocean_cells := 0
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if manager.biome_at_global(global_x, global_y) == "ocean":
					ocean_cells += 1
	assert_eq(water_layer.get_used_cells().size(), ocean_cells)
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


## Wind-driven pacing: set_wind_strength drives a continuous shader uniform on
## the shared water material (see WaterShader.set_wind_strength), the same
## pattern as set_rain above.
func test_set_wind_strength_updates_the_water_materials_wind_strength_uniform():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	manager.set_wind_strength(1.4)
	assert_eq((water_layer.material as ShaderMaterial).get_shader_parameter("wind_strength"), 1.4)

	manager.set_wind_strength(0.3)
	assert_eq((water_layer.material as ShaderMaterial).get_shader_parameter("wind_strength"), 0.3)
	water_layer.free()


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


func test_elevation_at_global_matches_the_generator_for_a_loaded_tile():
	manager.update(Vector2i(5, 5))
	var expected := manager.generator.elevation_at_global(5, 5)
	assert_almost_eq(manager.elevation_at_global(5, 5), expected, 0.0001)


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


# -- building/destruction -----------------------------------------------------

func test_build_at_global_sets_a_modification_when_the_chunk_is_loaded():
	manager.update(_berlin_tile)
	var success := manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")
	assert_true(success)
	assert_eq(manager.modification_at_global(_berlin_tile.x, _berlin_tile.y), "earth")


func test_build_at_global_fails_when_the_chunk_is_not_loaded():
	var success := manager.build_at_global(999999, 999999, "earth")
	assert_false(success)


func test_build_at_global_repaints_the_tile_map_cell():
	manager.update(_berlin_tile)
	manager.build_at_global(_berlin_tile.x, _berlin_tile.y, "earth")
	var terrain_renderer := TerrainRenderer.new()
	assert_eq(
		tile_map_layer.get_cell_atlas_coords(_berlin_tile),
		terrain_renderer.atlas_coords_for_modification("earth")
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


func _chunk_coord_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(tile.x) / EarthChunkManager.CHUNK_SIZE),
		floori(float(tile.y) / EarthChunkManager.CHUNK_SIZE)
	)


func _child_instance_ids(parent: Node2D) -> Array[int]:
	var ids: Array[int] = []
	for child in parent.get_children():
		ids.append(child.get_instance_id())
	return ids
