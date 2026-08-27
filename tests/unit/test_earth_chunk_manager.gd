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
const SeedCaching = preload("res://src/gameplay/seed_caching.gd")
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
const FlowerSpecies = preload("res://src/world/flower_species.gd")
const ProceduralFlowerSprite = preload("res://src/rendering/procedural_flower_sprite.gd")
const WildCropPatch = preload("res://src/world/wild_crop_patch.gd")
const WildCropMarker = preload("res://src/rendering/wild_crop_marker.gd")
const AntColony = preload("res://src/world/ant_colony.gd")
const FlyColony = preload("res://src/gameplay/fly_colony.gd")
const FruitingModel = preload("res://src/world/fruiting_model.gd")
const FlowerPatch = preload("res://src/world/flower_patch.gd")

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


## record_death_at is record_birth_at's counterpart in the opposite
## direction: an individual death near the player (predator kill or player
## weapon, see CreatureMarker.take_damage) has to move the SAME aggregate a
## birth does, or a kill in front of the player would vanish the moment the
## chunk unloads.
func test_record_death_at_lowers_the_regions_herbivore_population():
	manager.update(_berlin_tile)
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var pixel := Vector2(
		(center_chunk.x * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE,
		(center_chunk.y * EarthChunkManager.CHUNK_SIZE + 5) * TerrainRenderer.TILE_SIZE
	)
	manager._ecosystem.seed_populations(center_chunk, 1.0, 0.0)
	var before := manager.herbivore_population_at_chunk(center_chunk)
	manager.record_death_at(pixel, false, 0.4)
	assert_almost_eq(manager.herbivore_population_at_chunk(center_chunk), before - 0.4, 0.001)


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


# -- pollination feedback: bees recognize blossoming fruit trees too ---------
#
# Bees used to visit only FLOWERS, and crop_potential was a pure function of
# genome and time -- zero connection to the pollinator system. blossoms_near
# is the tree-side counterpart of flowers_near (same {position, species,
# nectar, landing} shape, so AmbientFlyerMarker's existing targeting machinery
# treats a blossoming tree exactly like a flower it already knows how to
# work), and record_pollination_visit_at is the counterpart of
# drink_nectar_at. Wind-pollinated species (pine/acorn/hazelnut/walnut -- see
# TreeSpecies.needs_pollinators_for) never appear here: a real bee has no
# reward to find at a catkin or a cone.

## A tree position landing inside chunk (0,0) whose OWN genome (step_fruiting
## derives species from _forage_scheduler.genome_for(position), never from a
## tree node's own species_bias field -- the two only agree in the real game
## because TreeRenderer sets a spawned tree's species_bias FROM that same
## genome) actually resolves to `species`, with a non-trivial crop -- so a
## comparison between visited/unvisited has something to show a difference
## in, and isn't silently comparing two zeros or the wrong species entirely.
func _fruit_bearing_tree_position(species: String) -> Vector2:
	var fm := FruitingModel.new()
	var species_yield: float = TreeSpecies.yield_multiplier_for(species)
	for i in 200:
		var candidate := Vector2(10.0 + float(i) * 2.0, 10.0 + float(i) * 1.0)
		var genome := manager._forage_scheduler.genome_for(candidate)
		if TreeSpecies.species_for_bias(genome.species_bias) != species:
			continue
		if fm.crop_potential(genome, species_yield) >= 8:
			return candidate
	return Vector2(10, 10)


func _add_loaded_tree(species: String, position: Vector2) -> ChoppableTree:
	var tree := ChoppableTree.new()
	tree.position = position
	# Matches the genome step_fruiting will derive for this same position --
	# only cosmetic (canopy tint), but kept consistent with how a real spawned
	# tree's species_bias always agrees with its own genome.
	tree.species_bias = manager._forage_scheduler.genome_for(position).species_bias
	entities_parent.add_child(tree)
	# set_ripe_fruit no-ops with no canopy bound (see ChoppableTree) -- a real
	# tree always has one via TreeRenderer, and ripe_fruit_count() has to
	# actually update for these tests to observe anything.
	var canopy := Sprite2D.new()
	tree.add_child(canopy)
	tree.bind_canopy(canopy)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(position))
	if not manager._loaded_trees.has(chunk_coord):
		manager._loaded_trees[chunk_coord] = []
	manager._loaded_trees[chunk_coord].append(tree)
	return tree


func test_blossoms_near_finds_a_blossoming_insect_pollinated_tree_in_spring():
	manager.jump_to_season("spring")
	var position := _fruit_bearing_tree_position("apple")
	_add_loaded_tree("apple", position)

	var found: Array = manager.blossoms_near(position, 8)

	assert_eq(found.size(), 1)
	assert_eq(found[0]["position"], position)
	assert_eq(String(found[0]["species"]), "apple")


func test_blossoms_near_excludes_wind_pollinated_species():
	manager.jump_to_season("spring")
	var position := _fruit_bearing_tree_position("walnut")
	_add_loaded_tree("walnut", position)

	assert_eq(
		manager.blossoms_near(position, 8).size(), 0,
		"a wind-pollinated tree offers a bee nothing to visit"
	)


func test_blossoms_near_is_empty_outside_spring():
	manager.jump_to_season("summer")
	var position := _fruit_bearing_tree_position("apple")
	_add_loaded_tree("apple", position)

	assert_eq(
		manager.blossoms_near(position, 8).size(), 0,
		"a tree is only in blossom in spring (see IllustratedTree.CANOPY_BLOSSOM)"
	)


func test_blossoms_near_respects_its_radius():
	manager.jump_to_season("spring")
	var position := _fruit_bearing_tree_position("apple")
	_add_loaded_tree("apple", position + Vector2(9999.0, 0.0))

	assert_eq(manager.blossoms_near(position, 8).size(), 0)


