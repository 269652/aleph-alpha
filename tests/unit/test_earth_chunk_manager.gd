extends GutTest

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const AmbientFlyerRenderer = preload("res://src/rendering/ambient_flyer_renderer.gd")
const TreePlacement = preload("res://src/world/tree_placement.gd")
const GeoCoordinates = preload("res://src/world/geo_coordinates.gd")
const EarthChunkGenerator = preload("res://src/world/earth_chunk_generator.gd")
const TerrainRenderer = preload("res://src/rendering/terrain_renderer.gd")
const ChoppableTree = preload("res://src/rendering/choppable_tree.gd")
const BiomeClassifier = preload("res://src/world/biome_classifier.gd")
const SeasonCycle = preload("res://src/world/season_cycle.gd")
const TreeSpecies = preload("res://src/world/tree_species.gd")
const Snowfall = preload("res://src/world/snowfall.gd")
const ProceduralTreeSprite = preload("res://src/rendering/procedural_tree_sprite.gd")
const CreatureRenderer = preload("res://src/rendering/creature_renderer.gd")
const CreatureMarker = preload("res://src/rendering/creature_marker.gd")
const RegionDifficulty = preload("res://src/world/region_difficulty.gd")
const TallGrass = preload("res://src/world/tall_grass.gd")
const ArtResolution = preload("res://src/rendering/art_resolution.gd")
const ProceduralGrassSprite = preload("res://src/rendering/procedural_grass_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Item = preload("res://src/gameplay/item.gd")
const LiftableStone = preload("res://src/rendering/liftable_stone.gd")
const SmashableStone = preload("res://src/rendering/smashable_stone.gd")

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


## Water is no longer wind-driven (see WaterShader's class doc) -- kept as a
## harmless no-op rather than removed so world.gd's existing call site
## doesn't need touching.
func test_set_wind_strength_is_a_harmless_no_op():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)
	manager.set_wind_strength(1.4)  # must not error
	water_layer.free()


## record_water_disturbance feeds the SAME shared material set_water_layer
## installed on the tile layer -- a fish/player/animal ripple must actually
## show up on the water the player sees, not on some other material.
func test_record_water_disturbance_updates_the_installed_water_materials_uniforms():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	manager.record_water_disturbance(Vector2(12.0, 34.0))

	var material := water_layer.material as ShaderMaterial
	assert_eq(material.get_shader_parameter("disturbance_count"), 1)
	var positions: PackedVector2Array = material.get_shader_parameter("disturbance_pos")
	assert_eq(positions[0], Vector2(12.0, 34.0))
	water_layer.free()


## step_water_disturbances must age the SAME installed material's
## disturbances -- world.gd calls this every frame precisely so a recorded
## ripple actually expands/fades instead of sitting frozen at age 0.
func test_step_water_disturbances_ages_the_installed_water_materials_ripple():
	var water_layer := TileMapLayer.new()
	manager.set_water_layer(water_layer)
	manager.update(_berlin_tile)

	manager.record_water_disturbance(Vector2(1.0, 1.0))
	manager.step_water_disturbances(0.5)

	var material := water_layer.material as ShaderMaterial
	var ages: PackedFloat32Array = material.get_shader_parameter("disturbance_age")
	assert_almost_eq(ages[0], 0.5, 0.001)
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


func test_a_mature_grass_tuft_stays_at_its_intended_per_seed_world_scale():
	manager.update(_berlin_tile)
	var found_mature := false
	for chunk_coord in manager._grass_sprites.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		for cell in manager._grass_sprites[chunk_coord]:
			if sim.get_growth(cell) < 1.0:
				continue
			found_mature = true
			var cards: Array = manager._grass_sprites[chunk_coord][cell]
			assert_gte(cards.size(), 3, "one grass cell should read as a small field of blade cards")
			var sprite: Sprite2D = cards[0]
	var expected := 16.0 / float(sprite.region_rect.size.x)
			assert_almost_eq(
				sprite.scale.x, expected, 0.001,
				"a mature tuft must stay at its intended (per-variant) world size, not balloon to the full canvas"
			)
	assert_true(found_mature, "precondition: Berlin's grassland seeded at least one mature patch")