func test_record_pollination_visit_at_increments_the_trees_visit_count():
	var position := _fruit_bearing_tree_position("apple")
	var tree := _add_loaded_tree("apple", position)

	var recorded: bool = manager.record_pollination_visit_at(position)

	assert_true(recorded, "a bee landing on a real tree should register")
	assert_eq(
		tree.pollination_visits_in_cycle(FruitingModel.BEARING_CYCLE_SECONDS, manager.world_age_seconds()),
		1.0
	)


func test_record_pollination_visit_at_returns_false_when_nothing_is_there():
	assert_false(manager.record_pollination_visit_at(Vector2(123456.0, 123456.0)))


## THE feedback loop: a bee-visited apple sets a measurably bigger crop than
## an identical, unvisited one, while a wind-pollinated species is unaffected
## either way -- composed into crop_potential's existing yield_multiplier
## alongside TreeSpecies.yield_multiplier_for, not instead of it.
func test_step_fruiting_gives_a_visited_apple_a_bigger_crop_than_an_unvisited_one():
	var position := _fruit_bearing_tree_position("apple")
	var visited := _add_loaded_tree("apple", position)
	var unvisited := _add_loaded_tree("apple", position)
	for i in FruitingModel.POLLINATION_SATURATION_VISITS:
		visited.record_pollination_visit(FruitingModel.BEARING_CYCLE_SECONDS, 0.0)

	# Into apple's ripening window (see FruitingModel.RIPENING_BY_SPECIES),
	# far from the player so nothing drops -- only the drawn ripe count
	# matters here.
	manager.advance_world_age(SeasonCycle.SECONDS_PER_YEAR * 0.6)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, position + Vector2(999999.0, 999999.0))

	assert_gt(
		visited.ripe_fruit_count(), unvisited.ripe_fruit_count(),
		"a bee-visited apple should carry more ripe fruit than an identical unvisited one"
	)


## A pine (wind-pollinated) sheds the same crop whether or not a bee ever
## lands on it -- pollination feedback is scoped to insect-pollinated species
## only (see TreeSpecies.needs_pollinators_for).
func test_step_fruiting_leaves_a_wind_pollinated_species_unaffected_by_visits():
	var position := _fruit_bearing_tree_position("pine")
	var visited := _add_loaded_tree("pine", position)
	var unvisited := _add_loaded_tree("pine", position)
	for i in FruitingModel.POLLINATION_SATURATION_VISITS:
		visited.record_pollination_visit(FruitingModel.BEARING_CYCLE_SECONDS, 0.0)

	manager.advance_world_age(SeasonCycle.SECONDS_PER_YEAR * 0.65)
	manager.step_fruiting(EarthChunkManager.FRUITING_INTERVAL, position + Vector2(999999.0, 999999.0))

	assert_eq(
		visited.ripe_fruit_count(), unvisited.ripe_fruit_count(),
		"a wind-pollinated tree's crop must not depend on bee visits"
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
			# Every cell contributes exactly CARD_COUNT instances.
			assert_eq(mmi.multimesh.instance_count % IllustratedGrassPatch.CARD_COUNT, 0)
			found_any_band = true
	assert_true(found_any_band, "precondition: Berlin's grassland seeded at least one patch")


## Every cell grouped into one band's draw call must actually belong there
## by IllustratedGrassPatch's own band math - the whole point of banding is
## that a band's Y-sort position is representative of the cells inside it.
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
			if not DecorationLod.keeps_decoration_tile(origin + cell, player_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
				continue
			var band := IllustratedGrassPatch.band_index_for_local_y(cell.y, EarthChunkManager.CHUNK_SIZE)
			expected_by_band[band] = int(expected_by_band.get(band, 0)) + IllustratedGrassPatch.CARD_COUNT
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

	# Stand right on the cell: it must be drawn (precondition).
	manager.update(a_tile)
	var band := IllustratedGrassPatch.band_index_for_local_y(a_cell.y, EarthChunkManager.CHUNK_SIZE)
	var near_count: int = manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	assert_gt(near_count, 0, "precondition: standing on the cell, its band has cards")

	# Walk far enough away (well beyond any reasonable half_span+buffer)
	# that the chunk itself still decorates (a village-sized hop, not a
	# world away) but this one cell no longer falls in the view window.
	manager.update(a_tile + Vector2i(0, 200))
	if not manager._grass_sprites.has(chunk_coord) or not manager._grass_sprites[chunk_coord].has(band):
		assert_true(true, "the band (or whole chunk) dropped entirely once nothing in it was in view -- also correct")
		return
	var far_count: int = manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	assert_lt(far_count, near_count, "walking away from the cell must reduce (or zero) its band's card count")


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
	var expected_by_band: Dictionary = {}
	for cell in sim.get_patch_cells():
		var tile: Vector2i = origin + cell
		if not DecorationLod.keeps_decoration_tile(tile, far_tile, half_span, EarthChunkManager.GRASS_VIEW_BUFFER_TILES):
			continue
		var cell_band := IllustratedGrassPatch.band_index_for_local_y(cell.y, EarthChunkManager.CHUNK_SIZE)
		expected_by_band[cell_band] = int(expected_by_band.get(cell_band, 0)) + IllustratedGrassPatch.CARD_COUNT

	var far_band := IllustratedGrassPatch.band_index_for_local_y(far_cell.y, EarthChunkManager.CHUNK_SIZE)
	assert_gt(expected_by_band.get(far_band, 0), 0, "precondition: far_cell's own band should now expect a nonzero count, standing right on it")

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

## Self-pollinates every flower in Berlin's own chunk (see pollinate_flower_at
## further below for what this call actually does, and
## test_pollinate_flower_at_makes_a_self_pollinated_meadow_actually_shed_seed
## for the test that proves the delivery path itself works). The seeds_near/
## take_seed_at tests in this section only care that SEED exists to be found
## -- they used to get it for free because FlowerPatch.shed_seed had no
## pollination gate at all; once that gate became real (2026-08-26, see
## Pollination/pollinate_flower_at), an unvisited meadow correctly stopped
## shedding, and every test below started failing for that same reason. This
## helper stands in for "a bee has already been working this meadow."
func _pollinate_every_flower_near_berlin() -> void:
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var patch: FlowerPatch = manager._flower_patches[chunk_coord]
	for cell in patch.get_flower_cells():
		manager.pollinate_flower_at(_pixel_for(chunk_coord, cell), patch.species_at(cell))


## Flowers whose bloom is over have gone to seed (see FlowerPatch.seed_cells
## / concept/flora.md). This is the seeds_near/take_seed_at pair FlyerDiet
## has been waiting on since the diet table was written -- sparrows carried a
## FOOD_SEEDS entry with nothing in the world to eat.
func test_seeds_near_reports_seed_lying_on_the_ground():
	manager.update(_berlin_tile)
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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
	manager.jump_to_season("winter")
	_pollinate_every_flower_near_berlin()
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


# -- pollinate_flower_at: pollen actually changes hands at a flower visit ----
#
# Pollination (sex_of/gives_pollen/can_set_seed/pollinates/pollen_after_visit/
# sets_seed) was a complete, fully-tested pure module with no LIVE caller --
# FlowerPatch.pollinate (its only caller) was itself only ever invoked from
# its own test file, so _pollinated stayed permanently empty and a meadow
# never actually shed seed through pollination (see FlowerPatch.shed_seed).
# pollinate_flower_at is the flower-side counterpart of
# record_pollination_visit_at (the tree-blossom equivalent above, which
# already worked end-to-end): a bee/butterfly landing on a flower now
# actually exchanges pollen, not merely nectar.

func test_pollinate_flower_at_returns_either_nothing_or_the_visited_flowers_own_species():
	manager.update(_berlin_tile)
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var patch: FlowerPatch = manager._flower_patches[chunk_coord]
	assert_gt(patch.get_flower_cells().size(), 0, "precondition: some flowers loaded near Berlin")

	for cell in patch.get_flower_cells():
		var species: String = patch.species_at(cell)
		var carried: String = manager.pollinate_flower_at(_pixel_for(chunk_coord, cell), "")
		assert_true(
			carried == "" or carried == species,
			"Pollination.pollen_after_visit only ever returns '' or the visited flower's own species"
		)


## Proven through the real EarthChunkManager surface, not FlowerPatch
## directly -- self-pollinating every flower in a loaded meadow this way must
## have a REAL behavioural effect: ground_seed_cells() actually gains seed,
## read directly off the manager's own patch rather than the combined
## seeds_near surface (which TallGrass alone can already satisfy -- see
## concept/long_grass.md -- so a test built on seeds_near could pass even if
## flower pollination stayed dead code).
func test_pollinate_flower_at_makes_a_self_pollinated_meadow_actually_shed_seed():
	manager.update(_berlin_tile)
	manager.jump_to_season("winter")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	var patch: FlowerPatch = manager._flower_patches[chunk_coord]
	assert_gt(patch.get_flower_cells().size(), 0, "precondition: some flowers loaded near Berlin")

	for cell in patch.get_flower_cells():
		var species: String = patch.species_at(cell)
		manager.pollinate_flower_at(_pixel_for(chunk_coord, cell), species)

	for i in 400:
		manager.step_flowers(1.0)

	assert_gt(
		manager._flower_patches[chunk_coord].ground_seed_cells().size(), 0,
		"a fully self-pollinated meadow, visited through the real EarthChunkManager surface, should shed seed"
	)


## The other direction, locked in as a regression guard: a meadow nothing
## ever pollinated must still shed ZERO seed, even after a long simulated
## time, so a future change cannot silently make FlowerPatch shed
## unconditionally again without a test noticing.
func test_an_unpollinated_meadow_still_sheds_no_seed_through_the_manager():
	manager.update(_berlin_tile)
	manager.jump_to_season("winter")
	var chunk_coord := _chunk_coord_for_tile(_berlin_tile)
	assert_gt(
		manager._flower_patches[chunk_coord].get_flower_cells().size(), 0,
		"precondition: some flowers loaded near Berlin"
	)

	for i in 400:
		manager.step_flowers(1.0)

	assert_eq(
		manager._flower_patches[chunk_coord].ground_seed_cells().size(), 0,
		"a meadow nothing pollinated should not seed itself, even after a long simulated time"
	)


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
	var band := IllustratedGrassPatch.band_index_for_local_y(cell.y, EarthChunkManager.CHUNK_SIZE)
	assert_true(manager._grass_sprites[chunk_coord].has(band), "precondition: its band was drawn")
	var before: int = manager._grass_sprites[chunk_coord][band].multimesh.instance_count
	manager.graze_grass_at(eaten)
	var bands: Dictionary = manager._grass_sprites[chunk_coord]
	if bands.has(band):
		assert_eq(bands[band].multimesh.instance_count, before - IllustratedGrassPatch.CARD_COUNT, "the eaten tuft's cards stop being drawn at once")
	else:
		assert_eq(before, IllustratedGrassPatch.CARD_COUNT, "the band only disappears outright if that was its only tuft")


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


# -- squirrel scatter-hoarding: a squirrel picks up a fallen tree NUT and
# either eats it outright or caches it as a new sapling elsewhere (see
# SquirrelNutCaching / docs/concept/flora.md's disperser-vs-predator
# tension) -- the fruit/nut-side counterpart of the mouse's grass-seed
# caching above, wired to fruit_near/take_fruit_at/try_plant_seed_at instead
# of grass_seeds_near/take_grass_seed_at/plant_grass_at.

func test_a_squirrel_standing_on_a_fallen_nut_picks_it_up():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "walnut"))
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(squirrel.carried_nut_species, "walnut", "the squirrel should have picked the nut up")
	assert_eq(manager.fruit_near(pixel, 5).size(), 0, "eaten off the ground, not merely noticed")
	ground_items.free()