## A tuft is a CLUMP standing on a tile, not a tile-sized carpet -- its
## rendered WORLD height must stay independent of how many art pixels its
## canvas is drawn at, and vary between roughly 0.75 and 1.5 tiles so a
## meadow shows real height variety (see ProceduralGrassSprite.VARIANTS).
## Doubling ProceduralGrassSprite.SIZE for finer blade detail regressed the
## independence part once already: without its own world-space target, the
## tuft rendered a full tile wide instead of half one.
func test_a_mature_grass_tufts_world_height_stays_within_its_intended_range():
	manager.update(_berlin_tile)
	var found_mature := false
	for chunk_coord in manager._grass_sprites.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		for cell in manager._grass_sprites[chunk_coord]:
			if sim.get_growth(cell) < 1.0:
				continue
			found_mature = true
			var cards: Array = manager._grass_sprites[chunk_coord][cell]
			for sprite: Sprite2D in cards:
				var rendered_height: float = sprite.scale.y * sprite.region_rect.size.y
				assert_almost_eq(rendered_height, 16.0, 0.001, "an illustrated blade card stays one tile tall")
	assert_true(found_mature, "precondition: Berlin's grassland seeded at least one mature patch")


## The whole point of per-variant sizing: a real meadow should show tufts of
## visibly different heights, not one uniform size.
func test_mature_grass_tufts_show_more_than_one_world_height():
	manager.update(_berlin_tile)
	var roots := {}
	for chunk_coord in manager._grass_sprites.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		for cell in manager._grass_sprites[chunk_coord]:
			if sim.get_growth(cell) < 1.0:
				continue
			for sprite: Sprite2D in manager._grass_sprites[chunk_coord][cell]:
				roots[snappedf(sprite.position.y, 0.01)] = true
	assert_gt(roots.size(), 1, "a patch's cards must carry distinct Y roots for y-sorted depth")


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
	var eaten: Vector2 = tufts[0].position
	var tile: Vector2i = manager._world_tile_for_pixel(eaten)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(tile)
	var cell: Vector2i = tile - chunk_coord * EarthChunkManager.CHUNK_SIZE
	assert_true(manager._grass_sprites[chunk_coord].has(cell), "precondition: it was drawn")
	manager.graze_grass_at(eaten)
	assert_false(manager._grass_sprites[chunk_coord].has(cell), "and stops being drawn at once")


# -- wild carrot (see docs/concept/taming.md) --------------------------------
#
# The carrot existed as an item with nothing in the world producing it, which
# left taming unreachable in normal play. Wild carrot (Daucus carota) is a
# meadow plant that grows among the grasses -- so it comes up where the player
# is already pulling grass for fibre, rather than needing a farming system
# that is not wired into the game yet.

func test_harvesting_a_meadow_sometimes_turns_up_a_wild_carrot():
	manager.update(_berlin_tile)
	var carrots := 0
	var harvests := 0
	var drops: Array = []
	var handler := func(stack, _pos): drops.append(stack)
	WorldItemBus.item_dropped.connect(handler)
	for chunk_coord in manager._grass_sims.keys():
		var sim: TallGrass = manager._grass_sims[chunk_coord]
		for cell in sim.get_patch_cells().duplicate():
			if sim.get_growth(cell) < 1.0:
				continue
			var tile: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + cell
			var pixel := Vector2(tile.x + 0.5, tile.y + 0.5) * TerrainRenderer.TILE_SIZE
			if manager.harvest_grass_near(pixel, 0):
				harvests += 1
	WorldItemBus.item_dropped.disconnect(handler)
	for stack in drops:
		if stack.item.id == "carrot":
			carrots += 1
	assert_gt(harvests, 20, "precondition: a meadow to work")
	assert_gt(carrots, 0, "a meadow should yield the occasional wild carrot")
	assert_lt(carrots, harvests, "and it is an occasional find, not every clump")


## Deterministic like everything else in the world sim: the same tile always
## either has a carrot in it or does not, so a reloaded chunk agrees with
## itself rather than rerolling.
func test_which_clumps_hide_a_carrot_is_deterministic():
	for tile in [Vector2i(3, 9), Vector2i(-40, 12), Vector2i(101, -7)]:
		assert_eq(
			EarthChunkManager.has_wild_carrot(tile), EarthChunkManager.has_wild_carrot(tile)
		)


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
	assert_lte(
		manager._loaded_ambient_flyers[chunk_coord].size(),
		AmbientFlyerRenderer.max_flyers_per_chunk(),
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