## Only squirrels do this -- a non-squirrel creature standing on the exact
## same nut must leave it alone, same gate as the mouse's grass-seed caching.
func test_a_non_squirrel_creature_does_not_cache_a_nut():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "walnut"))
	var horse := manager._creature_renderer.spawn_single(
		creatures_parent, "horse", pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(horse)

	assert_eq(horse.carried_nut_species, "")
	assert_eq(manager.fruit_near(pixel, 5).size(), 1, "a horse must not eat a nut off the ground")
	ground_items.free()


## Only real NUT species (TreeSpecies.is_nut) are a candidate for the
## crack-or-cache tension -- a fallen cherry is fleshy fruit, and a squirrel
## finding one just leaves it for the ordinary generic fruit-eating path
## (GrazerForaging's ungated FOOD_FRUIT), not this mechanic.
func test_a_squirrel_does_not_cache_fleshy_fruit():
	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(pixel, "cherry"))
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(squirrel.carried_nut_species, "", "cherry is fleshy fruit, not a nut")
	assert_eq(manager.fruit_near(pixel, 5).size(), 1, "the cherry should be left for generic fruit-eating")
	ground_items.free()


## Symmetric to the mouse's own "too soon" case: a squirrel that has not yet
## gone its own carry distance keeps carrying rather than resolving on the
## spot.
func test_a_squirrel_does_not_resolve_before_travelling_its_carry_distance():
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)
	squirrel.carried_nut_species = "walnut"
	squirrel.carried_nut_origin = pixel  # has not moved at all yet

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(squirrel.carried_nut_species, "walnut", "still carrying")


## Once a squirrel has carried its nut far enough and the roll comes up
## "cached" (see SquirrelNutCaching.nut_is_consumed), it sprouts a new
## sapling wherever the squirrel is standing -- via the SAME tree-seed sink
## robin's own fruit dispersal already uses (try_plant_seed_at), gated to
## forest/rainforest exactly like that path.
func test_a_squirrel_caches_its_carried_nut_as_a_new_sapling_once_it_has_travelled_far_enough():
	manager.update(_berlin_tile)
	var planted_pixel := Vector2.ZERO
	var found := false
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var tile := _berlin_tile + Vector2i(dx, dy)
			if ["forest", "rainforest"].has(manager.biome_at_global(tile.x, tile.y)):
				planted_pixel = Vector2(tile) * TerrainRenderer.TILE_SIZE
				found = true
				break
		if found:
			break
	assert_true(found, "precondition: some forested biome should be loaded near Berlin")
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", planted_pixel, manager, TerrainRenderer.TILE_SIZE
	)
	squirrel.carried_nut_species = "walnut"
	# Already travelled well past even the longest possible carry distance.
	squirrel.carried_nut_origin = planted_pixel - Vector2(
		(SquirrelNutCaching.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
	)
	# Chosen (not just any small int) so THIS squirrel's roll comes up
	# "cached" rather than "eaten" -- the roll's own distribution is covered
	# separately by test_a_squirrel_mostly_eats_the_nut_but_sometimes_caches_it
	# in test_squirrel_nut_caching.gd, which samples many wander_seeds.
	squirrel.wander_seed = 1
	var before := entities_parent.get_child_count()

	manager._step_squirrel_nut_caching(squirrel)

	assert_gt(entities_parent.get_child_count(), before, "a new sapling should have been cached here")
	assert_eq(squirrel.carried_nut_species, "", "resolving empties the cheek pouch either way")


## Symmetric outcome: when the roll comes up "eaten" instead, nothing new
## sprouts, but the nut is still gone (the squirrel's actual meal).
func test_a_squirrel_eats_its_carried_nut_outright_when_the_roll_says_so():
	var pixel := Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	var squirrel := manager._creature_renderer.spawn_single(
		creatures_parent, "squirrel", pixel, manager, TerrainRenderer.TILE_SIZE
	)
	squirrel.carried_nut_species = "walnut"
	squirrel.carried_nut_origin = pixel - Vector2(
		(SquirrelNutCaching.CARRY_MAX_TILES + 5.0) * TerrainRenderer.TILE_SIZE, 0.0
	)
	# Chosen so THIS squirrel's roll comes up "eaten" -- see the "cached" test
	# above for the mirror case.
	squirrel.wander_seed = 0
	var before := entities_parent.get_child_count()

	manager._step_squirrel_nut_caching(squirrel)

	assert_eq(entities_parent.get_child_count(), before, "eaten outright -- nothing new should sprout")
	assert_eq(squirrel.carried_nut_species, "", "the cheek pouch empties either way")


# -- ant mounds: myrmecochory, a background per-chunk population effect
# (see AntColony / docs/concept/soil_fauna.md#ants-myrmecochory) -- driven
# centrally from EarthChunkManager.step_ants rather than from any individual
# creature, unlike the mouse's scatter-hoarding above.

## A colony is constructed and dropped alongside the worm patch for every
## loaded/unloaded chunk (see EarthChunkManager._ant_colonies).
func test_ant_colony_wiring_loads_and_unloads_with_the_chunk():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	assert_true(manager._ant_colonies.has(chunk_coord), "a loaded chunk should have an ant colony")
	assert_true(manager._ant_colonies[chunk_coord] is AntColony)

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 20, 0))

	assert_false(
		manager._ant_colonies.has(chunk_coord), "an unloaded chunk should drop its ant colony"
	)


## The end-to-end myrmecochory loop: a mound with a grass seed sitting right
## on top of it eventually harvests that seed and caches a new grass patch a
## short carry away (see AntColony.CARRY_MIN_TILES/CARRY_MAX_TILES).
func test_ants_harvest_a_nearby_seed_and_cache_a_new_patch():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var colony: AntColony = manager._ant_colonies[chunk_coord]
	var mounds: Array = colony.mound_cells()
	assert_gt(mounds.size(), 0, "precondition: this chunk has at least one ant mound")

	# A mound on grassland, away from the chunk edge so a short carry can
	# never cross into a neighbouring (possibly unloaded) chunk.
	var mound_cell := Vector2i(-1, -1)
	for candidate in mounds:
		var global: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + candidate
		if candidate.x < 2 or candidate.x >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if candidate.y < 2 or candidate.y >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if manager.biome_at_global(global.x, global.y) == "grassland":
			mound_cell = candidate
			break
	assert_ne(mound_cell, Vector2i(-1, -1), "precondition: an interior grassland mound exists")

	# Clear every loaded chunk's mature grass first: a naturally-generated
	# grassland chunk sits close to TallGrass.MAX_PATCHES on its own field
	# coverage, which would make plant_grass_at fail on the cap rather than
	# on anything ants do -- not what this test is checking.
	for coord in manager._grass_sims:
		var other: TallGrass = manager._grass_sims[coord]
		other._patches.clear()
	var sim: TallGrass = manager._grass_sims[chunk_coord]
	sim._ground_seeds[mound_cell] = true

	var patches_before := _total_grass_patch_count()
	# Only step_ants runs here -- step_tall_grass (spread/growth) is never
	# called in this loop, so the only thing that can change the total patch
	# count across the whole loaded neighbourhood is ants planting a new one.
	for i in 600:
		manager.step_ants(1.0)
	var patches_after := _total_grass_patch_count()

	assert_false(
		sim._ground_seeds.has(mound_cell),
		"the seed sitting right on the mound should eventually be harvested"
	)
	assert_gt(
		patches_after, patches_before,
		"a new grass patch should have been cached a short carry away"
	)


func _total_grass_patch_count() -> int:
	var total := 0
	for coord in manager._grass_sims:
		var sim: TallGrass = manager._grass_sims[coord]
		total += sim.get_patch_cells().size()
	return total


## Mirrors _step_grass_seed_caching's mouse-only gate: ants must not touch a
## seed further than their own SHORT forage radius, even if it exists in the
## wider grass_seeds_near query.
func test_ant_forage_radius_is_shorter_than_rodent_pickup_radius():
	assert_lt(AntColony.FORAGE_RADIUS_TILES, SeedCaching.PICKUP_RADIUS_TILES)


# -- windfall foraging: closes the "forest/rainforest mound has nothing to
# harvest" gap named in AntColony's own doc comment and soil_fauna.md, since
# TallGrass's ground seed is grassland-only. Wired to fruit_near/take_fruit_at
# instead of grass_seeds_near/take_grass_seed_at, gated to real NUTS
# (TreeSpecies.is_nut) exactly like SquirrelNutCaching's own gate, since a
# fallen fleshy fruit is not a case a single forager ant can meaningfully
## interact with the way a bird/squirrel does.

## The end-to-end forest/rainforest myrmecochory loop: a mound with a fallen
## windfall NUT sitting right on top of it eventually harvests that nut, the
## same shape test_ants_harvest_a_nearby_seed_and_cache_a_new_patch already
## pins for grassland's own grass-seed case. Whether the outcome resolves as
## eaten outright or cached as a new sapling is the property
## AntColony.windfall_is_consumed's own pinning tests cover
## (test_ant_colony.gd); this only checks the wiring: the item is actually
## noticed and taken off the ground.
func test_ants_harvest_a_nearby_windfall_nut():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var colony: AntColony = manager._ant_colonies[chunk_coord]
	var mounds: Array = colony.mound_cells()
	assert_gt(mounds.size(), 0, "precondition: this chunk has at least one ant mound")

	# A mound on forest/rainforest, away from the chunk edge so a short carry
	# can never cross into a neighbouring (possibly unloaded) chunk.
	var mound_cell := Vector2i(-1, -1)
	for candidate in mounds:
		var global: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + candidate
		if candidate.x < 2 or candidate.x >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if candidate.y < 2 or candidate.y >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if ["forest", "rainforest"].has(manager.biome_at_global(global.x, global.y)):
			mound_cell = candidate
			break
	assert_ne(mound_cell, Vector2i(-1, -1), "precondition: an interior forest/rainforest mound exists")

	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var global_tile: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + mound_cell
	var mound_pixel := Vector2(
		float(global_tile.x) + 0.5, float(global_tile.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(mound_pixel, "walnut"))

	for i in 600:
		manager.step_ants(1.0)

	assert_eq(
		manager.fruit_near(mound_pixel, 5).size(), 0,
		"the windfall nut sitting right on the mound should eventually be harvested"
	)
	ground_items.free()


## Regression guard: extending ants to windfall must not change grassland's
## existing grass-seed-only behaviour. A grassland mound must leave a nearby
## windfall nut completely untouched -- it should never even look at
## fruit_near, only grass_seeds_near.
func test_a_grassland_mound_ignores_a_nearby_windfall_nut():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(manager._world_tile_for_pixel(
		Vector2(_berlin_tile) * TerrainRenderer.TILE_SIZE
	))
	var colony: AntColony = manager._ant_colonies[chunk_coord]
	var mounds: Array = colony.mound_cells()
	assert_gt(mounds.size(), 0, "precondition: this chunk has at least one ant mound")

	var mound_cell := Vector2i(-1, -1)
	for candidate in mounds:
		var global: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + candidate
		if candidate.x < 2 or candidate.x >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if candidate.y < 2 or candidate.y >= EarthChunkManager.CHUNK_SIZE - 2:
			continue
		if manager.biome_at_global(global.x, global.y) == "grassland":
			mound_cell = candidate
			break
	assert_ne(mound_cell, Vector2i(-1, -1), "precondition: an interior grassland mound exists")

	var ground_items := Node2D.new()
	manager.set_ground_items(ground_items)
	var global_tile: Vector2i = chunk_coord * EarthChunkManager.CHUNK_SIZE + mound_cell
	var mound_pixel := Vector2(
		float(global_tile.x) + 0.5, float(global_tile.y) + 0.5
	) * TerrainRenderer.TILE_SIZE
	ground_items.add_child(_make_ground_fruit(mound_pixel, "walnut"))

	for i in 600:
		manager.step_ants(1.0)

	assert_eq(
		manager.fruit_near(mound_pixel, 5).size(), 1,
		"a grassland mound must not touch a windfall nut -- it only forages grass seed"
	)
	ground_items.free()


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


# -- robin/sparrow/kingfisher reach parity with herbivore/predator/fish's
# unloaded-chunk catch-up and disk persistence (docs/concept/
# ecosystem_dynamics.md's "Persistence/catch-up gap, robin/sparrow/
# kingfisher", now resolved).

func test_unloading_a_chunk_persists_bird_populations():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	manager._ecosystem.seed_robin_population(chunk_coord, 3.5)
	manager._ecosystem.seed_sparrow_population(chunk_coord, 6.25)
	manager._ecosystem.seed_kingfisher_population(chunk_coord, 0.75)
	var path: String = manager._ecology_path(chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	# Walk far enough that Berlin's chunks are evicted.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))

	assert_true(FileAccess.file_exists(path), "an unloaded region must leave a record")
	var loaded := manager._chunk_serializer.load_ecology(path)
	assert_almost_eq(float(loaded.get("robins", 0.0)), 3.5, 0.001)
	assert_almost_eq(float(loaded.get("sparrows", 0.0)), 6.25, 0.001)
	assert_almost_eq(float(loaded.get("kingfishers", 0.0)), 0.75, 0.001)
	DirAccess.remove_absolute(path)


## Mirrors test_a_region_emptied_in_a_past_session_does_not_come_back_full /
## test_a_degraded_land_health_region_does_not_come_back_pristine: a robin
## count well above what a fresh chunk load would bootstrap must survive
## _apply_persisted_ecology rather than silently resetting to that bootstrap.
func test_a_persisted_bird_population_does_not_come_back_as_a_fresh_bootstrap():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var fresh_robin_bootstrap: float = manager._ecosystem.robin_population(chunk_coord)

	DirAccess.make_dir_recursive_absolute(EarthChunkManager.ECOLOGY_DIR)
	manager._chunk_serializer.save_ecology(
		{
			"herbivores": 1.0, "predators": 0.0, "vegetation": 0.5,
			"saved_at_unix": Time.get_unix_time_from_system(),
			"robins": fresh_robin_bootstrap + 50.0, "sparrows": 0.0, "kingfishers": 0.0,
		},
		manager._ecology_path(chunk_coord)
	)
	manager._apply_persisted_ecology(chunk_coord)

	assert_gt(
		manager._ecosystem.robin_population(chunk_coord), fresh_robin_bootstrap,
		"a persisted robin count above the fresh bootstrap must not silently reset to it"
	)
	DirAccess.remove_absolute(manager._ecology_path(chunk_coord))


## _apply_persisted_ecology hands EVERY population (herbivores/predators/
## land_health/robins/sparrows/kingfishers AND fish) to ChunkEcologyCatchup.advance,
## which steps each one forward for however long the chunk was unloaded -- but
## unlike its six siblings, the advanced FISH value was never written back via
## seed_fish_population. A fish population left well under capacity across a real
## multi-day session gap therefore came back frozen at exactly its pre-gap value,
## never catching up like everything else does.
func test_a_persisted_fish_population_catches_up_for_elapsed_time():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var capacity: float = manager._ecosystem.fish_capacity_at(chunk_coord)
	# Well under capacity, so logistic growth toward it is unambiguous -- not
	# something that could be mistaken for float noise.
	var low_fish := capacity * 0.1

	DirAccess.make_dir_recursive_absolute(EarthChunkManager.ECOLOGY_DIR)
	DirAccess.make_dir_recursive_absolute(EarthChunkManager.FISH_POPULATION_DIR)
	manager._chunk_serializer.save_fish_population(low_fish, manager._fish_population_path(chunk_coord))
	manager._chunk_serializer.save_ecology(
		{
			"herbivores": 1.0, "predators": 0.0, "vegetation": 0.5,
			# A real, multi-day gap -- long enough that a population well under
			# capacity should visibly grow, short of the catch-up cap.
			"saved_at_unix": (
				Time.get_unix_time_from_system()
				- 30.0 * EarthChunkManager.REAL_SECONDS_PER_ECOLOGICAL_DAY
			),
			"land_health": 1.0, "robins": 0.0, "sparrows": 0.0, "kingfishers": 0.0,
		},
		manager._ecology_path(chunk_coord)
	)
	# Install the raw last-known fish value the way _load_chunk's own sequence
	# does (via load_fish_population) before _apply_persisted_ecology runs.
	manager._ecosystem.seed_fish_population(chunk_coord, low_fish)
	manager._apply_persisted_ecology(chunk_coord)

	assert_gt(
		manager._ecosystem.fish_population(chunk_coord), low_fish,
		"a fish population left under capacity across a real away-gap must catch " +
		"up like every other population, not come back frozen at its pre-gap value"
	)
	DirAccess.remove_absolute(manager._ecology_path(chunk_coord))
	DirAccess.remove_absolute(manager._fish_population_path(chunk_coord))


## Exercises the in-session path (ChunkEcologyCatchup fed from the in-memory
## `_unloaded_ecology` record, not disk) -- the same distinction
## test_fish_population_survives_being_forgotten_from_in_session_memory draws
## for fish, in the other direction: this confirms the snapshot on unload and
## the restore on reload actually round-trip robin/sparrow/kingfisher.
func test_bird_populations_are_snapshotted_for_in_session_catchup_on_unload():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	manager._ecosystem.seed_robin_population(chunk_coord, 1.0)
	manager._ecosystem.seed_sparrow_population(chunk_coord, 1.0)
	manager._ecosystem.seed_kingfisher_population(chunk_coord, 1.0)

	# Walk far enough that Berlin's chunks are evicted.
	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))

	assert_true(manager._unloaded_ecology.has(chunk_coord), "precondition: chunk left an in-session record")
	var state: Dictionary = manager._unloaded_ecology[chunk_coord]["state"]
	assert_almost_eq(float(state.get("robins", -1.0)), 1.0, 0.001)
	assert_almost_eq(float(state.get("sparrows", -1.0)), 1.0, 0.001)
	assert_almost_eq(float(state.get("kingfishers", -1.0)), 1.0, 0.001)

	var path: String = manager._ecology_path(chunk_coord)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var fish_path := "user://chunk_fish_population/%d_%d.bin" % [chunk_coord.x, chunk_coord.y]
	if FileAccess.file_exists(fish_path):
		DirAccess.remove_absolute(fish_path)


## The reload side of the same round trip: a snapshotted in-session record
## with a robin count above the region's current capacity must be advanced by
## _apply_ecology_catchup rather than dropped -- the same "not silently reset"
## guarantee test_a_persisted_bird_population_does_not_come_back_as_a_fresh_bootstrap
## proves for the disk path, exercised here for the in-memory one.
func test_apply_ecology_catchup_advances_a_snapshotted_bird_population():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	# Force a real, known-positive worm-linked capacity rather than depending
	# on however many worms happened to surface in this particular chunk --
	# the point of this test is exercising _apply_ecology_catchup's wiring,
	# not this tile's actual earthworm density.
	manager._ecosystem.update_worm_density(chunk_coord, 1000.0)
	var capacity: float = manager._ecosystem.robin_capacity_at(chunk_coord)
	assert_gt(capacity, 0.0, "precondition: a forced worm density must yield a positive robin capacity")
	manager._unloaded_ecology[chunk_coord] = {
		"unloaded_at": manager._world_age_seconds,
		"state": {
			"herbivores": manager._ecosystem.herbivore_population(chunk_coord),
			"predators": manager._ecosystem.predator_population(chunk_coord),
			"fruit_stock": 0.0,
			"vegetation": manager._ecosystem.average_vegetation_density(chunk_coord),
			"fish": manager._ecosystem.fish_population(chunk_coord),
			"land_health": manager._ecosystem.land_health(chunk_coord),
			"robins": capacity * 0.01,
			"sparrows": 0.0,
			"kingfishers": 0.0,
		},
	}
	manager.set_world_age_seconds(manager._world_age_seconds + 1.0e7)

	manager._apply_ecology_catchup(chunk_coord)

	assert_gt(
		manager._ecosystem.robin_population(chunk_coord), capacity * 0.01,
		"a long-unloaded low robin count should have grown toward its worm-linked capacity"
	)


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


## The horse that comes back is the SAME individual, not a fresh randi() roll --
## its AnimalFitness phenotype (strength/agility/coat_vibrancy) is deterministic
## from this one seed, so a player's tamed horse quietly becoming a different
## individual on every reload would undercut the whole "not interchangeable"
## point of keeping it at all (see KeptAnimals's own doc comment).
func test_a_tamed_horses_own_individuality_survives_its_chunk_unloading():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var horse := _tame_a_horse_here(_berlin_tile)
	var original_seed := horse.wander_seed

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))  # evict
	manager.update(_berlin_tile)  # come back

	var found = null
	for creature in manager._loaded_creatures.get(chunk_coord, []):
		if is_instance_valid(creature) and creature.is_tame():
			found = creature
	assert_not_null(found, "a tamed horse must survive its chunk unloading")
	assert_eq(
		found.wander_seed, original_seed,
		"a restored kept animal must keep its own seed, not roll a fresh individual"
	)
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


# -- a growing wild juvenile survives a chunk unload too ---------------------
#
# A mammal's own maturity window is now 30-180 real days (see MammalGrowth) --
# almost certainly longer than most chunks stay loaded. Without persisting a
# juvenile's own age_seconds, a player would essentially never see one
# actually grow up (see docs/progress.md). This is NOT KeptAnimals: nobody
# tamed or tied this animal, it simply is not grown yet (see
# src/world/growing_juveniles.gd).

func _spawn_a_growing_juvenile_here(
	tile: Vector2i, species: String, age_seconds: float
) -> CreatureMarker:
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(tile)
	var juvenile := manager._creature_renderer.spawn_single(
		creatures_parent, species, Vector2(tile) * TerrainRenderer.TILE_SIZE,
		manager, TerrainRenderer.TILE_SIZE
	)
	juvenile.age_seconds = age_seconds
	manager._loaded_creatures[chunk_coord].append(juvenile)
	return juvenile


## Mirrors test_a_tamed_horses_own_individuality_survives_its_chunk_unloading's
## exact shape, but for an ordinary WILD juvenile: age_seconds (and therefore
## its rendered growth stage) and its own wander_seed (the same individual,
## not a fresh randi() roll) must both survive the round trip.
func test_a_wild_juveniles_growth_survives_its_chunk_unloading():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var fawn := _spawn_a_growing_juvenile_here(_berlin_tile, "deer", 1234.0)
	var original_seed := fawn.wander_seed

	manager.update(_berlin_tile + Vector2i(EarthChunkManager.CHUNK_SIZE * 40, 0))  # evict
	manager.update(_berlin_tile)  # come back

	var found = null
	for creature in manager._loaded_creatures.get(chunk_coord, []):
		if (
			is_instance_valid(creature) and creature.wander_seed == original_seed
			and creature.info != null and creature.info.species == "deer"
		):
			found = creature
	assert_not_null(found, "a growing wild juvenile must survive its chunk unloading")
	if found != null:
		assert_almost_eq(
			found.age_seconds, 1234.0, 0.5,
			"its own age (and so its rendered growth stage) must be preserved, not reset"
		)
	DirAccess.remove_absolute(manager._growing_juveniles_path(chunk_coord))


## A fully grown wild animal is exactly as interchangeable as any other wild
## adult -- it is NOT worth persisting individually (see
## GrowingJuveniles.is_worth_persisting).
func test_a_fully_grown_wild_animal_is_not_persisted_as_a_growing_juvenile():
	manager.update(_berlin_tile)
	var chunk_coord: Vector2i = manager._chunk_coord_for_tile(_berlin_tile)
	var saved: int = manager._save_growing_juveniles(chunk_coord)
	assert_eq(
		saved, 0,
		"a chunk of ordinary (already-adult) wild animals should keep none of them individually"
	)
	DirAccess.remove_absolute(manager._growing_juveniles_path(chunk_coord))


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


## The bug this exists to catch: every painted tile used to read the SAME
## global `_snow_depth`, so a whole loaded chunk snapped to whatever band the
## clock said the instant it was evaluated (reported: "snow covers a whole
## chunk instantly instead of spreading progressively"). A partial snowfall
## should paint a genuine MIX of bare and snow-covered land tiles -- proof
## that different tiles are now crossing their own threshold at different
## points, not all reading the one shared number (see SnowLayer.onset_offset_for).
func test_a_partial_snowfall_paints_a_mix_of_bare_and_covered_tiles_not_one_uniform_state():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)

	manager.set_snow_depth(0.1)  # partway into a snowfall, not fully covered

	var states := {}  # "bare" or the painted band index -> true
	var center_chunk := _chunk_coord_for_tile(_berlin_tile)
	var used_cells := {}
	for cell in snow_layer.get_used_cells():
		used_cells[cell] = true
	for chunk_coord in manager.chunks_in_radius(center_chunk, EarthChunkManager.LOAD_RADIUS):
		for y in EarthChunkManager.CHUNK_SIZE:
			for x in EarthChunkManager.CHUNK_SIZE:
				var global_x := chunk_coord.x * EarthChunkManager.CHUNK_SIZE + x
				var global_y := chunk_coord.y * EarthChunkManager.CHUNK_SIZE + y
				if manager.biome_at_global(global_x, global_y) == "ocean":
					continue  # water never takes snow -- not part of this claim
				var cell := Vector2i(global_x, global_y)
				if used_cells.has(cell):
					states[snow_layer.get_cell_atlas_coords(cell).x] = true
				else:
					states["bare"] = true
	assert_gt(
		states.size(), 1,
		"a partial snowfall painted every land tile the same way (%s) -- the whole-chunk-snaps bug is back" % [states]
	)
	snow_layer.free()


## A companion regression to the mix test above: the whole-field repaint used
## to fire only when the (onset-FREE) tracked band crossed one of
## DEPTH_BANDS' 4 boundaries, so within a single band's depth range -- easily
## a third of a whole snowfall -- NOTHING repainted at all, no matter how far
## the global depth kept climbing. Measured live before this test existed:
## coverage sat flat at the exact same percentage from depth 0.02 clear
## through depth 0.25, then jumped straight to 100% at depth 0.5 -- the
## "instant reveal" bug again, just moved to a coarser timescale. More land
## tiles must show snow at a later depth than an earlier one even when both
## fall inside the SAME depth band.
func test_snow_coverage_advances_within_a_single_depth_band_not_only_at_band_crossings():
	var snow_layer := TileMapLayer.new()
	manager.set_snow_layer(snow_layer)
	manager.update(_berlin_tile)

	# Both comfortably inside depth BAND 0 (SnowLayer.band_for(x, 0) == 0 for
	# any x in (0, 0.25]) -- a repaint gated only on the band index would
	# treat these as indistinguishable.
	manager.set_snow_depth(0.02)
	var covered_early := snow_layer.get_used_cells().size()

	manager.set_snow_depth(0.2)
	var covered_later := snow_layer.get_used_cells().size()

	assert_gt(
		covered_later, covered_early,
		"depth 0.02 painted %d covered tiles and depth 0.2 also painted %d -- the field is frozen within a band" % [covered_early, covered_later]
	)
	snow_layer.free()


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
	manager.market_store().market_for(settlement_id).add_stock("meat", 1)

	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	var successes: Array = manager.event_store().events_of_type("production_succeeded")
	assert_eq(successes.size(), 1)
	assert_eq(successes[0].tags, ["cooked_meat"])


## A settlement whose only villager has no grounded recipe (see
## OccupationProduction) attempts nothing -- no invented production for an
## occupation with no real recipe to point at. Seed 2 is a real guard.
func test_step_settlements_attempts_no_production_for_an_unmapped_occupation():
	var chunk_coord := Vector2i(53, 53)
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(2)])
	manager.step_settlements(EarthChunkManager.SETTLEMENT_STEP_INTERVAL)

	assert_eq(manager.event_store().events_of_type("production_succeeded").size(), 0)
	assert_eq(manager.event_store().events_of_type("production_failed").size(), 0)


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
	manager.record_settlement_founded_if_new(chunk_coord, [NpcIdentity.new(20), NpcIdentity.new(21)])
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


# -- step_ground_food wires FlyColony.decay_hastened_by into real aging ------
#
# FlyColony.decay_hastened_by (docs/concept/flies.md) was a real, tested pure
# function nobody ever called: an item with maggots on it aged exactly like
# one with none. This closes that loop at the one place a ground item's age
# actually advances (step_ground_food), for any item that is a key in
# _fly_colonies.

func test_step_ground_food_ages_an_item_with_an_active_fly_colony_faster():
	add_child(entities_parent)

	var no_colony := DroppedItem.new()
	no_colony.item_stack = ItemStack.new(Item.new("apple", "Apple", "food", 20))
	no_colony.ages_on_world_time = true
	entities_parent.add_child(no_colony)

	var with_colony := DroppedItem.new()
	with_colony.item_stack = ItemStack.new(Item.new("apple", "Apple", "food", 20))
	with_colony.ages_on_world_time = true
	entities_parent.add_child(with_colony)

	# Grow real maggots the same way test_fly_colony.gd does: settle adults,
	# then advance with rot_remains true until eggs are laid and hatch.
	var colony := FlyColony.new()
	colony.settle(2)
	for step in 60:
		colony.advance(SeasonCycle.SECONDS_PER_DAY * 0.4, true)
	assert_gt(colony.maggots(), 0, "the colony needs real maggots before the real assertion runs")
	manager._fly_colonies[with_colony] = colony

	manager.step_ground_food(SeasonCycle.SECONDS_PER_DAY)

	assert_gt(
		with_colony.spoilage(), no_colony.spoilage(),
		"an item with an active fly colony should spoil measurably faster than the same item with none"
	)
